#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
SCRIPTS="$REPO_ROOT/ios/scripts"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rocketflow-handoff-tests.XXXXXX")"
mkdir -p "$REPO_ROOT/ios/.handoff"
REPO_TEMP="$(mktemp -d "$REPO_ROOT/ios/.handoff/contract.XXXXXX")"
UNIGNORED_CONFIG="$(mktemp "$REPO_ROOT/ios/Config/mac-handoff-config.XXXXXX")"
UNIGNORED_PLIST="$(mktemp "$REPO_ROOT/ios/Config/mac-handoff-plist.XXXXXX")"

cleanup() {
  rm -rf -- "$TEMP_ROOT" "$REPO_TEMP"
  rm -f -- "$UNIGNORED_CONFIG" "$UNIGNORED_PLIST"
}
trap cleanup EXIT

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

pass() {
  passed=$((passed + 1))
  printf 'ok %d - %s\n' "$passed" "$1"
}

skip() {
  passed=$((passed + 1))
  skipped=$((skipped + 1))
  printf 'ok %d - %s # SKIP %s\n' "$passed" "$1" "$2"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
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

placeholder_config="$TEMP_ROOT/placeholder.xcconfig"
write_config "$placeholder_config" YOUR_TEAM_ID com.acme.personal.rocketflow
expect_failure_matching "placeholder team rejected" "DEVELOPMENT_TEAM must be" \
  bash "$SCRIPTS/mac-preflight.sh" --dry-run --config "$placeholder_config"

valid_config="$TEMP_ROOT/Config With Spaces/Device Config.xcconfig"
mkdir -p "$(dirname "$valid_config")"
write_config "$valid_config" A1B2C3D4E5 com.acme.personal.rocketflow

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

symlink_real="$TEMP_ROOT/symlink-real"
symlink_path="$TEMP_ROOT/symlink-output"
mkdir -p "$symlink_real"
if ln -s "$symlink_real" "$symlink_path" 2>/dev/null && [[ -L "$symlink_path" ]]; then
  expect_failure_matching "DerivedData symlink rejected" "symlink or reparse" \
    bash "$SCRIPTS/mac-verify.sh" --dry-run --derived-data "$symlink_path/child"
else
  skip "DerivedData symlink rejected" "filesystem does not expose symlinks"
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
destination=""
for argument in "$@"; do
  printf 'ARG:%s\n' "$argument" >>"$MOCK_RSYNC_ARGS"
  destination="$argument"
done
mkdir -p "${destination%/}"
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
: >"$MOCK_XCODEBUILD_ARGS"
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
esac

derived=""
project=""
bundle=""
api=""
mode="no-push"
previous=""
for argument in "$@"; do
  if [[ "$previous" == "-derivedDataPath" ]]; then derived="$argument"; fi
  if [[ "$previous" == "-project" ]]; then project="$argument"; fi
  case "$argument" in
    PRODUCT_BUNDLE_IDENTIFIER=*) bundle="${argument#PRODUCT_BUNDLE_IDENTIFIER=}" ;;
    ROCKETFLOW_API_BASE_URL=*) api="${argument#ROCKETFLOW_API_BASE_URL=}" ;;
    CODE_SIGN_ENTITLEMENTS=RocketFlow/RocketFlow.entitlements) mode="push" ;;
  esac
  previous="$argument"
done
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
SECRET_MARKER="SECRET-MARKER-DO-NOT-PRINT"
export MOCK_XCODEBUILD_ARGS MOCK_RSYNC_ARGS MOCK_XCRUN_ARGS MOCK_CODESIGN_ARGS MOCK_SECURITY_ARGS

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
expect_failure_matching "push rejects missing APNs entitlement" "lacks an APNs entitlement" \
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
  expect_failure_matching "installer rejects symlink app" "symlink or reparse" \
    env PATH="$MOCK_PATH" MOCK_XCRUN_ARGS="$MOCK_XCRUN_ARGS" \
      MOCK_CODESIGN_ARGS="$MOCK_CODESIGN_ARGS" MOCK_SIGNED_MODE=no-push \
      bash "$SCRIPTS/mac-install-device.sh" --device "$DEVICE_ID" --config "$valid_config" --app "$app_symlink"
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
