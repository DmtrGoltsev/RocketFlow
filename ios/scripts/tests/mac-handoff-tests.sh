#!/usr/bin/env bash

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
case "$SCRIPT_SOURCE" in
  */*) SCRIPT_PARENT="${SCRIPT_SOURCE%/*}" ;;
  *) SCRIPT_PARENT="." ;;
esac
SCRIPT_DIR="$(cd "$SCRIPT_PARENT" && pwd -P)" \
  || { printf 'not ok - test script directory canonicalization failed\n' >&2; exit 1; }
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)" \
  || { printf 'not ok - test repository root canonicalization failed\n' >&2; exit 1; }
unset SCRIPT_SOURCE SCRIPT_PARENT
SCRIPTS="$REPO_ROOT/ios/scripts"
# shellcheck source=../mac-handoff-common.sh
source "$SCRIPTS/mac-handoff-common.sh"

TEMP_ROOT=""
REPO_TEMP=""
UNIGNORED_CONFIG=""
UNIGNORED_PLIST=""
REPO_HANDOFF_CREATED=false
DERIVED_FIXTURE=""
DERIVED_ROOT_CREATED=false

cleanup() {
  cleanup_private_temp_file "$UNIGNORED_CONFIG" || true
  cleanup_private_temp_file "$UNIGNORED_PLIST" || true
  cleanup_private_temp_dir "$DERIVED_FIXTURE" || true
  cleanup_private_temp_dir "$REPO_TEMP" || true
  cleanup_private_temp_dir "$TEMP_ROOT" || true
  if [[ "$DERIVED_ROOT_CREATED" == true ]]; then
    rmdir -- "$REPO_ROOT/ios/DerivedData" 2>/dev/null || true
  fi
  if [[ "$REPO_HANDOFF_CREATED" == true ]]; then
    rmdir -- "$REPO_ROOT/ios/.handoff" 2>/dev/null || true
  fi
}
trap cleanup EXIT

CANONICAL_TEMP_PARENT="$(canonical_temp_root)" || exit $?
TEMP_ROOT="$(create_private_temp_dir rocketflow-handoff-tests)" || exit $?
if [[ ! -e "$REPO_ROOT/ios/.handoff" ]]; then
  mkdir -m 700 "$REPO_ROOT/ios/.handoff"
  REPO_HANDOFF_CREATED=true
fi
REPO_HANDOFF_ROOT="$(canonical_existing_directory "$REPO_ROOT/ios/.handoff" "Test handoff root")" || exit $?
REPO_TEMP="$(create_private_temp_dir_at "$REPO_HANDOFF_ROOT" rocketflow-contract)" || exit $?
CONFIG_ROOT="$(canonical_existing_directory "$REPO_ROOT/ios/Config" "iOS config root")" || exit $?
UNIGNORED_CONFIG="$(create_private_temp_file_at "$CONFIG_ROOT" rocketflow-unignored-config)" || exit $?
UNIGNORED_PLIST="$(create_private_temp_file_at "$CONFIG_ROOT" rocketflow-unignored-plist)" || exit $?

TEST_BIN="$TEMP_ROOT/test-bin"
mkdir -p "$TEST_BIN"
if ! python3 -c 'raise SystemExit(0)' >/dev/null 2>&1; then
  python_fallback="$(command -v python || true)"
  [[ -n "$python_fallback" ]] || {
    printf 'not ok - a working python3 or python is required for plist fixtures\n' >&2
    exit 1
  }
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$python_fallback" >"$TEST_BIN/python3"
  chmod +x "$TEST_BIN/python3"
  export PATH="$TEST_BIN:$PATH"
fi

passed=0
skipped=0
LAST_OUTPUT=""
SECRET_MARKER="SECRET-MARKER-DO-NOT-PRINT"

pass() {
  passed=$((passed + 1))
  printf 'ok %d - %s\n' "$passed" "$1"
}

skip() {
  passed=$((passed + 1))
  skipped=$((skipped + 1))
  printf 'ok %d - %s # SKIP %s\n' "$passed" "$1" "$2"
}

sanitize_last_output() {
  local diagnostic="${LAST_OUTPUT:-}"
  local marker
  for marker in \
    "${CANONICAL_TEMP_PARENT:-}" "${TMPDIR:-/tmp}" "${TEMP_ROOT:-}" "${REPO_TEMP:-}" \
    "${DEVICE_ID:-}" "A1B2C3D4E5" "com.acme.personal.rocketflow" \
    "${SECRET_MARKER:-}" "contract-leaf-certificate" "foreign-leaf-certificate"; do
    [[ -n "$marker" ]] && diagnostic="${diagnostic//"$marker"/<redacted>}"
  done
  printf '%s' "$diagnostic"
}

fail() {
  local diagnostic
  diagnostic="$(sanitize_last_output)"
  printf 'not ok - %s\n' "$1" >&2
  [[ -z "$diagnostic" ]] || printf 'diagnostic: %s\n' "$diagnostic" >&2
  exit 1
}

expect_success() {
  local name="$1"
  shift
  LAST_OUTPUT="$("$@" 2>&1)" || fail "$name"
  pass "$name"
}

expect_failure_matching() {
  local name="$1"
  local pattern="$2"
  shift 2
  if LAST_OUTPUT="$("$@" 2>&1)"; then
    fail "$name (unexpected success)"
  fi
  [[ "$LAST_OUTPUT" == *"$pattern"* ]] || fail "$name (unexpected error contract)"
  pass "$name"
}

assert_output_excludes() {
  local name="$1"
  local marker="$2"
  [[ "$LAST_OUTPUT" != *"$marker"* ]] || fail "$name"
}

assert_single_primary_error() {
  local name="$1"
  local expected="$2"
  local diagnostic count
  diagnostic="$(sanitize_last_output)"
  count="$(printf '%s\n' "$diagnostic" | awk '/^error: / { count++ } END { print count + 0 }')"
  [[ "$count" == "1" && "$diagnostic" == *"error: $expected"* ]] || fail "$name"
  [[ "$diagnostic" != *"unbound variable"* && "$diagnostic" != *"must be a regular directory"* ]] \
    || fail "$name"
  pass "$name"
}

assert_file_line() {
  local name="$1"
  local file="$2"
  local line="$3"
  grep -Fqx -- "$line" "$file" || fail "$name"
  pass "$name"
}

assert_argv_pair() {
  local name="$1"
  local file="$2"
  local first="$3"
  local second="$4"
  awk -v first="ARG:$first" -v second="ARG:$second" '
    previous == first && $0 == second { found = 1 }
    { previous = $0 }
    END { exit !found }
  ' "$file" || fail "$name"
  pass "$name"
}

assert_exact_call() {
  local name="$1"
  local file="$2"
  shift 2
  local argument line expected="" current="" found=false
  for argument in "$@"; do
    expected+=$'\034'"$argument"
  done
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == "CALL" ]]; then
      if [[ "$current" == "$expected" ]]; then found=true; fi
      current=""
    elif [[ "$line" == ARG:* ]]; then
      current+=$'\034'"${line#ARG:}"
    fi
  done <"$file"
  if [[ "$current" == "$expected" ]]; then found=true; fi
  [[ "$found" == true ]] || fail "$name"
  pass "$name"
}

argv_value_after() {
  local file="$1"
  local key="$2"
  awk -v key="ARG:$key" '
    previous == key { sub(/^ARG:/, ""); print; exit }
    { previous = $0 }
  ' "$file"
}

assert_exact_argv() {
  local name="$1"
  local file="$2"
  shift 2
  local argument line expected="" actual=""
  for argument in "$@"; do expected+=$'\034'"$argument"; done
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == ARG:* ]] && actual+=$'\034'"${line#ARG:}"
  done <"$file"
  [[ "$actual" == "$expected" ]] || fail "$name"
  pass "$name"
}

write_config() {
  local path="$1"
  local team="$2"
  local bundle="$3"
  cat >"$path" <<EOF
DEVELOPMENT_TEAM = $team
PRODUCT_BUNDLE_IDENTIFIER = $bundle
CODE_SIGN_STYLE = Automatic
CODE_SIGNING_ALLOWED = YES
CODE_SIGNING_REQUIRED = YES
EOF
  chmod 600 "$path" 2>/dev/null || true
}

write_firebase_plist() {
  local path="$1"
  local bundle="$2"
  python3 - "$path" "$bundle" <<'PY'
import plistlib
import sys

payload = {
    "BUNDLE_ID": sys.argv[2],
    "GOOGLE_APP_ID": "contract-test-app-id",
    "GCM_SENDER_ID": "contract-test-sender",
    "PROJECT_ID": "contract-test-project",
    "API_KEY": "contract-test-api-key",
}
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(payload, stream)
PY
  chmod 600 "$path" 2>/dev/null || true
}

write_info_plist() {
  local path="$1"
  local bundle="$2"
  local api="$3"
  local ats_http="$4"
  local ats_subdomains="$5"
  local variant="${6:-exact}"
  python3 - "$path" "$bundle" "$api" "$ats_http" "$ats_subdomains" "$variant" <<'PY'
import plistlib
import sys

domain_policy = {
    "NSExceptionAllowsInsecureHTTPLoads": sys.argv[4] == "true",
    "NSIncludesSubdomains": sys.argv[5] == "true",
}
domains = {"45.10.110.42": domain_policy}
ats = {"NSExceptionDomains": domains}
platforms = ["iPhoneOS"]
variant = sys.argv[6]
if variant == "broad":
    ats["NSAllowsArbitraryLoads"] = True
elif variant == "broad-variants":
    ats["NSAllowsArbitraryLoadsForMedia"] = True
    ats["NSAllowsArbitraryLoadsInWebContent"] = True
elif variant == "extra-domain":
    domains["example.invalid"] = dict(domain_policy)
elif variant == "extra-key":
    domain_policy["NSExceptionMinimumTLSVersion"] = "TLSv1.0"
elif variant == "simulator":
    platforms = ["iPhoneSimulator"]
payload = {
    "CFBundleIdentifier": sys.argv[2],
    "CFBundleSupportedPlatforms": platforms,
    "RocketFlowAPIBaseURL": sys.argv[3],
    "NSAppTransportSecurity": ats,
}
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(payload, stream)
PY
}

create_app() {
  local app="$1"
  local bundle="$2"
  local api="${3:-http://45.10.110.42/rocket-api}"
  local ats_http="${4:-true}"
  local ats_subdomains="${5:-false}"
  local firebase_bundle="${6:-}"
  local variant="${7:-exact}"
  mkdir -p "$app"
  write_info_plist "$app/Info.plist" "$bundle" "$api" "$ats_http" "$ats_subdomains" "$variant"
  printf 'mock embedded profile\n' >"$app/embedded.mobileprovision"
  if [[ -n "$firebase_bundle" ]]; then
    write_firebase_plist "$app/GoogleService-Info.plist" "$firebase_bundle"
  fi
}

for script in mac-preflight.sh mac-verify.sh mac-build-device.sh mac-install-device.sh; do
  expect_success "$script help" bash "$SCRIPTS/$script" --help
done
LAST_OUTPUT=""

SUBSTITUTION_AUDIT="$TEMP_ROOT/command-substitution-audit.py"
cat >"$SUBSTITUTION_AUDIT" <<'PY'
import argparse
import pathlib
import re
import sys

assignment = re.compile(
    r'^\s*(?:if\s+!?\s*)?(?:local\s+)?[A-Za-z_][A-Za-z0-9_]*="\$\((?!\()'
)


def has_unescaped_continuation(line):
    if not line.endswith("\\"):
        return False
    trailing = len(line) - len(line.rstrip("\\"))
    return trailing % 2 == 1


parser = argparse.ArgumentParser()
parser.add_argument("--minimum-count", type=int, default=1)
parser.add_argument("--expected-count", type=int)
parser.add_argument("--allow", action="append", default=[])
parser.add_argument("paths", nargs="+")
args = parser.parse_args()

allowlist = set()
for entry in args.allow:
    name, separator, raw_line = entry.rpartition(":")
    if not separator or not name or not raw_line.isdigit():
        raise SystemExit("invalid audit allowlist entry")
    allowlist.add((name, int(raw_line)))

failures = []
parse_failures = []
audited = 0
for raw_path in args.paths:
    path = pathlib.Path(raw_path)
    lines = path.read_text(encoding="utf-8").splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        if not assignment.match(line):
            index += 1
            continue
        start = index + 1
        block = line
        physical_lines = 1
        closed = ')"' in line
        while (not closed or has_unescaped_continuation(lines[index])) and index + 1 < len(lines):
            if physical_lines >= 64:
                parse_failures.append(f"{path.name}:{start}:logical command exceeds 64 lines")
                break
            index += 1
            block += "\n" + lines[index]
            physical_lines += 1
            closed = closed or ')"' in lines[index]
        if not closed:
            parse_failures.append(f"{path.name}:{start}:unterminated assignment substitution")
        audited += 1
        stripped = block.lstrip()
        closing = block.rfind(')"')
        suffix = block[closing + 2:] if closing >= 0 else ""
        guarded = stripped.startswith("if ") or re.search(r'(^|\s)\|\|(?=\s|$)', suffix) is not None
        key = (path.name, start)
        if not guarded and key not in allowlist:
            failures.append(f"{path.name}:{start}")
        index += 1
if parse_failures:
    raise SystemExit("command substitution audit parse failures: " + ", ".join(parse_failures))
if args.expected_count is not None and audited != args.expected_count:
    raise SystemExit(f"static substitution audit expected {args.expected_count}, audited {audited}")
if audited < args.minimum_count:
    raise SystemExit("static substitution audit matched too few assignments")
if failures:
    raise SystemExit("unchecked assignment command substitutions: " + ", ".join(failures))
print(f"audited={audited} allowlisted={len(allowlist)}")
PY
chmod 600 "$SUBSTITUTION_AUDIT"

AUDIT_FIXTURES="$TEMP_ROOT/Command Substitution Audit Fixtures"
mkdir -p "$AUDIT_FIXTURES"

guarded_multiline_fixture="$AUDIT_FIXTURES/guarded-multiline.sh"
: >"$guarded_multiline_fixture"
fixture_index=1
while [[ "$fixture_index" -le 25 ]]; do
  printf 'guarded_%02d="$(printf %%s value)" \\\n  || return $?\n' \
    "$fixture_index" >>"$guarded_multiline_fixture"
  fixture_index=$((fixture_index + 1))
done
expect_success "static audit accepts 25 guarded multiline assignments" \
  python3 "$SUBSTITUTION_AUDIT" --expected-count 25 "$guarded_multiline_fixture"
[[ "$LAST_OUTPUT" == "audited=25 allowlisted=0" ]] \
  || fail "guarded multiline audit count is not independent"
pass "guarded multiline audit reports exact count with empty allowlist"

unguarded_fixture="$AUDIT_FIXTURES/unguarded-twin.sh"
cat >"$unguarded_fixture" <<'EOF'
guarded="$(printf %s value)" \
  || return $?
unguarded="$(printf %s value)"
EOF
expect_failure_matching "static audit rejects an otherwise identical unguarded assignment" \
  "unchecked assignment command substitutions: unguarded-twin.sh:3" \
  python3 "$SUBSTITUTION_AUDIT" --expected-count 2 "$unguarded_fixture"

guard_forms_fixture="$AUDIT_FIXTURES/guard-forms.sh"
cat >"$guard_forms_fixture" <<'EOF'
one_line="$(printf %s value)" || return $?
quoted_backslash="$(printf '%s' '\')" || return $?
if conditional="$(printf %s value)"; then
  :
fi
EOF
expect_success "static audit accepts one-line, quoted-backslash, and if guards" \
  python3 "$SUBSTITUTION_AUDIT" --expected-count 3 "$guard_forms_fixture"

escaped_continuation_fixture="$AUDIT_FIXTURES/escaped-continuation.sh"
cat >"$escaped_continuation_fixture" <<'EOF'
escaped="$(printf %s value)" \\
  || return $?
EOF
expect_failure_matching "static audit does not treat an escaped trailing backslash as continuation" \
  "unchecked assignment command substitutions: escaped-continuation.sh:1" \
  python3 "$SUBSTITUTION_AUDIT" --expected-count 1 "$escaped_continuation_fixture"

allowlist_fixture="$AUDIT_FIXTURES/allowlist-isolation.sh"
cat >"$allowlist_fixture" <<'EOF'
known="$(printf %s value)"
guarded="$(printf %s value)" || return $?
new_unchecked="$(printf %s value)"
EOF
expect_failure_matching "static audit allowlist does not mask newly added assignments" \
  "unchecked assignment command substitutions: allowlist-isolation.sh:3" \
  python3 "$SUBSTITUTION_AUDIT" --expected-count 3 \
    --allow "allowlist-isolation.sh:1" "$allowlist_fixture"

expect_failure_matching "static audit known count is checked independently" \
  "static substitution audit expected 2, audited 3" \
  python3 "$SUBSTITUTION_AUDIT" --expected-count 2 \
    --allow "allowlist-isolation.sh:1" --allow "allowlist-isolation.sh:3" "$allowlist_fixture"

expect_success "security script command substitutions are explicitly guarded" \
  python3 "$SUBSTITUTION_AUDIT" --minimum-count 30 \
    "$SCRIPTS/mac-handoff-common.sh" \
    "$SCRIPTS/mac-preflight.sh" \
    "$SCRIPTS/mac-verify.sh" \
    "$SCRIPTS/mac-build-device.sh" \
    "$SCRIPTS/mac-install-device.sh"

[[ "$CANONICAL_TEMP_PARENT" == "$(cd "${TMPDIR:-/tmp}" && pwd -P)" ]] \
  || fail "temporary root is not physically canonical"
pass "temporary root is physically canonical before mktemp"

expect_success "lexical root is nounset-safe" \
  bash -u -c 'source "$1"; actual="$(lexical_absolute_path /)" || exit $?; [[ "$actual" == / ]]' _ \
    "$SCRIPTS/mac-handoff-common.sh"
expect_success "lexical parent collapse to root is nounset-safe" \
  bash -u -c 'source "$1"; actual="$(lexical_absolute_path /a/..)" || exit $?; [[ "$actual" == / ]]' _ \
    "$SCRIPTS/mac-handoff-common.sh"
expect_success "lexical empty components are nounset-safe" \
  bash -u -c 'source "$1"; actual="$(lexical_absolute_path ////a//../)" || exit $?; [[ "$actual" == / ]]' _ \
    "$SCRIPTS/mac-handoff-common.sh"

temp_root_mode="$(file_mode "$TEMP_ROOT")"
if [[ "${temp_root_mode: -3}" == "700" ]]; then
  pass "private temporary directory is mode 0700"
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      skip "private temporary directory is mode 0700" "Windows filesystem does not preserve POSIX mode bits"
      ;;
    *) fail "private temporary directory mode is not 0700" ;;
  esac
fi

placeholder_config="$TEMP_ROOT/placeholder.xcconfig"
write_config "$placeholder_config" YOUR_TEAM_ID com.acme.personal.rocketflow
expect_failure_matching "placeholder team rejected" "DEVELOPMENT_TEAM must be" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$placeholder_config"

valid_config="$TEMP_ROOT/Config With Spaces/Device Config.xcconfig"
mkdir -p "$(dirname "$valid_config")"
write_config "$valid_config" A1B2C3D4E5 com.acme.personal.rocketflow

permission_bin="$(create_private_temp_dir_at "$TEMP_ROOT" rocketflow-permission-bin)" || exit $?
cat >"$permission_bin/stat" <<'EOF'
#!/usr/bin/env bash
printf '600\n'
EOF
chmod +x "$permission_bin/stat"
expect_success "0600 sensitive input accepted after physical canonicalization" \
  env PATH="$permission_bin:$PATH" \
    bash -c 'source "$1"; canonical_sensitive_input "$2" "Device xcconfig" >/dev/null' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$valid_config"

if [[ "$(uname -s)" == "Darwin" && "$TEMP_ROOT" == /private/var/* ]]; then
  lexical_temp_alias="/var/${TEMP_ROOT#/private/var/}"
  lexical_config_alias="$lexical_temp_alias/Config With Spaces/Device Config.xcconfig"
else
  mkdir -p "$TEMP_ROOT/portable-var-alias"
  lexical_config_alias="$TEMP_ROOT/portable-var-alias/../Config With Spaces/Device Config.xcconfig"
fi
expect_success "lexical macOS temp alias resolves to physical canonical file" \
  bash -c 'source "$1"; actual="$(canonical_existing_file "$2" "Alias fixture")" || exit $?; [[ "$actual" == "$3" ]]' _ \
    "$SCRIPTS/mac-handoff-common.sh" "$lexical_config_alias" "$valid_config"

cat >"$permission_bin/stat" <<'EOF'
#!/usr/bin/env bash
printf '666\n'
EOF
chmod +x "$permission_bin/stat"
expect_failure_matching "group/world writable sensitive input rejected" "must not be group- or world-writable" \
  env PATH="$permission_bin:$PATH" \
    bash -c 'source "$1"; canonical_sensitive_input "$2" "Device xcconfig" >/dev/null' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$valid_config"

config_symlink="$TEMP_ROOT/Device-Config-Symlink.xcconfig"
if ln -s "$valid_config" "$config_symlink" 2>/dev/null && [[ -L "$config_symlink" ]]; then
  expect_failure_matching "final sensitive-input symlink rejected" "readable regular file" \
    bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$config_symlink"
else
  skip "final sensitive-input symlink rejected" "filesystem does not expose symlinks"
fi

FAULT_BIN="$(create_private_temp_dir_at "$TEMP_ROOT" rocketflow-fault-bin)" || exit $?
REAL_MKTEMP="$(command -v mktemp)" || fail "real mktemp lookup failed"
REAL_CHMOD="$(command -v chmod)" || fail "real chmod lookup failed"
REAL_GIT="$(command -v git)" || fail "real git lookup failed"
export REAL_MKTEMP REAL_CHMOD REAL_GIT

cat >"$FAULT_BIN/mktemp" <<'EOF'
#!/usr/bin/env bash
kind="file"
[[ "${1:-}" == "-d" ]] && kind="dir"
if [[ "${MOCK_MKTEMP_FAIL_KIND:-}" == "$kind" ]]; then
  printf '%s\n' "${MOCK_MKTEMP_FAILURE_OUTPUT:-$PWD}"
  exit "${MOCK_MKTEMP_EXIT:-47}"
fi
exec "$REAL_MKTEMP" "$@"
EOF

cat >"$FAULT_BIN/chmod" <<'EOF'
#!/usr/bin/env bash
mode="${1:-}"
target=""
for argument in "$@"; do target="$argument"; done
if [[ -n "${MOCK_CHMOD_FAIL_MODE:-}" && "$mode" == "$MOCK_CHMOD_FAIL_MODE" \
  && "${target##*/}" == rocketflow-fault-* ]]; then
  [[ -z "${MOCK_CHMOD_RECORD:-}" ]] || printf '%s\n' "$target" >"$MOCK_CHMOD_RECORD"
  exit "${MOCK_CHMOD_EXIT:-48}"
