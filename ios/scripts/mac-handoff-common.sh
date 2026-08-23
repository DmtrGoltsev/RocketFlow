#!/usr/bin/env bash

set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
case "$SCRIPT_SOURCE" in
  */*) SCRIPT_PARENT="${SCRIPT_SOURCE%/*}" ;;
  *) SCRIPT_PARENT="." ;;
esac
SCRIPT_DIR="$(cd "$SCRIPT_PARENT" && pwd -P)" \
  || { printf 'error: Script directory could not be physically canonicalized.\n' >&2; exit 1; }
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)" \
  || { printf 'error: Repository root could not be physically canonicalized.\n' >&2; exit 1; }
unset SCRIPT_SOURCE SCRIPT_PARENT
IOS_ROOT="$REPO_ROOT/ios"
EXPECTED_XCODEGEN_VERSION="2.46.0"
MINIMUM_IPHONEOS_SDK_MAJOR=16
PRODUCTION_API_BASE_URL="http://45.10.110.42/rocket-api"
PRODUCTION_API_HOST="45.10.110.42"
DEFAULT_DEVICE_CONFIG="$IOS_ROOT/Config/Device.xcconfig"
GOOGLE_SERVICE_INFO="$IOS_ROOT/RocketFlow/Resources/GoogleService-Info.plist"
APP_ENTITLEMENTS="$IOS_ROOT/RocketFlow/RocketFlow.entitlements"

handoff_die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

handoff_error() {
  printf 'error: %s\n' "$1" >&2
}

handoff_note() {
  printf '%s\n' "$1"
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || handoff_die "$option requires a value."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || handoff_die "Required command is unavailable: $1"
}

require_macos() {
  local system_name
  system_name="$(uname -s)" || handoff_die "Operating-system inspection failed."
  [[ "$system_name" == "Darwin" ]] || handoff_die "This operation requires macOS. Use --dry-run for contract validation."
}

validate_mode() {
  case "$1" in
    no-push|push) ;;
    *) handoff_die "Mode must be no-push or push." ;;
  esac
}

validate_configuration() {
  case "$1" in
    Debug|Release) ;;
    *) handoff_die "Configuration must be Debug or Release." ;;
  esac
}

validate_device_identifier() {
  [[ "$1" =~ ^[A-Za-z0-9-]{8,64}$ ]] || handoff_die "Device identifier format is invalid."
}

lexical_absolute_path() {
  local path="$1"
  local raw body component result index stack_count=0
  local -a stack
  stack=()
  case "$path" in
    /*) raw="$path" ;;
    *) raw="$PWD/$path" ;;
  esac
  body="${raw#/}"
  while [[ -n "$body" ]]; do
    if [[ "$body" == */* ]]; then
      component="${body%%/*}"
      body="${body#*/}"
    else
      component="$body"
      body=""
    fi
    case "$component" in
      ''|.) continue ;;
      ..)
        if ((stack_count > 0)); then
          stack_count=$((stack_count - 1))
          unset 'stack[stack_count]'
        fi
        ;;
      *)
        stack[stack_count]="$component"
        stack_count=$((stack_count + 1))
        ;;
    esac
  done
  if ((stack_count == 0)); then
    printf '/\n'
    return
  fi
  result="${stack[0]}"
  for ((index = 1; index < stack_count; index++)); do
    result="$result/${stack[index]}"
  done
  printf '/%s\n' "$result"
}

canonical_existing_file() {
  local input="$1"
  local label="$2"
  local absolute parent_input parent base canonical
  absolute="$(lexical_absolute_path "$input")" || return $?
  [[ -f "$absolute" && ! -L "$absolute" && -r "$absolute" ]] \
    || handoff_die "$label must be a readable regular file."
  parent_input="${absolute%/*}"
  [[ -n "$parent_input" ]] || parent_input="/"
  base="${absolute##*/}"
  parent="$(cd "$parent_input" && pwd -P)" \
    || handoff_die "$label parent could not be physically canonicalized."
  if [[ "$parent" == "/" ]]; then
    canonical="/$base"
  else
    canonical="$parent/$base"
  fi
  [[ -f "$canonical" && ! -L "$canonical" && -r "$canonical" ]] \
    || handoff_die "$label must be a readable regular file."
  printf '%s\n' "$canonical"
}

