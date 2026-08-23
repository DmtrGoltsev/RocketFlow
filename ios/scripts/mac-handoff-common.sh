#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
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
  [[ "$(uname -s)" == "Darwin" ]] || handoff_die "This operation requires macOS. Use --dry-run for contract validation."
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
  local raw component result index
  local -a parts stack
  parts=()
  stack=()
  case "$path" in
    /*) raw="$path" ;;
    *) raw="$PWD/$path" ;;
  esac
  IFS='/' read -r -a parts <<<"${raw#/}"
  for component in "${parts[@]}"; do
    case "$component" in
      ''|.) continue ;;
      ..)
        if ((${#stack[@]})); then
          index=$((${#stack[@]} - 1))
          unset 'stack[index]'
        fi
        ;;
      *) stack+=("$component") ;;
    esac
  done
  if ((${#stack[@]} == 0)); then
    printf '/\n'
    return
  fi
  result="$(IFS=/; printf '%s' "${stack[*]}")"
  printf '/%s\n' "$result"
}

canonical_existing_file() {
  local input="$1"
  local label="$2"
  local absolute parent canonical
  absolute="$(lexical_absolute_path "$input")"
  [[ -f "$absolute" && ! -L "$absolute" && -r "$absolute" ]] \
    || handoff_die "$label must be a readable regular file."
  parent="$(cd "$(dirname "$absolute")" && pwd -P)" \
    || handoff_die "$label parent could not be physically canonicalized."
  if [[ "$parent" == "/" ]]; then
    canonical="/$(basename "$absolute")"
  else
    canonical="$parent/$(basename "$absolute")"
  fi
  [[ -f "$canonical" && ! -L "$canonical" && -r "$canonical" ]] \
    || handoff_die "$label must be a readable regular file."
  printf '%s\n' "$canonical"
}

canonical_existing_directory() {
  local input="$1"
  local label="$2"
  local absolute parent canonical
  absolute="$(lexical_absolute_path "$input")"
  [[ -d "$absolute" && ! -L "$absolute" ]] || handoff_die "$label must be a regular directory."
  parent="$(cd "$(dirname "$absolute")" && pwd -P)" \
    || handoff_die "$label parent could not be physically canonicalized."
  if [[ "$parent" == "/" ]]; then
    canonical="/$(basename "$absolute")"
  else
    canonical="$parent/$(basename "$absolute")"
  fi
  [[ -d "$canonical" && ! -L "$canonical" ]] || handoff_die "$label must be a regular directory."
  (cd "$canonical" && pwd -P)
}

canonical_output_directory() {
  local input="$1"
  local absolute cursor suffix="" parent base canonical
  [[ -n "$input" ]] || handoff_die "Output path is empty."
  absolute="$(lexical_absolute_path "$input")"
  [[ ! -L "$absolute" ]] || handoff_die "Output path must not be a symlink or reparse point."
  cursor="$absolute"
  while [[ ! -e "$cursor" ]]; do
    base="$(basename "$cursor")"
    suffix="/$base$suffix"
    parent="$(dirname "$cursor")"
    [[ "$parent" != "$cursor" ]] || handoff_die "Output path cannot be canonicalized."
    cursor="$parent"
  done
  [[ -d "$cursor" ]] || handoff_die "Output path must resolve through directories only."
  parent="$(cd "$cursor" && pwd -P)"
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

validate_derived_data_path() {
  local input="$1"
  local lexical canonical relative tracked
  lexical="$(lexical_absolute_path "$input")"
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
    git -C "$REPO_ROOT" check-ignore -q -- "$relative" \
      || handoff_die "In-repository DerivedData must be ignored."
    tracked="$(git -C "$REPO_ROOT" ls-files -- "$relative" "$relative/**")"
    [[ -z "$tracked" ]] || handoff_die "DerivedData path contains tracked repository content."
  fi
  printf '%s\n' "$canonical"
}

file_mode() {
  local mode
  mode="$(stat -f '%Lp' "$1" 2>/dev/null || true)"
  if [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "$mode"
  else
    stat -c '%a' "$1" 2>/dev/null
  fi
}

validate_private_input_permissions() {
  local file="$1"
  local label="$2"
  local mode
  mode="$(file_mode "$file" || true)"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || handoff_die "$label permissions could not be validated."
  mode="${mode: -3}"
  (( (8#$mode & 022) == 0 )) || handoff_die "$label must not be group- or world-writable."
}

canonical_sensitive_input() {
  local input="$1"
  local label="$2"
  local lexical canonical relative tracked
  lexical="$(lexical_absolute_path "$input")"
  canonical="$(canonical_existing_file "$input" "$label")" || return $?
  validate_private_input_permissions "$canonical" "$label"
  if path_is_within "$lexical" "$REPO_ROOT" && ! path_is_within "$canonical" "$REPO_ROOT"; then
    handoff_die "$label must not escape the repository through a symlink or reparse parent."
  fi
  if path_is_within "$canonical" "$REPO_ROOT"; then
    relative="${canonical#"$REPO_ROOT/"}"
    tracked="$(git -C "$REPO_ROOT" ls-files -- "$relative")"
    [[ -z "$tracked" ]] || handoff_die "$label must not be tracked."
    git -C "$REPO_ROOT" check-ignore -q -- "$relative" \
      || handoff_die "$label inside the repository must be ignored."
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
  team="$(xcconfig_value "$file" DEVELOPMENT_TEAM)"
  bundle="$(xcconfig_value "$file" PRODUCT_BUNDLE_IDENTIFIER)"
  style="$(xcconfig_value "$file" CODE_SIGN_STYLE)"
  allowed="$(xcconfig_value "$file" CODE_SIGNING_ALLOWED)"
  required="$(xcconfig_value "$file" CODE_SIGNING_REQUIRED)"
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
  if [[ -x /usr/libexec/PlistBuddy ]]; then
    /usr/libexec/PlistBuddy -c "Print :$key_path" "$file" 2>/dev/null
    return
  fi
  require_command python3
  python3 - "$file" "$key_path" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    value = plistlib.load(stream)
for component in sys.argv[2].split(":"):
    if not isinstance(value, dict) or component not in value:
        raise SystemExit(1)
    value = value[component]
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None or isinstance(value, (dict, list, bytes)):
    raise SystemExit(1)
else:
    print(value)
PY
}

validate_firebase_plist() {
  local plist="$1"
  local bundle="$2"
  local key value
  for key in BUNDLE_ID GOOGLE_APP_ID GCM_SENDER_ID PROJECT_ID API_KEY; do
    value="$(plist_value_silent "$plist" "$key" 2>/dev/null || true)"
    [[ -n "$value" ]] || handoff_die "GoogleService-Info.plist is missing required key $key."
  done
  value="$(plist_value_silent "$plist" BUNDLE_ID 2>/dev/null || true)"
  [[ "$value" == "$bundle" ]] \
    || handoff_die "GoogleService-Info.plist bundle identifier does not match Device.xcconfig."
}

validate_push_contract() {
  local plist="$1"
  local bundle="$2"
  local value
  validate_firebase_plist "$plist" "$bundle"
  [[ -f "$APP_ENTITLEMENTS" ]] || handoff_die "Push mode requires the tracked app entitlements file."
  value="$(plist_value_silent "$APP_ENTITLEMENTS" aps-environment 2>/dev/null || true)"
  [[ "$value" == "development" || "$value" == "production" ]] \
    || handoff_die "Push mode requires an aps-environment entitlement."
}

assert_ignored_path() {
  local path="$1"
  git -C "$REPO_ROOT" check-ignore -q -- "$path" || handoff_die "Security-sensitive path is not ignored."
}

verify_security_ignores() {
  local tracked
  assert_ignored_path "ios/Config/Device.xcconfig"
  assert_ignored_path "ios/RocketFlow/Resources/GoogleService-Info.plist"
  assert_ignored_path "ios/DerivedData/handoff-probe"
  assert_ignored_path "ios/build/handoff-probe"
  assert_ignored_path "ios/handoff-probe.mobileprovision"
  assert_ignored_path "ios/handoff-probe.provisionprofile"
  assert_ignored_path "ios/handoff-probe.ipa"
  assert_ignored_path "ios/handoff-probe.xcarchive/example"
  assert_ignored_path "ios/handoff-probe.p8"
  assert_ignored_path "ios/handoff-probe.key"
  assert_ignored_path "ios/handoff-probe.keychain-db"
  assert_ignored_path "ios/handoff-probe.cer"
  tracked="$(git -C "$REPO_ROOT" ls-files -- \
    'ios/Config/Device.xcconfig' \
    'ios/**/GoogleService-Info.plist' \
    '*.mobileprovision' '*.provisionprofile' '*.p8' '*.key' '*.keychain-db' \
    '*.cer' '*.p12' '*.ipa' '*.xcarchive/**')"
  [[ -z "$tracked" ]] || handoff_die "A local signing input or output is tracked."
}

validate_source_api_contract() {
  local api_placeholder
  tr -d '\r' <"$IOS_ROOT/Config/Base.xcconfig" \
    | grep -Fqx 'ROCKETFLOW_DEFAULT_API_BASE_URL = http:/$()/45.10.110.42/rocket-api' \
    || handoff_die "The tracked production API build-setting contract changed."
  validate_exact_ats_contract "$IOS_ROOT/RocketFlow/Resources/Info.plist"
  api_placeholder="$(plist_value_silent "$IOS_ROOT/RocketFlow/Resources/Info.plist" RocketFlowAPIBaseURL 2>/dev/null || true)"
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
  output="$(xcodegen --version 2>/dev/null || true)"
  detected="$(printf '%s\n' "$output" | awk '
    match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH); exit }
  ')"
  [[ "$detected" == "$EXPECTED_XCODEGEN_VERSION" ]] || handoff_die "XcodeGen $EXPECTED_XCODEGEN_VERSION is required."
}

canonical_temp_root() {
  canonical_existing_directory "${TMPDIR:-/tmp}" "Temporary root"
}

create_private_temp_dir_at() {
  local parent="$1"
  local prefix="$2"
  local previous_umask directory
  parent="$(canonical_existing_directory "$parent" "Temporary parent")" || return $?
  previous_umask="$(umask)"
  umask 077
  directory="$(mktemp -d "$parent/${prefix}.XXXXXX")"
  umask "$previous_umask"
  chmod 700 "$directory"
  canonical_existing_directory "$directory" "Private temporary directory"
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
  local previous_umask file
  parent="$(canonical_existing_directory "$parent" "Temporary parent")" || return $?
  previous_umask="$(umask)"
  umask 077
  file="$(mktemp "$parent/${prefix}.XXXXXX")"
  umask "$previous_umask"
  chmod 600 "$file"
  canonical_existing_file "$file" "Private temporary file"
}

cleanup_private_temp_dir() {
  local directory="${1:-}"
  [[ -n "$directory" && "$directory" != "/" && -d "$directory" ]] || return 0
  case "$(basename "$directory")" in
    rocketflow-*.??????) rm -rf -- "$directory" ;;
    *) return 1 ;;
  esac
}

cleanup_private_temp_file() {
  local file="${1:-}"
  [[ -n "$file" && -f "$file" && ! -L "$file" ]] || return 0
  case "$(basename "$file")" in
    rocketflow-*.??????) rm -f -- "$file" ;;
    *) return 1 ;;
  esac
}

capture_command() {
  local output_file="$1"
  shift
  : >"$output_file"
  chmod 600 "$output_file"
  local status=0
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
  mkdir -p "$(dirname "$destination")"
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
  ' "$file")"
  [[ "$major" =~ ^[0-9]+$ && "$major" -ge "$MINIMUM_IPHONEOS_SDK_MAJOR" ]] \
    || handoff_die "An iphoneos SDK version 16 or newer is required."
}

validate_built_info_contract() {
  local info_plist="$1"
  local expected_bundle="$2"
  local actual_bundle api_url
  actual_bundle="$(plist_value_silent "$info_plist" CFBundleIdentifier 2>/dev/null || true)"
  api_url="$(plist_value_silent "$info_plist" RocketFlowAPIBaseURL 2>/dev/null || true)"
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
  team="$(plist_value_silent "$entitlements" com.apple.developer.team-identifier 2>/dev/null || true)"
  application_identifier="$(plist_value_silent "$entitlements" application-identifier 2>/dev/null || true)"
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
  local profile_plist profile_log certificate_prefix leaf_certificate previous_umask status
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
  : >"$entitlements_file"
  : >"$codesign_log"
  chmod 600 "$entitlements_file" "$codesign_log"
  if ! codesign -d --entitlements :- "$app" >"$entitlements_file" 2>"$codesign_log"; then
    handoff_die "Built app signature entitlements could not be inspected."
  fi
  validate_built_info_contract "$info_plist" "$expected_bundle"
  validate_signed_identity "$entitlements_file" "$expected_team" "$expected_bundle"

  certificate_prefix="$private_dir/signing-certificate-"
  codesign_log="$private_dir/codesign-certificates.log"
  : >"$codesign_log"
  chmod 600 "$codesign_log"
  previous_umask="$(umask)"
  umask 077
  status=0
  codesign -d --extract-certificates "$certificate_prefix" "$app" >"$codesign_log" 2>&1 || status=$?
  umask "$previous_umask"
  [[ "$status" -eq 0 ]] || handoff_die "Signing certificate extraction failed."
  leaf_certificate="${certificate_prefix}0"
  leaf_certificate="$(canonical_existing_file "$leaf_certificate" "Signing leaf certificate")" || return $?
  chmod 600 "$leaf_certificate"

  embedded_profile="$(canonical_existing_file "$app/embedded.mobileprovision" "Embedded provisioning profile")" || return $?
  profile_plist="$private_dir/embedded-profile.plist"
  profile_log="$private_dir/security-cms.log"
  : >"$profile_plist"
  : >"$profile_log"
  chmod 600 "$profile_plist" "$profile_log"
  if ! security cms -D -i "$embedded_profile" >"$profile_plist" 2>"$profile_log"; then
    handoff_die "Embedded provisioning profile could not be decoded."
  fi
  aps="$(plist_value_silent "$entitlements_file" aps-environment 2>/dev/null || true)"
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
  json="$(xcrun simctl list devices available --json)"
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
  local candidate newest=""
  while IFS= read -r -d '' candidate; do
    if [[ -z "$newest" || "$candidate" -nt "$newest" ]]; then
      newest="$candidate"
    fi
  done < <(find "$derived_data/Build/Products" -type d -name 'RocketFlow.app' -path '*iphoneos*' -print0 2>/dev/null)
  printf '%s\n' "$newest"
}