fi
exec "$REAL_CHMOD" "$@"
EOF

cat >"$FAULT_BIN/git" <<'EOF'
#!/usr/bin/env bash
subcommand=""
for argument in "$@"; do
  case "$argument" in
    rev-parse|ls-files|check-ignore|status)
      subcommand="$argument"
      break
      ;;
  esac
done
if [[ -n "${MOCK_GIT_FAIL_COMMAND:-}" && "$subcommand" == "$MOCK_GIT_FAIL_COMMAND" ]]; then
  printf '%s\n' "${MOCK_SECRET_MARKER:-git failure}" >&2
  exit "${MOCK_GIT_EXIT:-49}"
fi
exec "$REAL_GIT" "$@"
EOF
"$REAL_CHMOD" +x "$FAULT_BIN/mktemp" "$FAULT_BIN/chmod" "$FAULT_BIN/git"

workspace_before_faults="$(git -C "$REPO_ROOT" status --short --untracked-files=all)" \
  || fail "workspace status before fault injection failed"

expect_failure_matching "mktemp directory failure preserves state" \
  "Private temporary directory creation failed" \
  env PATH="$FAULT_BIN:$PATH" MOCK_MKTEMP_FAIL_KIND=dir MOCK_MKTEMP_EXIT=47 \
    MOCK_MKTEMP_FAILURE_OUTPUT="$REPO_ROOT" \
    bash -c 'source "$1"; before="$(umask)" || exit 80; status=0; result="$(create_private_temp_dir_at "$2" rocketflow-fault-dir)" || status=$?; after="$(umask)" || exit 81; [[ "$status" -eq 47 && "$before" == "$after" && -z "$result" ]] || exit 82; exit "$status"' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$TEMP_ROOT"