canonical_existing_directory() {
  local input="$1"
  local label="$2"
  local absolute parent_input parent base canonical resolved
  absolute="$(lexical_absolute_path "$input")" || return $?
  [[ -d "$absolute" && ! -L "$absolute" ]] || handoff_die "$label must be a regular directory."
  parent_input="${absolute%/*}"
  [[ -n "$parent_input" ]] || parent_input="/"
  base="${absolute##*/}"
  parent="$(cd "$parent_input" && pwd -P)" \
    || handoff_die "$label parent could not be physically canonicalized."
  if [[ "$parent" == "/" ]]; then
    canonical="/$base"
  else
    canonical="$parent/$base"
  fi
  [[ -d "$canonical" && ! -L "$canonical" ]] || handoff_die "$label must be a regular directory."
  resolved="$(cd "$canonical" && pwd -P)" \
    || handoff_die "$label could not be physically canonicalized."
  printf '%s\n' "$resolved"
}

canonical_output_directory() {
  local input="$1"
  local absolute cursor suffix="" parent base canonical
  [[ -n "$input" ]] || handoff_die "Output path is empty."
  absolute="$(lexical_absolute_path "$input")" || return $?
  [[ ! -L "$absolute" ]] || handoff_die "Output path must not be a symlink or reparse point."
  cursor="$absolute"
  while [[ ! -e "$cursor" ]]; do
    base="${cursor##*/}"
    suffix="/$base$suffix"
    parent="${cursor%/*}"
    [[ -n "$parent" ]] || parent="/"
    [[ "$parent" != "$cursor" ]] || handoff_die "Output path cannot be canonicalized."
    cursor="$parent"
  done
  [[ -d "$cursor" ]] || handoff_die "Output path must resolve through directories only."
  parent="$(cd "$cursor" && pwd -P)" \
    || handoff_die "Output path could not be physically canonicalized."
  if [[ "$parent" == "/" ]]; then
    canonical="${suffix:-/}"
  else
    canonical="$parent$suffix"
  fi
  if [[ -e "$canonical" ]]; then
    [[ -d "$canonical" && ! -L "$canonical" ]] \
      || handoff_die "Output path must be a regular directory."
  fi
  printf '%s\n' "$canonical"
}

path_is_within() {
  local child="$1"
  local parent="$2"
  [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

verify_git_repository_root() {
  local reported_root canonical_root
  if ! reported_root="$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)"; then
    handoff_die "Git repository-root inspection failed."
  fi
  canonical_root="$(cd "$reported_root" && pwd -P)" \
    || handoff_die "Git repository root could not be physically canonicalized."
  [[ "$canonical_root" == "$REPO_ROOT" ]] || handoff_die "Git repository root does not match the handoff workspace."
}

require_git_ignored_path() {
  local relative="$1"
  local label="$2"
  local status=0
  git -C "$REPO_ROOT" check-ignore -q -- "$relative" 2>/dev/null || status=$?
  case "$status" in
    0) ;;
    1) handoff_die "$label must be ignored." ;;
    *) handoff_die "Git ignore inspection failed." ;;
  esac
}

require_git_untracked_path() {
  local relative="$1"
  local label="$2"
  local tracked
  if ! tracked="$(git -C "$REPO_ROOT" ls-files -- "$relative" "$relative/**" 2>/dev/null)"; then
    handoff_die "Git tracked-file inspection failed."
  fi
  [[ -z "$tracked" ]] || handoff_die "$label must not be tracked."
}

require_git_clean_status_path() {
  local relative="$1"
  local label="$2"
  local status_output
  if ! status_output="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- "$relative" 2>/dev/null)"; then
    handoff_die "Git status inspection failed."
  fi
  [[ -z "$status_output" ]] || handoff_die "$label has visible repository state."
}

validate_derived_data_path() {
  local input="$1"
  local lexical canonical relative
  lexical="$(lexical_absolute_path "$input")" || return $?
  canonical="$(canonical_output_directory "$lexical")" || return $?
  [[ "$lexical" != "/" && "$lexical" != "$REPO_ROOT" && "$lexical" != "$IOS_ROOT" \
    && "$canonical" != "/" && "$canonical" != "$REPO_ROOT" && "$canonical" != "$IOS_ROOT" ]] \
    || handoff_die "DerivedData path targets a protected repository directory."

  if path_is_within "$lexical" "$REPO_ROOT"; then
    [[ "$lexical" == "$IOS_ROOT/DerivedData/"* \
      && "$canonical" == "$IOS_ROOT/DerivedData/"* ]] \
      || handoff_die "DerivedData inside the repository is allowed only below ios/DerivedData."
  fi
  if path_is_within "$canonical" "$REPO_ROOT"; then
    [[ "$canonical" == "$IOS_ROOT/DerivedData/"* ]] \
      || handoff_die "DerivedData inside the repository is allowed only below ios/DerivedData."
    relative="${canonical#"$REPO_ROOT/"}"
    verify_git_repository_root || return $?
    require_git_untracked_path "$relative" "DerivedData path" || return $?
    require_git_ignored_path "$relative" "In-repository DerivedData" || return $?
    require_git_clean_status_path "$relative" "DerivedData path" || return $?
  fi
  printf '%s\n' "$canonical"
}

file_mode() {
  local mode
  if mode="$(stat -f '%Lp' "$1" 2>/dev/null)" && [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "$mode"
    return
  fi
  mode="$(stat -c '%a' "$1" 2>/dev/null)" || return $?
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  printf '%s\n' "$mode"
}

validate_private_input_permissions() {
  local file="$1"
  local label="$2"
  local mode
  mode="$(file_mode "$file")" || handoff_die "$label permissions could not be validated."
  mode="${mode: -3}"
  (( (8#$mode & 022) == 0 )) || handoff_die "$label must not be group- or world-writable."
}

canonical_sensitive_input() {
  local input="$1"
  local label="$2"
  local lexical canonical relative
  lexical="$(lexical_absolute_path "$input")" || return $?
  canonical="$(canonical_existing_file "$input" "$label")" || return $?
  validate_private_input_permissions "$canonical" "$label"
  if path_is_within "$lexical" "$REPO_ROOT" && ! path_is_within "$canonical" "$REPO_ROOT"; then
    handoff_die "$label must not escape the repository through a symlink or reparse parent."
  fi
  if path_is_within "$canonical" "$REPO_ROOT"; then
    relative="${canonical#"$REPO_ROOT/"}"
    verify_git_repository_root || return $?
    require_git_untracked_path "$relative" "$label" || return $?
    require_git_ignored_path "$relative" "$label inside the repository" || return $?
    require_git_clean_status_path "$relative" "$label" || return $?
  fi
  printf '%s\n' "$canonical"
}

xcconfig_value() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      line = $0
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
      sub("[[:space:]]*//.*$", "", line)
      sub("^[[:space:]]+", "", line)
      sub("[[:space:]]+$", "", line)
      value = line
    }
    END { if (value != "") print value }
  ' "$file"
}