assert_output_excludes "mktemp directory failure returned workspace path" "$REPO_ROOT"
assert_single_primary_error "mktemp directory failure has one primary error" \
  "Private temporary directory creation failed."

expect_failure_matching "mktemp file failure preserves state" \
  "Private temporary file creation failed" \
  env PATH="$FAULT_BIN:$PATH" MOCK_MKTEMP_FAIL_KIND=file MOCK_MKTEMP_EXIT=47 \
    MOCK_MKTEMP_FAILURE_OUTPUT="$REPO_ROOT" \
    bash -c 'source "$1"; before="$(umask)" || exit 80; status=0; result="$(create_private_temp_file_at "$2" rocketflow-fault-file)" || status=$?; after="$(umask)" || exit 81; [[ "$status" -eq 47 && "$before" == "$after" && -z "$result" ]] || exit 82; exit "$status"' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$TEMP_ROOT"
assert_output_excludes "mktemp file failure returned workspace path" "$REPO_ROOT"
assert_single_primary_error "mktemp file failure has one primary error" \
  "Private temporary file creation failed."

chmod_dir_record="$TEMP_ROOT/chmod-dir-target"
expect_failure_matching "chmod directory failure removes owned temp" \
  "Private temporary directory permissions could not be applied" \
  env PATH="$FAULT_BIN:$PATH" MOCK_CHMOD_FAIL_MODE=700 MOCK_CHMOD_EXIT=48 \
    MOCK_CHMOD_RECORD="$chmod_dir_record" \
    bash -c 'source "$1"; before="$(umask)" || exit 80; status=0; result="$(create_private_temp_dir_at "$2" rocketflow-fault-dir)" || status=$?; after="$(umask)" || exit 81; target="$(cat "$3")" || exit 82; [[ "$status" -eq 48 && "$before" == "$after" && -z "$result" && ! -e "$target" ]] || exit 83; exit "$status"' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$TEMP_ROOT" "$chmod_dir_record"
assert_single_primary_error "chmod directory failure has one primary error" \
  "Private temporary directory permissions could not be applied."

chmod_file_record="$TEMP_ROOT/chmod-file-target"
expect_failure_matching "chmod file failure removes owned temp" \
  "Private temporary file permissions could not be applied" \
  env PATH="$FAULT_BIN:$PATH" MOCK_CHMOD_FAIL_MODE=600 MOCK_CHMOD_EXIT=48 \
    MOCK_CHMOD_RECORD="$chmod_file_record" \
    bash -c 'source "$1"; before="$(umask)" || exit 80; status=0; result="$(create_private_temp_file_at "$2" rocketflow-fault-file)" || status=$?; after="$(umask)" || exit 81; target="$(cat "$3")" || exit 82; [[ "$status" -eq 48 && "$before" == "$after" && -z "$result" && ! -e "$target" ]] || exit 83; exit "$status"' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$TEMP_ROOT" "$chmod_file_record"
assert_single_primary_error "chmod file failure has one primary error" \
  "Private temporary file permissions could not be applied."

expect_failure_matching "physical parent canonicalization failure is primary" \
  "parent could not be physically canonicalized" \
  bash -c 'source "$1"; pwd() { return 61; }; canonical_existing_file "$2" "Injected path"' _ \
    "$SCRIPTS/mac-handoff-common.sh" "$valid_config"
assert_output_excludes "canonicalization failure returned PWD" "$REPO_ROOT"
assert_single_primary_error "canonicalization failure has one primary error" \
  "Injected path parent could not be physically canonicalized."

for git_failure in \
  'rev-parse:Git repository-root inspection failed.' \
  'ls-files:Git tracked-file inspection failed.' \
  'check-ignore:Git ignore inspection failed.' \
  'status:Git status inspection failed.'; do
  git_command="${git_failure%%:*}"
  git_error="${git_failure#*:}"
  expect_failure_matching "git $git_command failure is fail closed" "$git_error" \
    env PATH="$FAULT_BIN:$PATH" MOCK_GIT_FAIL_COMMAND="$git_command" \
      MOCK_SECRET_MARKER="$SECRET_MARKER" \
      bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$valid_config"
  assert_output_excludes "git $git_command failure leaked command stderr" "$SECRET_MARKER"
  assert_single_primary_error "git $git_command failure has one primary error" "$git_error"
done

workspace_after_faults="$(git -C "$REPO_ROOT" status --short --untracked-files=all)" \
  || fail "workspace status after fault injection failed"
[[ "$workspace_after_faults" == "$workspace_before_faults" ]] \
  || fail "fault injection changed workspace state"
pass "fault injection leaves workspace state unchanged"

unsupported_config="$TEMP_ROOT/unsupported.xcconfig"
write_config "$unsupported_config" A1B2C3D4E5 com.acme.personal.rocketflow
printf 'ROCKETFLOW_API_BASE_URL = https://override.invalid\n' >>"$unsupported_config"
expect_failure_matching "xcconfig API override rejected" "unsupported setting or directive" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$unsupported_config"

write_config "$UNIGNORED_CONFIG" A1B2C3D4E5 com.acme.personal.rocketflow
expect_failure_matching "unignored in-repo config rejected" "must be ignored" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$UNIGNORED_CONFIG"
expect_failure_matching "tracked config rejected" "must not be tracked" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$REPO_ROOT/ios/Config/Base.xcconfig"

ignored_config="$REPO_TEMP/Device Config.xcconfig"
write_config "$ignored_config" A1B2C3D4E5 com.acme.personal.rocketflow
expect_success "ignored in-repo config accepted" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$ignored_config"

missing_plist="$TEMP_ROOT/missing GoogleService-Info.plist"
expect_failure_matching "push missing plist rejected" "Firebase plist must be a readable regular file" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --mode push --config "$valid_config" \
    --firebase-plist "$missing_plist"

write_firebase_plist "$UNIGNORED_PLIST" com.acme.personal.rocketflow
expect_failure_matching "unignored in-repo plist rejected" "must be ignored" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --mode push --config "$valid_config" \
    --firebase-plist "$UNIGNORED_PLIST"
expect_failure_matching "tracked plist rejected" "must not be tracked" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --mode push --config "$valid_config" \
    --firebase-plist "$REPO_ROOT/ios/RocketFlow/Resources/Info.plist"

mismatched_plist="$TEMP_ROOT/Mismatched GoogleService-Info.plist"
matching_plist="$TEMP_ROOT/Matching GoogleService-Info.plist"
write_firebase_plist "$mismatched_plist" com.acme.someone.else
write_firebase_plist "$matching_plist" com.acme.personal.rocketflow
expect_failure_matching "push bundle mismatch rejected" "bundle identifier does not match" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --mode push --config "$valid_config" \
    --firebase-plist "$mismatched_plist"
expect_success "valid outside-repo push inputs accepted" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --mode push --config "$valid_config" \
    --firebase-plist "$matching_plist"
assert_output_excludes "push output leaked Firebase value" "contract-test-api-key"

for ats_variant in broad broad-variants extra-domain extra-key; do
  ats_fixture="$TEMP_ROOT/source-ats-$ats_variant.plist"
  write_info_plist "$ats_fixture" com.acme.personal.rocketflow \
    http://45.10.110.42/rocket-api true false "$ats_variant"
  expect_failure_matching "source ATS rejects $ats_variant" "only the documented host-scoped" \
    bash -c 'source "$1"; validate_exact_ats_contract "$2"' _ \
      "$SCRIPTS/mac-handoff-common.sh" "$ats_fixture"
done

expect_failure_matching "DerivedData root rejected" "protected repository directory" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data /
assert_single_primary_error "root DerivedData emits one primary sanitized error" \
  "DerivedData path targets a protected repository directory."
expect_failure_matching "DerivedData lexical parent collapse to root rejected" \
  "protected repository directory" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data /a/..
assert_single_primary_error "collapsed-root DerivedData emits one primary sanitized error" \
  "DerivedData path targets a protected repository directory."
expect_failure_matching "DerivedData repo root rejected" "protected repository directory" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$REPO_ROOT"
expect_failure_matching "DerivedData ios root rejected" "protected repository directory" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$REPO_ROOT/ios"
for protected in RocketFlow Config scripts RocketFlow.xcodeproj; do
  expect_failure_matching "DerivedData $protected source rejected" "allowed only below ios/DerivedData" \
    bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$REPO_ROOT/ios/$protected"
done
expect_failure_matching "DerivedData traversal into source rejected" "allowed only below ios/DerivedData" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run \
    --derived-data "$REPO_ROOT/ios/DerivedData/new/../../RocketFlow"
expect_success "ignored DerivedData with spaces accepted" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run \
    --derived-data "$REPO_ROOT/ios/DerivedData/Contract Output With Spaces"
expect_success "outside-repo DerivedData accepted" \
  bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$TEMP_ROOT/External Output With Spaces"

mkdir -p "$TEMP_ROOT/canonical-parent"
outside_lexical="$TEMP_ROOT/canonical-parent/../Canonical External Output"
outside_canonical="$TEMP_ROOT/Canonical External Output"
expect_success "outside DerivedData is returned as a canonical physical path" \
  bash -c 'source "$1"; actual="$(validate_derived_data_path "$2")" || exit $?; [[ "$actual" == "$3" ]]' _ \
    "$SCRIPTS/mac-handoff-common.sh" "$outside_lexical" "$outside_canonical"