contains_placeholder() {
  local value="$1"
  [[ "$value" =~ YOUR_|yourname|YOURNAME|CHANGE_ME|PLACEHOLDER|EXAMPLE|example|TEAM_ID|\$\( ]]
}

validate_device_config() {
  local file="$1"
  local team bundle style allowed required
  awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*(DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_STYLE|CODE_SIGNING_ALLOWED|CODE_SIGNING_REQUIRED)[[:space:]]*=/ { next }
    { invalid = 1 }
    END { exit invalid }
  ' "$file" || handoff_die "Device xcconfig contains an unsupported setting or directive."
  team="$(xcconfig_value "$file" DEVELOPMENT_TEAM)" || handoff_die "Device xcconfig Team ID could not be read."
  bundle="$(xcconfig_value "$file" PRODUCT_BUNDLE_IDENTIFIER)" || handoff_die "Device xcconfig bundle identifier could not be read."
  style="$(xcconfig_value "$file" CODE_SIGN_STYLE)" || handoff_die "Device xcconfig signing style could not be read."
  allowed="$(xcconfig_value "$file" CODE_SIGNING_ALLOWED)" || handoff_die "Device xcconfig signing allowance could not be read."
  required="$(xcconfig_value "$file" CODE_SIGNING_REQUIRED)" || handoff_die "Device xcconfig signing requirement could not be read."
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || handoff_die "DEVELOPMENT_TEAM must be a non-placeholder 10-character Team ID."
  contains_placeholder "$team" && handoff_die "DEVELOPMENT_TEAM still contains a placeholder."
  [[ "$bundle" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$ ]] \
    || handoff_die "PRODUCT_BUNDLE_IDENTIFIER must be a unique reverse-DNS identifier."
  contains_placeholder "$bundle" && handoff_die "PRODUCT_BUNDLE_IDENTIFIER still contains a placeholder."
  [[ "$bundle" != *'*'* ]] || handoff_die "Wildcard bundle identifiers are not accepted."
  [[ "$style" == "Automatic" ]] || handoff_die "CODE_SIGN_STYLE must be Automatic."
  [[ "$allowed" == "YES" && "$required" == "YES" ]] \
    || handoff_die "Device signing must keep CODE_SIGNING_ALLOWED and CODE_SIGNING_REQUIRED enabled."
}

plist_value_silent() {
  local file="$1"
  local key_path="$2"
  require_command python3
  python3 - "$file" "$key_path" <<'PY'
import plistlib
import sys

try:
    with open(sys.argv[1], "rb") as stream:
        value = plistlib.load(stream)
except Exception:
    raise SystemExit(2)
for component in sys.argv[2].split(":"):
    if not isinstance(value, dict) or component not in value:
        raise SystemExit(3)
    value = value[component]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None or isinstance(value, (dict, list, bytes)):
    raise SystemExit(4)
else:
    print(value)
PY
}

validate_firebase_plist() {
  local plist="$1"
  local bundle="$2"
  local key value
  for key in BUNDLE_ID GOOGLE_APP_ID GCM_SENDER_ID PROJECT_ID API_KEY; do
    if ! value="$(plist_value_silent "$plist" "$key" 2>/dev/null)"; then
      handoff_die "GoogleService-Info.plist is missing or has an unreadable required key $key."
    fi
    [[ -n "$value" ]] || handoff_die "GoogleService-Info.plist has an empty required key $key."
  done
  value="$(plist_value_silent "$plist" BUNDLE_ID 2>/dev/null)" \
    || handoff_die "GoogleService-Info.plist bundle identifier could not be read."
  [[ "$value" == "$bundle" ]] \
    || handoff_die "GoogleService-Info.plist bundle identifier does not match Device.xcconfig."
}

validate_push_contract() {
  local plist="$1"
  local bundle="$2"
  local value
  validate_firebase_plist "$plist" "$bundle"
  [[ -f "$APP_ENTITLEMENTS" ]] || handoff_die "Push mode requires the tracked app entitlements file."
  value="$(plist_value_silent "$APP_ENTITLEMENTS" aps-environment 2>/dev/null)" \
    || handoff_die "Push entitlement could not be read."
  [[ "$value" == "development" || "$value" == "production" ]] \
    || handoff_die "Push mode requires an aps-environment entitlement."
}

assert_ignored_path() {
  local path="$1"
  require_git_untracked_path "$path" "Security-sensitive path" || return $?
  require_git_ignored_path "$path" "Security-sensitive path" || return $?
  require_git_clean_status_path "$path" "Security-sensitive path" || return $?
}

verify_security_ignores() {
  local tracked
  verify_git_repository_root || return $?
  assert_ignored_path "ios/Config/Device.xcconfig" || return $?
  assert_ignored_path "ios/RocketFlow/Resources/GoogleService-Info.plist" || return $?
  assert_ignored_path "ios/DerivedData/handoff-probe" || return $?
  assert_ignored_path "ios/build/handoff-probe" || return $?
  assert_ignored_path "ios/handoff-probe.mobileprovision" || return $?
  assert_ignored_path "ios/handoff-probe.provisionprofile" || return $?
  assert_ignored_path "ios/handoff-probe.ipa" || return $?
  assert_ignored_path "ios/handoff-probe.xcarchive/example" || return $?
  assert_ignored_path "ios/handoff-probe.p8" || return $?
  assert_ignored_path "ios/handoff-probe.key" || return $?
  assert_ignored_path "ios/handoff-probe.keychain-db" || return $?
  assert_ignored_path "ios/handoff-probe.cer" || return $?
  if ! tracked="$(git -C "$REPO_ROOT" ls-files -- \
    'ios/Config/Device.xcconfig' \
    'ios/**/GoogleService-Info.plist' \
    '*.mobileprovision' '*.provisionprofile' '*.p8' '*.key' '*.keychain-db' \
    '*.cer' '*.p12' '*.ipa' '*.xcarchive/**' 2>/dev/null)"; then
    handoff_die "Git signing-artifact inspection failed."
  fi
  [[ -z "$tracked" ]] || handoff_die "A local signing input or output is tracked."
}

validate_source_api_contract() {
  local api_placeholder
  tr -d '\r' <"$IOS_ROOT/Config/Base.xcconfig" \
    | grep -Fqx 'ROCKETFLOW_DEFAULT_API_BASE_URL = http:/$()/45.10.110.42/rocket-api' \
    || handoff_die "The tracked production API build-setting contract changed."
  validate_exact_ats_contract "$IOS_ROOT/RocketFlow/Resources/Info.plist"
  api_placeholder="$(plist_value_silent "$IOS_ROOT/RocketFlow/Resources/Info.plist" RocketFlowAPIBaseURL 2>/dev/null)" \
    || handoff_die "Info.plist API build-setting placeholder could not be read."
  [[ "$api_placeholder" == '$(ROCKETFLOW_API_BASE_URL)' ]] \
    || handoff_die "Info.plist no longer consumes the required API build setting."
}

validate_exact_ats_contract() {
  local plist="$1"
  if ! python3 - "$plist" "$PRODUCTION_API_HOST" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    root = plistlib.load(stream)
expected = {
    "NSExceptionDomains": {
        sys.argv[2]: {
            "NSExceptionAllowsInsecureHTTPLoads": True,
            "NSIncludesSubdomains": False,
        }
    }
}
raise SystemExit(0 if root.get("NSAppTransportSecurity") == expected else 1)
PY
  then
    handoff_die "ATS policy must contain only the documented host-scoped production exception."
  fi
}

verify_xcodegen_version() {
  local output detected
  output="$(xcodegen --version 2>/dev/null)" || handoff_die "XcodeGen version inspection failed."
  detected="$(printf '%s\n' "$output" | awk '
    match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH); exit }
  ')" || handoff_die "XcodeGen version output could not be parsed."
  [[ "$detected" == "$EXPECTED_XCODEGEN_VERSION" ]] || handoff_die "XcodeGen $EXPECTED_XCODEGEN_VERSION is required."
}