symlink_real="$TEMP_ROOT/symlink-real"
symlink_path="$TEMP_ROOT/symlink-output"
mkdir -p "$symlink_real"
if ln -s "$symlink_real" "$symlink_path" 2>/dev/null && [[ -L "$symlink_path" ]]; then
  expect_failure_matching "final DerivedData symlink rejected" "symlink or reparse" \
    bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$symlink_path"

  if [[ ! -e "$REPO_ROOT/ios/DerivedData" ]]; then
    mkdir -m 700 "$REPO_ROOT/ios/DerivedData"
    DERIVED_ROOT_CREATED=true
  fi
  derived_root="$(canonical_existing_directory "$REPO_ROOT/ios/DerivedData" "DerivedData test root")" || exit $?
  DERIVED_FIXTURE="$(create_private_temp_dir_at "$derived_root" rocketflow-symlink-fixture)" || exit $?
  repo_escape_link="$DERIVED_FIXTURE/escape-parent"
  ln -s "$TEMP_ROOT" "$repo_escape_link"
  expect_failure_matching "repo DerivedData parent symlink cannot escape trust boundary" \
    "allowed only below ios/DerivedData" \
    bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$repo_escape_link/child"
else
  skip "final DerivedData symlink rejected" "filesystem does not expose symlinks"
  skip "repo DerivedData parent symlink cannot escape trust boundary" "filesystem does not expose symlinks"
fi

MOCK_BIN="$TEMP_ROOT/mock-bin"
MOCK_XCODEBUILD_ARGS="$TEMP_ROOT/xcodebuild-args"
MOCK_RSYNC_ARGS="$TEMP_ROOT/rsync-args"
MOCK_XCRUN_ARGS="$TEMP_ROOT/xcrun-args"
MOCK_CODESIGN_ARGS="$TEMP_ROOT/codesign-args"
MOCK_SECURITY_ARGS="$TEMP_ROOT/security-args"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF

cat >"$MOCK_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
printf '/Applications/Xcode.app/Contents/Developer\n'
EOF

cat >"$MOCK_BIN/xcodegen" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf 'Version: %s\n' "${MOCK_XCODEGEN_VERSION:-2.46.0}"
fi
EOF

cat >"$MOCK_BIN/rsync" <<'EOF'
#!/usr/bin/env bash
: >"$MOCK_RSYNC_ARGS"
source_path=""
destination=""
for argument in "$@"; do
  printf 'ARG:%s\n' "$argument" >>"$MOCK_RSYNC_ARGS"
  source_path="$destination"
  destination="$argument"
done
mkdir -p "${destination%/}"
if [[ "${MOCK_RSYNC_COPY_PROJECT:-0}" == "1" ]]; then
  cp -R "${source_path%/}/RocketFlow.xcodeproj" "${destination%/}/RocketFlow.xcodeproj"
fi
EOF

cat >"$MOCK_BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
{
  printf 'CALL\n'
  for argument in "$@"; do
    printf 'ARG:%s\n' "$argument"
  done
} >>"$MOCK_XCRUN_ARGS"
if [[ -n "${MOCK_XCRUN_STDERR:-}" ]]; then
  printf '%s\n' "$MOCK_XCRUN_STDERR" >&2
fi
if [[ "${1:-}" == "simctl" && "${2:-}" == "list" && "${3:-}" == "devices" \
  && "${4:-}" == "available" && "${5:-}" == "--json" ]]; then
  printf '{"devices":{"contract":[{"isAvailable":true,"name":"iPhone Contract","udid":"%s"}]}}\n' \
    "${MOCK_SIMULATOR_ID:-00008110-0012345678901234}"
  exit 0
fi
if [[ -n "${MOCK_XCRUN_FAIL_MATCH:-}" && " $* " == *" $MOCK_XCRUN_FAIL_MATCH "* ]]; then
  printf '%s\n' "${MOCK_SECRET_MARKER:-mock failure}" >&2
  exit "${MOCK_XCRUN_EXIT:-41}"
fi
EOF

cat >"$MOCK_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
{
  printf 'CALL\n'
  for argument in "$@"; do
    printf 'ARG:%s\n' "$argument"
  done
} >>"$MOCK_CODESIGN_ARGS"
if [[ "${1:-}" == "--verify" ]]; then
  if [[ "${MOCK_CODESIGN_VERIFY_FAIL:-0}" == "1" ]]; then
    printf '%s\n' "${MOCK_SECRET_MARKER:-signature failure}" >&2
    exit 37
  fi
  exit 0
fi
if [[ "${1:-}" == "-d" && "${2:-}" == "--extract-certificates" ]]; then
  printf '%s' "${MOCK_SIGNED_CERTIFICATE:-contract-leaf-certificate}" >"${3}0"
  chmod 600 "${3}0" 2>/dev/null || true
  exit 0
fi
if [[ "${1:-}" == "-d" ]]; then
  python3 - "${MOCK_SIGNED_MODE:-no-push}" \
    "${MOCK_SIGNED_TEAM:-A1B2C3D4E5}" \
    "${MOCK_SIGNED_BUNDLE:-com.acme.personal.rocketflow}" \
    "${MOCK_SIGNED_APS:-development}" <<'PY'
import plistlib
import sys
payload = {
    "com.apple.developer.team-identifier": sys.argv[2],
    "application-identifier": f"{sys.argv[2]}.{sys.argv[3]}",
}
if sys.argv[1] == "push":
    payload["aps-environment"] = sys.argv[4]
plistlib.dump(payload, sys.stdout.buffer)
PY
  exit 0
fi
exit 2
EOF

cat >"$MOCK_BIN/security" <<'EOF'
#!/usr/bin/env bash
{
  printf 'CALL\n'
  for argument in "$@"; do
    printf 'ARG:%s\n' "$argument"
  done
} >>"$MOCK_SECURITY_ARGS"
[[ "${1:-}" == "cms" && "${2:-}" == "-D" && "${3:-}" == "-i" ]] || exit 2
if [[ -n "${MOCK_SECURITY_STDERR:-}" ]]; then
  printf '%s\n' "$MOCK_SECURITY_STDERR" >&2
fi
python3 - \
  "${MOCK_PROFILE_KIND:-development}" \
  "${MOCK_PROFILE_TEAM:-A1B2C3D4E5}" \
  "${MOCK_PROFILE_BUNDLE:-com.acme.personal.rocketflow}" \
  "${MOCK_PROFILE_DEVICE:-00008110-0012345678901234}" \
  "${MOCK_PROFILE_CERTIFICATE:-contract-leaf-certificate}" \
  "${MOCK_PROFILE_APS:-development}" <<'PY'
from datetime import datetime, timedelta
import plistlib
import sys

kind, team, bundle, device, certificate, aps = sys.argv[1:7]
payload = {
    "ExpirationDate": datetime.utcnow() + timedelta(days=-1 if kind == "expired" else 30),
    "ProvisionedDevices": [device],
    "DeveloperCertificates": [certificate.encode("utf-8")],
}
if kind != "adhoc":
    payload["TeamIdentifier"] = [team]
    payload["Entitlements"] = {
        "com.apple.developer.team-identifier": team,
        "application-identifier": f"{team}.{bundle}",
        "get-task-allow": kind != "distribution",
        "aps-environment": aps,
    }
if kind == "enterprise":
    payload["ProvisionsAllDevices"] = True
plistlib.dump(payload, sys.stdout.buffer)
PY
EOF

cat >"$MOCK_BIN/xcodebuild" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_XCODEBUILD_APPEND:-0}" == "1" ]]; then
  printf 'CALL\n' >>"$MOCK_XCODEBUILD_ARGS"
else
  : >"$MOCK_XCODEBUILD_ARGS"
fi
for argument in "$@"; do
  printf 'ARG:%s\n' "$argument" >>"$MOCK_XCODEBUILD_ARGS"
done
case "${1:-}" in
  -version)
    printf 'Xcode 16.4\nBuild version 16F6\n'
    exit 0
    ;;
  -checkFirstLaunchStatus)
    exit 0
    ;;
  -showsdks)
    printf 'iOS SDKs:\n\tiOS %s -sdk iphoneos%s\n' "${MOCK_SDK_VERSION:-18.5}" "${MOCK_SDK_VERSION:-18.5}"
    exit 0
    ;;
  -resolvePackageDependencies)
    exit 0
    ;;
esac

derived=""
project=""
scheme=""
bundle=""
api=""
mode="no-push"
previous=""
for argument in "$@"; do
  if [[ "$previous" == "-derivedDataPath" ]]; then derived="$argument"; fi
  if [[ "$previous" == "-project" ]]; then project="$argument"; fi
  if [[ "$previous" == "-scheme" ]]; then scheme="$argument"; fi
  case "$argument" in
    PRODUCT_BUNDLE_IDENTIFIER=*) bundle="${argument#PRODUCT_BUNDLE_IDENTIFIER=}" ;;
    ROCKETFLOW_API_BASE_URL=*) api="${argument#ROCKETFLOW_API_BASE_URL=}" ;;
    CODE_SIGN_ENTITLEMENTS=RocketFlow/RocketFlow.entitlements) mode="push" ;;
  esac
  previous="$argument"
done
if [[ "$scheme" == "RocketFlow-CI" ]]; then
  exit 0
fi
[[ -n "$derived" && -n "$bundle" && -n "$api" ]] || exit 31
app="$derived/Build/Products/Debug-iphoneos/RocketFlow.app"
mkdir -p "$app"
python3 - "$app/Info.plist" "$bundle" "$api" <<'PY'
import plistlib
import sys
payload = {
    "CFBundleIdentifier": sys.argv[2],
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "RocketFlowAPIBaseURL": sys.argv[3],
    "NSAppTransportSecurity": {
        "NSExceptionDomains": {
            "45.10.110.42": {
                "NSExceptionAllowsInsecureHTTPLoads": True,
                "NSIncludesSubdomains": False,
            }
        }
    },
}
with open(sys.argv[1], "wb") as stream:
    plistlib.dump(payload, stream)
PY
printf 'mock embedded profile\n' >"$app/embedded.mobileprovision"
if [[ "$mode" == "push" ]]; then
  snapshot="$(dirname "$project")"
  cp "$snapshot/RocketFlow/Resources/GoogleService-Info.plist" "$app/GoogleService-Info.plist"
fi
EOF

chmod +x "$MOCK_BIN"/*
MOCK_PATH="$MOCK_BIN:$PATH"
DEVICE_ID="00008110-0012345678901234"
export MOCK_XCODEBUILD_ARGS MOCK_RSYNC_ARGS MOCK_XCRUN_ARGS MOCK_CODESIGN_ARGS MOCK_SECURITY_ARGS

LAST_OUTPUT="$CANONICAL_TEMP_PARENT/internal $TEMP_ROOT $DEVICE_ID A1B2C3D4E5 com.acme.personal.rocketflow $SECRET_MARKER"
sanitized_probe="$(sanitize_last_output)"
for forbidden in \
  "$CANONICAL_TEMP_PARENT" "$TEMP_ROOT" "$DEVICE_ID" "A1B2C3D4E5" \
  "com.acme.personal.rocketflow" "$SECRET_MARKER"; do
  [[ "$sanitized_probe" != *"$forbidden"* ]] || fail "failure diagnostic sanitizer leaked protected data"
done
LAST_OUTPUT=""
pass "failure diagnostics redact temp, device, signing, bundle, and secret markers"

expect_success "preflight validates Xcode and iphoneos SDK" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_ARGS="$MOCK_XCODEBUILD_ARGS" \
    MOCK_RSYNC_ARGS="$MOCK_RSYNC_ARGS" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    bash "$SCRIPTS/mac-preflight.sh" --config "$valid_config"
expect_failure_matching "preflight rejects iphoneos SDK below 16" "SDK version 16 or newer" \
  env PATH="$MOCK_PATH" MOCK_SDK_VERSION=15.4 MOCK_XCODEBUILD_ARGS="$MOCK_XCODEBUILD_ARGS" \
    MOCK_RSYNC_ARGS="$MOCK_RSYNC_ARGS" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    bash "$SCRIPTS/mac-preflight.sh" --config "$valid_config"

: >"$MOCK_XCRUN_ARGS"
expect_success "preflight validates exact requested device" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_ARGS="$MOCK_XCODEBUILD_ARGS" \
    MOCK_RSYNC_ARGS="$MOCK_RSYNC_ARGS" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    bash "$SCRIPTS/mac-preflight.sh" --config "$valid_config" --device "$DEVICE_ID"
assert_exact_call "preflight devicectl info uses exact device" "$MOCK_XCRUN_ARGS" \
  devicectl device info details --device "$DEVICE_ID"

: >"$MOCK_XCRUN_ARGS"
expect_success "device inventory output is redacted" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_ARGS="$MOCK_XCODEBUILD_ARGS" \
    MOCK_RSYNC_ARGS="$MOCK_RSYNC_ARGS" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_XCRUN_STDERR="$SECRET_MARKER" \
    bash "$SCRIPTS/mac-preflight.sh" --config "$valid_config" --list-devices
assert_output_excludes "device inventory leaked stderr" "$SECRET_MARKER"

verify_default_derived="$TEMP_ROOT/Mac Verify Default"
: >"$MOCK_XCODEBUILD_ARGS"
: >"$MOCK_RSYNC_ARGS"
: >"$MOCK_XCRUN_ARGS"
expect_success "default mac verify succeeds without package skip flag" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_APPEND=1 MOCK_RSYNC_COPY_PROJECT=1 \
    MOCK_SIMULATOR_ID="$DEVICE_ID" \
    bash "$SCRIPTS/mac-verify.sh" --derived-data "$verify_default_derived"
verify_default_project="$(argv_value_after "$MOCK_XCODEBUILD_ARGS" -project)"
verify_default_packages="$verify_default_derived/SourcePackages"
assert_exact_call "default mac verify resolves locked packages" "$MOCK_XCODEBUILD_ARGS" \
  -resolvePackageDependencies \
  -project "$verify_default_project" \
  -scheme RocketFlow-CI \
  -clonedSourcePackagesDirPath "$verify_default_packages"
assert_exact_call "default mac verify test call omits empty package argument" "$MOCK_XCODEBUILD_ARGS" \
  test \
  -project "$verify_default_project" \
  -scheme RocketFlow-CI \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$verify_default_derived" \
  -clonedSourcePackagesDirPath "$verify_default_packages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=
if grep -Fqx -- 'ARG:-disableAutomaticPackageResolution' "$MOCK_XCODEBUILD_ARGS"; then
  fail "default mac verify unexpectedly set package skip flag"
fi
pass "default mac verify has no package skip flag"
if grep -Fqx -- 'ARG:' "$MOCK_XCODEBUILD_ARGS"; then
  fail "default mac verify emitted a dummy empty argument"
fi
pass "default mac verify has no dummy empty argument"
assert_exact_call "default mac verify selects one simulator" "$MOCK_XCRUN_ARGS" \
  simctl list devices available --json

verify_skip_derived="$TEMP_ROOT/Mac Verify Skip"
: >"$MOCK_XCODEBUILD_ARGS"
: >"$MOCK_RSYNC_ARGS"
: >"$MOCK_XCRUN_ARGS"
expect_success "skip-package mac verify succeeds" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_APPEND=1 MOCK_RSYNC_COPY_PROJECT=1 \
    bash "$SCRIPTS/mac-verify.sh" --build-only --skip-package-resolution \
      --simulator "$DEVICE_ID" --derived-data "$verify_skip_derived"
verify_skip_project="$(argv_value_after "$MOCK_XCODEBUILD_ARGS" -project)"
assert_exact_call "skip-package mac verify build call keeps exact flag" "$MOCK_XCODEBUILD_ARGS" \
  build \
  -project "$verify_skip_project" \
  -scheme RocketFlow-CI \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath "$verify_skip_derived" \
  -clonedSourcePackagesDirPath "$verify_skip_derived/SourcePackages" \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=
if grep -Fqx -- 'ARG:-resolvePackageDependencies' "$MOCK_XCODEBUILD_ARGS"; then
  fail "skip-package mac verify unexpectedly resolved packages"
fi
pass "skip-package mac verify omits resolution call"

no_push_derived="$TEMP_ROOT/Device Output With Spaces"
: >"$MOCK_XCODEBUILD_ARGS"
: >"$MOCK_RSYNC_ARGS"
: >"$MOCK_XCRUN_ARGS"
: >"$MOCK_CODESIGN_ARGS"
: >"$MOCK_SECURITY_ARGS"
expect_success "mocked no-push signed build succeeds" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_ARGS="$MOCK_XCODEBUILD_ARGS" \
    MOCK_RSYNC_ARGS="$MOCK_RSYNC_ARGS" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-build-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --derived-data "$no_push_derived"
assert_output_excludes "build output leaked device identifier" "$DEVICE_ID"
assert_output_excludes "build output leaked absolute artifact path" "$no_push_derived"
assert_output_excludes "build output leaked signing certificate data" "contract-leaf-certificate"
no_push_project="$(argv_value_after "$MOCK_XCODEBUILD_ARGS" -project)"
[[ "$no_push_project" == */rocketflow-device-build.??????/ios/RocketFlow.xcodeproj ]] \
  || fail "xcodebuild project is not the private generated snapshot"
pass "xcodebuild project uses private generated snapshot"
assert_exact_argv "default no-push xcodebuild full call" "$MOCK_XCODEBUILD_ARGS" \
  build -quiet \
  -project "$no_push_project" \
  -scheme RocketFlow \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$no_push_derived" \
  -xcconfig "$valid_config" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=A1B2C3D4E5 \
  PRODUCT_BUNDLE_IDENTIFIER=com.acme.personal.rocketflow \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  ROCKETFLOW_API_BASE_URL=http://45.10.110.42/rocket-api \
  CODE_SIGN_ENTITLEMENTS= \
  EXCLUDED_SOURCE_FILE_NAMES=GoogleService-Info.plist