canonical_temp_root() {
  canonical_existing_directory "${TMPDIR:-/tmp}" "Temporary root"
}

create_private_temp_dir_at() {
  local parent="$1"
  local prefix="$2"
  local previous_umask directory="" canonical="" operation_status=0 restore_status=0
  parent="$(canonical_existing_directory "$parent" "Temporary parent")" || return $?
  previous_umask="$(umask)" || { handoff_error "Current umask could not be read."; return 1; }
  umask 077 || operation_status=$?
  if [[ "$operation_status" -ne 0 ]]; then
    restore_status=0
    umask "$previous_umask" || restore_status=$?
    [[ "$restore_status" -eq 0 ]] || { handoff_error "Original umask could not be restored."; return "$restore_status"; }
    handoff_error "Private umask could not be applied."
    return "$operation_status"
  fi
  operation_status=0
  directory="$(mktemp -d "$parent/${prefix}.XXXXXX")" || operation_status=$?
  umask "$previous_umask" || restore_status=$?
  if [[ "$restore_status" -ne 0 ]]; then
    if [[ "$operation_status" -eq 0 && "$directory" == "$parent/$prefix."?????? \
      && -d "$directory" && ! -L "$directory" ]]; then
      rm -rf -- "$directory" || true
    fi
    handoff_error "Original umask could not be restored."
    return "$restore_status"
  fi
  if [[ "$operation_status" -ne 0 ]]; then
    directory=""
    handoff_error "Private temporary directory creation failed."
    return "$operation_status"
  fi
  if [[ "$directory" != "$parent/$prefix."?????? || ! -d "$directory" || -L "$directory" ]]; then
    handoff_error "mktemp returned an invalid private directory."
    return 1
  fi
  operation_status=0
  chmod 700 "$directory" || operation_status=$?
  if [[ "$operation_status" -ne 0 ]]; then
    rm -rf -- "$directory" || true
    handoff_error "Private temporary directory permissions could not be applied."
    return "$operation_status"
  fi
  canonical="$(canonical_existing_directory "$directory" "Private temporary directory")" || operation_status=$?
  if [[ "$operation_status" -ne 0 ]]; then
    rm -rf -- "$directory" || true
    return "$operation_status"
  fi
  printf '%s\n' "$canonical"
}

create_private_temp_dir() {
  local prefix="$1"
  local parent
  parent="$(canonical_temp_root)" || return $?
  create_private_temp_dir_at "$parent" "$prefix"
}

create_private_temp_file_at() {
  local parent="$1"
  local prefix="$2"
  local previous_umask file="" canonical="" operation_status=0 restore_status=0
  parent="$(canonical_existing_directory "$parent" "Temporary parent")" || return $?
  previous_umask="$(umask)" || { handoff_error "Current umask could not be read."; return 1; }
  umask 077 || operation_status=$?
  if [[ "$operation_status" -ne 0 ]]; then
    restore_status=0
    umask "$previous_umask" || restore_status=$?
    [[ "$restore_status" -eq 0 ]] || { handoff_error "Original umask could not be restored."; return "$restore_status"; }
    handoff_error "Private umask could not be applied."
    return "$operation_status"
  fi
  operation_status=0
  file="$(mktemp "$parent/${prefix}.XXXXXX")" || operation_status=$?
  umask "$previous_umask" || restore_status=$?
  if [[ "$restore_status" -ne 0 ]]; then
    if [[ "$operation_status" -eq 0 && "$file" == "$parent/$prefix."?????? \
      && -f "$file" && ! -L "$file" ]]; then
      rm -f -- "$file" || true
    fi
    handoff_error "Original umask could not be restored."
    return "$restore_status"
  fi
  if [[ "$operation_status" -ne 0 ]]; then
    file=""
    handoff_error "Private temporary file creation failed."
    return "$operation_status"
  fi
  if [[ "$file" != "$parent/$prefix."?????? || ! -f "$file" || -L "$file" ]]; then
    handoff_error "mktemp returned an invalid private file."
    return 1
  fi
  operation_status=0
  chmod 600 "$file" || operation_status=$?
  if [[ "$operation_status" -ne 0 ]]; then
    rm -f -- "$file" || true
    handoff_error "Private temporary file permissions could not be applied."
    return "$operation_status"
  fi
  canonical="$(canonical_existing_file "$file" "Private temporary file")" || operation_status=$?
  if [[ "$operation_status" -ne 0 ]]; then
    rm -f -- "$file" || true
    return "$operation_status"
  fi
  printf '%s\n' "$canonical"
}