assert_argv_pair "xcodebuild scheme is RocketFlow" "$MOCK_XCODEBUILD_ARGS" -scheme RocketFlow
assert_argv_pair "xcodebuild configuration is Debug" "$MOCK_XCODEBUILD_ARGS" -configuration Debug
assert_argv_pair "xcodebuild destination preserves device" "$MOCK_XCODEBUILD_ARGS" -destination "platform=iOS,id=$DEVICE_ID"
assert_argv_pair "xcodebuild uses canonical xcconfig" "$MOCK_XCODEBUILD_ARGS" -xcconfig "$valid_config"
assert_argv_pair "xcodebuild uses canonical DerivedData" "$MOCK_XCODEBUILD_ARGS" -derivedDataPath "$no_push_derived"
assert_file_line "xcodebuild automatic signing" "$MOCK_XCODEBUILD_ARGS" "ARG:CODE_SIGN_STYLE=Automatic"
assert_file_line "xcodebuild signing is allowed" "$MOCK_XCODEBUILD_ARGS" "ARG:CODE_SIGNING_ALLOWED=YES"
assert_file_line "xcodebuild signing is required" "$MOCK_XCODEBUILD_ARGS" "ARG:CODE_SIGNING_REQUIRED=YES"
assert_file_line "xcodebuild exact team" "$MOCK_XCODEBUILD_ARGS" "ARG:DEVELOPMENT_TEAM=A1B2C3D4E5"
assert_file_line "xcodebuild exact bundle" "$MOCK_XCODEBUILD_ARGS" "ARG:PRODUCT_BUNDLE_IDENTIFIER=com.acme.personal.rocketflow"
assert_file_line "xcodebuild provisioning updates enabled" "$MOCK_XCODEBUILD_ARGS" "ARG:-allowProvisioningUpdates"
assert_file_line "xcodebuild exact API override" "$MOCK_XCODEBUILD_ARGS" "ARG:ROCKETFLOW_API_BASE_URL=http://45.10.110.42/rocket-api"
assert_file_line "no-push strips entitlements" "$MOCK_XCODEBUILD_ARGS" "ARG:CODE_SIGN_ENTITLEMENTS="
assert_file_line "no-push excludes Firebase resource" "$MOCK_XCODEBUILD_ARGS" "ARG:EXCLUDED_SOURCE_FILE_NAMES=GoogleService-Info.plist"
assert_argv_pair "codesign verifies deeply and strictly" "$MOCK_CODESIGN_ARGS" --verify --deep
assert_argv_pair "codesign strict follows deep" "$MOCK_CODESIGN_ARGS" --deep --strict
assert_exact_call "build devicectl info uses exact device" "$MOCK_XCRUN_ARGS" \
  devicectl device info details --device "$DEVICE_ID"
assert_exact_call "build decodes exact embedded profile" "$MOCK_SECURITY_ARGS" \
  cms -D -i "$no_push_derived/Build/Products/Debug-iphoneos/RocketFlow.app/embedded.mobileprovision"
certificate_prefix="$(argv_value_after "$MOCK_CODESIGN_ARGS" --extract-certificates)"
[[ "$certificate_prefix" == */rocketflow-device-build.??????/signing-certificate- ]] \
  || fail "signing certificate extraction is not private"
pass "signing certificate extraction uses private prefix"
[[ "$certificate_prefix" == "$CANONICAL_TEMP_PARENT"/rocketflow-device-build.??????/signing-certificate- ]] \
  || fail "signing certificate extraction escaped the canonical private root"
pass "self-generated signing certificate path stays under canonical private root"
assert_exact_call "codesign extracts the app certificate chain" "$MOCK_CODESIGN_ARGS" \
  -d --extract-certificates "$certificate_prefix" \
  "$no_push_derived/Build/Products/Debug-iphoneos/RocketFlow.app"
for excluded in \
  /DerivedData/ /build/ /.handoff/ \
  /Config/Local.xcconfig /Config/Device.xcconfig \
  /RocketFlow/Resources/GoogleService-Info.plist /GoogleService-Info.plist \
  /Signing/ /export/ \
  '*.mobileprovision' '*.provisionprofile' '*.p8' '*.key' '*.keychain-db' \
  '*.cer' '*.p12' '*.ipa' '*.xcarchive' '*.app' xcuserdata/; do
  assert_argv_pair "snapshot excludes $excluded" "$MOCK_RSYNC_ARGS" --exclude "$excluded"
done

push_derived="$TEMP_ROOT/Push Device Output"
: >"$MOCK_XCODEBUILD_ARGS"
: >"$MOCK_RSYNC_ARGS"
: >"$MOCK_XCRUN_ARGS"
: >"$MOCK_CODESIGN_ARGS"
: >"$MOCK_SECURITY_ARGS"
expect_success "mocked push signed build succeeds" \
  env PATH="$MOCK_PATH" MOCK_XCODEBUILD_ARGS="$MOCK_XCODEBUILD_ARGS" \
    MOCK_RSYNC_ARGS="$MOCK_RSYNC_ARGS" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=push \
    bash "$SCRIPTS/mac-build-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --mode push --firebase-plist "$matching_plist" --derived-data "$push_derived"
push_project="$(argv_value_after "$MOCK_XCODEBUILD_ARGS" -project)"
assert_exact_argv "push xcodebuild full call" "$MOCK_XCODEBUILD_ARGS" \
  build -quiet \
  -project "$push_project" \
  -scheme RocketFlow \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$push_derived" \
  -xcconfig "$valid_config" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=A1B2C3D4E5 \
  PRODUCT_BUNDLE_IDENTIFIER=com.acme.personal.rocketflow \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  ROCKETFLOW_API_BASE_URL=http://45.10.110.42/rocket-api \
  CODE_SIGN_ENTITLEMENTS=RocketFlow/RocketFlow.entitlements
assert_file_line "push uses APNs entitlements" "$MOCK_XCODEBUILD_ARGS" \
  "ARG:CODE_SIGN_ENTITLEMENTS=RocketFlow/RocketFlow.entitlements"
assert_output_excludes "push build leaked Firebase credential" "contract-test-api-key"

registration_derived="$TEMP_ROOT/Registration Opt In Output"
: >"$MOCK_XCODEBUILD_ARGS"
: >"$MOCK_RSYNC_ARGS"
: >"$MOCK_XCRUN_ARGS"
: >"$MOCK_CODESIGN_ARGS"
: >"$MOCK_SECURITY_ARGS"
expect_success "mocked opt-in device registration build succeeds" \
  env PATH="$MOCK_PATH" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-build-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --derived-data "$registration_derived" --allow-device-registration
registration_project="$(argv_value_after "$MOCK_XCODEBUILD_ARGS" -project)"
assert_exact_argv "opt-in registration xcodebuild full call" "$MOCK_XCODEBUILD_ARGS" \
  build -quiet \
  -project "$registration_project" \
  -scheme RocketFlow \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$registration_derived" \
  -xcconfig "$valid_config" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=A1B2C3D4E5 \
  PRODUCT_BUNDLE_IDENTIFIER=com.acme.personal.rocketflow \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  ROCKETFLOW_API_BASE_URL=http://45.10.110.42/rocket-api \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_ENTITLEMENTS= \
  EXCLUDED_SOURCE_FILE_NAMES=GoogleService-Info.plist

no_push_app="$no_push_derived/Build/Products/Debug-iphoneos/RocketFlow.app"
push_app="$push_derived/Build/Products/Debug-iphoneos/RocketFlow.app"
: >"$MOCK_XCRUN_ARGS"
: >"$MOCK_CODESIGN_ARGS"
expect_success "installer verifies, installs, and launches no-push app" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --app "$no_push_app" --launch
assert_file_line "devicectl receives install verb" "$MOCK_XCRUN_ARGS" "ARG:install"
assert_file_line "devicectl receives exact app argument" "$MOCK_XCRUN_ARGS" "ARG:$no_push_app"
assert_file_line "devicectl receives launch verb" "$MOCK_XCRUN_ARGS" "ARG:launch"
assert_file_line "devicectl receives exact bundle for launch" "$MOCK_XCRUN_ARGS" "ARG:com.acme.personal.rocketflow"
assert_exact_call "installer info uses exact device" "$MOCK_XCRUN_ARGS" \
  devicectl device info details --device "$DEVICE_ID"
assert_exact_call "installer install uses exact device and app" "$MOCK_XCRUN_ARGS" \
  devicectl device install app --device "$DEVICE_ID" "$no_push_app"
assert_exact_call "installer launch uses exact device and bundle" "$MOCK_XCRUN_ARGS" \
  devicectl device process launch --device "$DEVICE_ID" com.acme.personal.rocketflow
assert_output_excludes "installer output leaked app path" "$no_push_app"
assert_output_excludes "installer output leaked device identifier" "$DEVICE_ID"

: >"$MOCK_XCRUN_ARGS"
expect_success "installer verifies push entitlements and embedded Firebase bundle" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=push \
    MOCK_SECURITY_STDERR="$SECRET_MARKER" \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --mode push --app "$push_app"
assert_output_excludes "security cms stderr secret leaked" "$SECRET_MARKER"

unsigned_app="$TEMP_ROOT/Unsigned/RocketFlow.app"
create_app "$unsigned_app" com.acme.personal.rocketflow
: >"$MOCK_XCRUN_ARGS"
expect_failure_matching "unsigned app rejected before devicectl" "signature verification failed" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_CODESIGN_VERIFY_FAIL=1 \
    MOCK_SECRET_MARKER="$SECRET_MARKER" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$unsigned_app"
assert_output_excludes "codesign failure leaked stderr" "$SECRET_MARKER"
[[ ! -s "$MOCK_XCRUN_ARGS" ]] || fail "unsigned app reached devicectl"
pass "unsigned app cannot reach devicectl"

wrong_bundle_app="$TEMP_ROOT/Wrong Bundle/RocketFlow.app"
create_app "$wrong_bundle_app" com.acme.wrong.bundle
: >"$MOCK_XCRUN_ARGS"
expect_failure_matching "wrong-bundle app rejected" "bundle identifier does not match" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$wrong_bundle_app"
[[ ! -s "$MOCK_XCRUN_ARGS" ]] || fail "wrong-bundle app reached devicectl"
pass "wrong-bundle app cannot reach devicectl"

wrong_api_app="$TEMP_ROOT/Wrong API/RocketFlow.app"
create_app "$wrong_api_app" com.acme.personal.rocketflow https://override.invalid/rocket-api
expect_failure_matching "wrong API app rejected" "API endpoint does not match" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$wrong_api_app"

wrong_ats_app="$TEMP_ROOT/Wrong ATS/RocketFlow.app"
create_app "$wrong_ats_app" com.acme.personal.rocketflow http://45.10.110.42/rocket-api false false
expect_failure_matching "wrong ATS app rejected" "only the documented host-scoped" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$wrong_ats_app"

for ats_variant in broad broad-variants extra-domain extra-key; do
  built_ats_app="$TEMP_ROOT/Built ATS $ats_variant/RocketFlow.app"
  create_app "$built_ats_app" com.acme.personal.rocketflow \
    http://45.10.110.42/rocket-api true false "" "$ats_variant"
  expect_failure_matching "built ATS rejects $ats_variant" "only the documented host-scoped" \
    env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
      MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
      bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$built_ats_app"
done

simulator_app="$TEMP_ROOT/Simulator Product/RocketFlow.app"
create_app "$simulator_app" com.acme.personal.rocketflow \
  http://45.10.110.42/rocket-api true false "" simulator
expect_failure_matching "simulator product rejected" "not an iPhoneOS device product" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$simulator_app"

missing_info_app="$TEMP_ROOT/Missing Info/RocketFlow.app"
mkdir -p "$missing_info_app"
expect_failure_matching "missing Info.plist rejected" "Info.plist must be a readable regular file" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$missing_info_app"

expect_failure_matching "no-push rejects APNs entitlement" "unexpectedly contains an APNs entitlement" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
expect_failure_matching "push rejects missing APNs entitlement" "APNs entitlement could not be inspected" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --mode push --app "$push_app"

expect_failure_matching "foreign signed TeamIdentifier rejected" "TeamIdentifier does not match" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    MOCK_SIGNED_TEAM=Z9Y8X7W6V5 \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
expect_failure_matching "wrong signed application identifier rejected" "application-identifier does not match" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    MOCK_SIGNED_BUNDLE=com.acme.wrong.bundle \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"

missing_profile_app="$TEMP_ROOT/Missing Profile/RocketFlow.app"
create_app "$missing_profile_app" com.acme.personal.rocketflow
rm -f -- "$missing_profile_app/embedded.mobileprovision"
expect_failure_matching "missing embedded profile rejected" "Embedded provisioning profile must be a readable regular file" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$missing_profile_app"

expect_failure_matching "ad-hoc embedded profile rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push MOCK_PROFILE_KIND=adhoc \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
expect_failure_matching "foreign embedded profile rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push MOCK_PROFILE_TEAM=Z9Y8X7W6V5 \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
assert_output_excludes "foreign profile output leaked team" "Z9Y8X7W6V5"
expect_failure_matching "wrong embedded profile app identifier rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push MOCK_PROFILE_BUNDLE=com.acme.wrong.bundle \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
expect_failure_matching "expired embedded profile rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push MOCK_PROFILE_KIND=expired \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"

expect_failure_matching "other-device profile rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    MOCK_PROFILE_DEVICE=00008110-0099999999999999 \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
assert_output_excludes "other-device profile leaked device identifier" "00008110-0099999999999999"
expect_failure_matching "distribution profile with get-task-allow false rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push MOCK_PROFILE_KIND=distribution \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
expect_failure_matching "enterprise all-devices profile rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push MOCK_PROFILE_KIND=enterprise \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
expect_failure_matching "profile certificate mismatch rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    MOCK_PROFILE_CERTIFICATE=foreign-leaf-certificate \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
assert_output_excludes "certificate mismatch leaked certificate data" "foreign-leaf-certificate"
expect_failure_matching "push profile environment mismatch rejected" "does not authorize this development device" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=push \
    MOCK_SIGNED_APS=development MOCK_PROFILE_APS=production \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --mode push --app "$push_app"

wrong_firebase_app="$TEMP_ROOT/Wrong Firebase/RocketFlow.app"
create_app "$wrong_firebase_app" com.acme.personal.rocketflow \
  http://45.10.110.42/rocket-api true false com.acme.other.bundle
expect_failure_matching "push rejects embedded Firebase mismatch" "bundle identifier does not match" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" \
      --mode push --app "$wrong_firebase_app"

app_symlink="$TEMP_ROOT/RocketFlow-Symlink.app"
if ln -s "$no_push_app" "$app_symlink" 2>/dev/null && [[ -L "$app_symlink" ]]; then
  if LAST_OUTPUT="$(env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" \
      --config "$valid_config" --app "$app_symlink" 2>&1)"; then
    fail "installer rejects symlink app (unexpected success)"
  fi
  case "$LAST_OUTPUT" in
    *"symlink or reparse"*|*"Built app must be a regular directory."*)
      pass "installer rejects symlink app"
      ;;
    *)
      fail "installer rejects symlink app (unexpected error contract)"
      ;;
  esac
else
  skip "installer rejects symlink app" "filesystem does not expose symlinks"
fi

: >"$MOCK_XCRUN_ARGS"
expect_failure_matching "devicectl failure is categorized" "Device installation failed (exit 42)" \
  env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
    MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
    MOCK_XCRUN_FAIL_MATCH=install MOCK_XCRUN_EXIT=42 MOCK_SECRET_MARKER="$SECRET_MARKER" \
    bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$no_push_app"
assert_output_excludes "devicectl stderr secret leaked" "$SECRET_MARKER"
assert_output_excludes "devicectl failure leaked UDID" "$DEVICE_ID"
assert_output_excludes "devicectl failure leaked app path" "$no_push_app"
[[ "$LAST_OUTPUT" == *"Window > Devices and Simulators"* ]] \
  || fail "safe same-artifact fallback is missing"
[[ "$LAST_OUTPUT" != *"Xcode Run"* ]] || fail "unsafe Xcode Run fallback remains"
pass "devicectl fallback preserves the signed artifact contract"

mock_version_bin="$TEMP_ROOT/version-bin"
mkdir -p "$mock_version_bin"
cat >"$mock_version_bin/xcodegen" <<'EOF'
#!/usr/bin/env bash
printf 'Version: 2x46y0\n'
EOF
chmod +x "$mock_version_bin/xcodegen"
expect_failure_matching "XcodeGen lookalike version rejected" "XcodeGen 2.46.0 is required" \
  env PATH="$mock_version_bin:$PATH" bash -c \
    'source "$1"; verify_xcodegen_version' _ "$SCRIPTS/mac-handoff-common.sh"

printf '1..%d\n' "$passed"
printf '# total=%d passed=%d skipped=%d\n' "$passed" "$((passed - skipped))" "$skipped"