cleanup_private_temp_dir() {
  local directory="${1:-}"
  [[ -n "$directory" && "$directory" != "/" && -d "$directory" ]] || return 0
  case "${directory##*/}" in
    rocketflow-*.??????) rm -rf -- "$directory" ;;
    *) return 1 ;;
  esac
}

cleanup_private_temp_file() {
  local file="${1:-}"
  [[ -n "$file" && -f "$file" && ! -L "$file" ]] || return 0
  case "${file##*/}" in
    rocketflow-*.??????) rm -f -- "$file" ;;
    *) return 1 ;;
  esac
}

capture_command() {
  local output_file="$1"
  shift
  local status=0
  : >"$output_file" || { handoff_error "Private command log could not be created."; return 1; }
  chmod 600 "$output_file" || { status=$?; rm -f -- "$output_file" || true; handoff_error "Private command log permissions could not be applied."; return "$status"; }
  "$@" >"$output_file" 2>&1 || status=$?
  return "$status"
}

prepare_ios_snapshot() {
  local destination="$1"
  local mode="$2"
  validate_mode "$mode"
  require_command rsync
  mkdir -p "$destination"
  rsync -a --delete \
    --exclude '/DerivedData/' \
    --exclude '/build/' \
    --exclude '/.handoff/' \
    --exclude '/Config/Local.xcconfig' \
    --exclude '/Config/Device.xcconfig' \
    --exclude '/RocketFlow/Resources/GoogleService-Info.plist' \
    --exclude '/GoogleService-Info.plist' \
    --exclude '/Signing/' \
    --exclude '/export/' \
    --exclude '*.mobileprovision' \
    --exclude '*.provisionprofile' \
    --exclude '*.p8' \
    --exclude '*.key' \
    --exclude '*.keychain-db' \
    --exclude '*.cer' \
    --exclude '*.p12' \
    --exclude '*.ipa' \
    --exclude '*.xcarchive' \
    --exclude '*.app' \
    --exclude 'xcuserdata/' \
    "$IOS_ROOT/" "$destination/"
}

install_push_plist_in_snapshot() {
  local source_plist="$1"
  local snapshot="$2"
  local destination="$snapshot/RocketFlow/Resources/GoogleService-Info.plist"
  mkdir -p "${destination%/*}"
  cp "$source_plist" "$destination"
}

generate_snapshot_project() {
  local snapshot="$1"
  (cd "$snapshot" && xcodegen generate --spec project.yml >/dev/null)
}

validate_xcode_version_file() {
  grep -Eq '^Xcode [0-9]+([.][0-9]+)*$' "$1" || handoff_die "xcodebuild did not report a valid Xcode version."
}

validate_iphoneos_sdk_file() {
  local file="$1"
  local major
  major="$(awk '
    match($0, /iphoneos[0-9]+([.][0-9]+)?/) {
      value = substr($0, RSTART + 8, RLENGTH - 8)
      split(value, parts, ".")
      if (parts[1] > maximum) maximum = parts[1]
    }
    END { if (maximum != "") print maximum }
  ' "$file")" || handoff_die "Installed SDK output could not be parsed."
  [[ "$major" =~ ^[0-9]+$ && "$major" -ge "$MINIMUM_IPHONEOS_SDK_MAJOR" ]] \
    || handoff_die "An iphoneos SDK version 16 or newer is required."
}

validate_built_info_contract() {
  local info_plist="$1"
  local expected_bundle="$2"
  local actual_bundle api_url
  actual_bundle="$(plist_value_silent "$info_plist" CFBundleIdentifier 2>/dev/null)" \
    || handoff_die "Built app bundle identifier could not be read."
  api_url="$(plist_value_silent "$info_plist" RocketFlowAPIBaseURL 2>/dev/null)" \
    || handoff_die "Built app API endpoint could not be read."
  [[ "$actual_bundle" == "$expected_bundle" ]] || handoff_die "Built app bundle identifier does not match Device.xcconfig."
  [[ "$api_url" == "$PRODUCTION_API_BASE_URL" ]] || handoff_die "Built app API endpoint does not match the production handoff contract."
  validate_exact_ats_contract "$info_plist"
  if ! python3 - "$info_plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    platforms = plistlib.load(stream).get("CFBundleSupportedPlatforms")
raise SystemExit(0 if platforms == ["iPhoneOS"] else 1)
PY
  then
    handoff_die "Built app is not an iPhoneOS device product."
  fi
}

validate_signed_identity() {
  local entitlements="$1"
  local expected_team="$2"
  local expected_bundle="$3"
  local team application_identifier
  team="$(plist_value_silent "$entitlements" com.apple.developer.team-identifier 2>/dev/null)" \
    || handoff_die "Signed app TeamIdentifier could not be read."
  application_identifier="$(plist_value_silent "$entitlements" application-identifier 2>/dev/null)" \
    || handoff_die "Signed app application-identifier could not be read."
  [[ "$team" == "$expected_team" ]] || handoff_die "Signed app TeamIdentifier does not match Device.xcconfig."
  [[ "$application_identifier" == "$expected_team.$expected_bundle" ]] \
    || handoff_die "Signed app application-identifier does not match the configured team and bundle."
}

validate_mobileprovision_contract() {
  local profile_plist="$1"
  local expected_team="$2"
  local expected_bundle="$3"
  local expected_device="$4"
  local mode="$5"
  local signed_aps="$6"
  local leaf_certificate="$7"
  if ! python3 - \
    "$profile_plist" "$expected_team" "$expected_bundle" "$expected_device" \
    "$mode" "$signed_aps" "$leaf_certificate" <<'PY'
from datetime import datetime, timezone
import hashlib
import hmac
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    profile = plistlib.load(stream)
team = sys.argv[2]
bundle = sys.argv[3]
device = sys.argv[4]
mode = sys.argv[5]
signed_aps = sys.argv[6]
with open(sys.argv[7], "rb") as stream:
    leaf_hash = hashlib.sha256(stream.read()).digest()
teams = profile.get("TeamIdentifier")
entitlements = profile.get("Entitlements")
expiration = profile.get("ExpirationDate")
devices = profile.get("ProvisionedDevices")
certificates = profile.get("DeveloperCertificates")
if teams != [team] or not isinstance(entitlements, dict):
    raise SystemExit(1)
if entitlements.get("com.apple.developer.team-identifier") != team:
    raise SystemExit(1)
if entitlements.get("application-identifier") != f"{team}.{bundle}":
    raise SystemExit(1)
if entitlements.get("get-task-allow") is not True:
    raise SystemExit(1)
if profile.get("ProvisionsAllDevices", False) is not False:
    raise SystemExit(1)
if not isinstance(devices, list) or device not in devices:
    raise SystemExit(1)
if not isinstance(certificates, list) or not certificates:
    raise SystemExit(1)
certificate_matches = any(
    isinstance(certificate, bytes)
    and hmac.compare_digest(hashlib.sha256(certificate).digest(), leaf_hash)
    for certificate in certificates
)
if not certificate_matches:
    raise SystemExit(1)
if mode == "push" and entitlements.get("aps-environment") != signed_aps:
    raise SystemExit(1)
if not isinstance(expiration, datetime):
    raise SystemExit(1)
if expiration.tzinfo is None:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
else:
    now = datetime.now(timezone.utc)
raise SystemExit(0 if expiration > now else 1)
PY
  then
    handoff_die "Embedded provisioning profile does not authorize this development device and signed identity."
  fi
}

verify_signed_app() {
  local app="$1"
  local expected_bundle="$2"
  local expected_team="$3"
  local expected_device="$4"
  local mode="$5"
  local private_dir="$6"
  local info_plist entitlements_file codesign_log aps embedded_plist embedded_profile
  local profile_plist profile_log certificate_prefix leaf_certificate previous_umask status restore_status
  validate_mode "$mode"
  private_dir="$(canonical_existing_directory "$private_dir" "Private verification directory")" || return $?
  app="$(canonical_existing_directory "$app" "Built app")" || return $?
  [[ "$app" == *.app ]] || handoff_die "Built app must be an .app directory."
  info_plist="$(canonical_existing_file "$app/Info.plist" "Built app Info.plist")" || return $?
  codesign_log="$private_dir/codesign-verify.log"
  capture_command "$codesign_log" codesign --verify --deep --strict "$app" \
    || handoff_die "Built app signature verification failed."
  entitlements_file="$private_dir/signed-entitlements.plist"
  codesign_log="$private_dir/codesign-entitlements.log"
  : >"$entitlements_file" || handoff_die "Signed-entitlements output could not be created."
  : >"$codesign_log" || handoff_die "Codesign log could not be created."
  chmod 600 "$entitlements_file" "$codesign_log" \
    || handoff_die "Signed-entitlements output permissions could not be applied."
  if ! codesign -d --entitlements :- "$app" >"$entitlements_file" 2>"$codesign_log"; then
    handoff_die "Built app signature entitlements could not be inspected."
  fi
  validate_built_info_contract "$info_plist" "$expected_bundle"
  validate_signed_identity "$entitlements_file" "$expected_team" "$expected_bundle"

  certificate_prefix="$private_dir/signing-certificate-"
  codesign_log="$private_dir/codesign-certificates.log"
  : >"$codesign_log" || handoff_die "Certificate-extraction log could not be created."
  chmod 600 "$codesign_log" || handoff_die "Certificate-extraction log permissions could not be applied."
  previous_umask="$(umask)" || handoff_die "Current umask could not be read."
  status=0
  umask 077 || status=$?
  if [[ "$status" -ne 0 ]]; then
    restore_status=0
    umask "$previous_umask" || restore_status=$?
    [[ "$restore_status" -eq 0 ]] || handoff_die "Original certificate umask could not be restored."
    handoff_die "Private certificate umask could not be applied."
  fi
  status=0
  codesign -d --extract-certificates "$certificate_prefix" "$app" >"$codesign_log" 2>&1 || status=$?
  restore_status=0
  umask "$previous_umask" || restore_status=$?
  [[ "$restore_status" -eq 0 ]] || handoff_die "Original certificate umask could not be restored."
  [[ "$status" -eq 0 ]] || handoff_die "Signing certificate extraction failed."
  leaf_certificate="${certificate_prefix}0"
  leaf_certificate="$(canonical_existing_file "$leaf_certificate" "Signing leaf certificate")" || return $?
  chmod 600 "$leaf_certificate" || handoff_die "Signing certificate permissions could not be applied."

  embedded_profile="$(canonical_existing_file "$app/embedded.mobileprovision" "Embedded provisioning profile")" || return $?
  profile_plist="$private_dir/embedded-profile.plist"
  profile_log="$private_dir/security-cms.log"
  : >"$profile_plist" || handoff_die "Decoded profile output could not be created."
  : >"$profile_log" || handoff_die "Profile-decoding log could not be created."
  chmod 600 "$profile_plist" "$profile_log" \
    || handoff_die "Profile-decoding output permissions could not be applied."
  if ! security cms -D -i "$embedded_profile" >"$profile_plist" 2>"$profile_log"; then
    handoff_die "Embedded provisioning profile could not be decoded."
  fi
  status=0
  aps="$(plist_value_silent "$entitlements_file" aps-environment 2>/dev/null)" || status=$?
  if [[ "$status" -eq 3 && "$mode" == "no-push" ]]; then
    aps=""
  elif [[ "$status" -ne 0 ]]; then
    handoff_die "Signed app APNs entitlement could not be inspected."
  fi
  if [[ "$mode" == "no-push" ]]; then
    [[ -z "$aps" ]] || handoff_die "No-push app unexpectedly contains an APNs entitlement."
  else
    [[ "$aps" == "development" || "$aps" == "production" ]] \
      || handoff_die "Push app lacks an APNs entitlement in its signed profile."
  fi
  validate_mobileprovision_contract \
    "$profile_plist" "$expected_team" "$expected_bundle" "$expected_device" \
    "$mode" "$aps" "$leaf_certificate"

  embedded_plist="$app/GoogleService-Info.plist"
  if [[ "$mode" == "no-push" ]]; then
    [[ ! -e "$embedded_plist" && ! -L "$embedded_plist" ]] \
      || handoff_die "No-push app unexpectedly contains Firebase configuration."
  else
    embedded_plist="$(canonical_existing_file "$embedded_plist" "Embedded Firebase plist")" || return $?
    validate_firebase_plist "$embedded_plist" "$expected_bundle"
  fi
}

select_simulator_identifier() {
  local json
  json="$(xcrun simctl list devices available --json)" \
    || handoff_die "Available simulator inventory could not be read."
  printf '%s' "$json" | python3 -c '
import json
import sys
devices = json.load(sys.stdin)["devices"]
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator found")
'
}

newest_device_app() {
  local derived_data="$1"
  local products="$derived_data/Build/Products"
  local listing candidate newest=""
  [[ -d "$products" ]] || { printf '\n'; return; }
  listing="$(find "$products" -type d -name 'RocketFlow.app' -path '*iphoneos*' -print 2>/dev/null)" \
    || return $?
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if [[ -z "$newest" || "$candidate" -nt "$newest" ]]; then
      newest="$candidate"
    fi
  done <<<"$listing"
  printf '%s\n' "$newest"
}
