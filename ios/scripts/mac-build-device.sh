#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=mac-handoff-common.sh
source "$SCRIPT_DIR/mac-handoff-common.sh"

usage() {
  cat <<'EOF'
Usage: bash ios/scripts/mac-build-device.sh --device UDID [options]

Builds a signed Debug .app for one connected iPhone from a temporary XcodeGen
snapshot. Default no-push mode strips app entitlements and excludes Firebase
configuration while keeping local task reminders available.

Options:
  --device UDID               Required physical-device identifier
  --mode no-push|push         Capability mode (default: no-push)
  --config PATH               Local Device.xcconfig path
  --firebase-plist PATH       Local GoogleService-Info.plist for push mode
  --derived-data PATH         DerivedData/output path
  --allow-device-registration Allow Xcode to register the device if needed
  --dry-run                   Validate and print sanitized build settings only
  -h, --help                  Show this help
EOF
}

device=""
mode="no-push"
config="$DEFAULT_DEVICE_CONFIG"
firebase_plist="$GOOGLE_SERVICE_INFO"
derived_data="$IOS_ROOT/DerivedData/Device"
allow_device_registration=false
dry_run=false

while (($#)); do
  case "$1" in
    --device)
      require_value "$1" "${2:-}"
      device="$2"
      shift 2
      ;;
    --mode)
      require_value "$1" "${2:-}"
      mode="$2"
      shift 2
      ;;
    --config)
      require_value "$1" "${2:-}"
      config="$2"
      shift 2
      ;;
    --firebase-plist)
      require_value "$1" "${2:-}"
      firebase_plist="$2"
      shift 2
      ;;
    --derived-data)
      require_value "$1" "${2:-}"
      derived_data="$2"
      shift 2
      ;;
    --allow-device-registration)
      allow_device_registration=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) handoff_die "Unknown option: $1" ;;
  esac
done

[[ -n "$device" ]] || handoff_die "--device is required."
validate_device_identifier "$device"
validate_mode "$mode"
config="$(canonical_sensitive_input "$config" "Device xcconfig")" || exit $?
validate_device_config "$config"
verify_security_ignores
validate_source_api_contract
derived_data="$(validate_derived_data_path "$derived_data")" || exit $?

team="$(xcconfig_value "$config" DEVELOPMENT_TEAM)"
bundle="$(xcconfig_value "$config" PRODUCT_BUNDLE_IDENTIFIER)"
if [[ "$mode" == "push" ]]; then
  firebase_plist="$(canonical_sensitive_input "$firebase_plist" "Firebase plist")" || exit $?
  validate_push_contract "$firebase_plist" "$bundle"
fi

if [[ "$mode" == "no-push" ]]; then
  mode_build_settings=(
    "CODE_SIGN_ENTITLEMENTS="
    "EXCLUDED_SOURCE_FILE_NAMES=GoogleService-Info.plist"
  )
else
  mode_build_settings=("CODE_SIGN_ENTITLEMENTS=RocketFlow/RocketFlow.entitlements")
fi

if [[ "$dry_run" == true ]]; then
  handoff_note "DRY-RUN device build validated"
  handoff_note "mode=$mode"
  handoff_note "automatic_signing=enabled"
  if [[ "$mode" == "no-push" ]]; then
    printf '%s\n' "${mode_build_settings[@]}"
    handoff_note "local_reminders=available"
  else
    printf '%s\n' "${mode_build_settings[@]}"
    handoff_note "firebase_plist=validated"
    handoff_note "backend_readiness=not_asserted"
  fi
  exit 0
fi

require_macos
for command_name in codesign mktemp python3 rsync security stat xcodebuild xcodegen xcrun; do
  require_command "$command_name"
done
verify_xcodegen_version

mkdir -p "$derived_data"
temporary_root="$(create_private_temp_dir rocketflow-device-build)"
trap 'cleanup_private_temp_dir "$temporary_root"' EXIT
snapshot="$temporary_root/ios"
build_log="$temporary_root/xcodebuild.log"

status=0
capture_command "$temporary_root/device-info.log" xcrun devicectl device info details --device "$device" || status=$?
[[ "$status" -eq 0 ]] || handoff_die "Connected-device validation failed (exit $status)."

prepare_ios_snapshot "$snapshot" "$mode"
if [[ "$mode" == "push" ]]; then
  install_push_plist_in_snapshot "$firebase_plist" "$snapshot"
fi
generate_snapshot_project "$snapshot"

build_command=(
  xcodebuild build -quiet
  -project "$snapshot/RocketFlow.xcodeproj"
  -scheme RocketFlow
  -configuration Debug
  -destination "platform=iOS,id=$device"
  -derivedDataPath "$derived_data"
  -xcconfig "$config"
  -allowProvisioningUpdates
  "DEVELOPMENT_TEAM=$team"
  "PRODUCT_BUNDLE_IDENTIFIER=$bundle"
  CODE_SIGN_STYLE=Automatic
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=YES
  "ROCKETFLOW_API_BASE_URL=$PRODUCTION_API_BASE_URL"
)
if [[ "$allow_device_registration" == true ]]; then
  build_command+=("-allowProvisioningDeviceRegistration")
fi
build_command+=("${mode_build_settings[@]}")

status=0
capture_command "$build_log" "${build_command[@]}" || status=$?
[[ "$status" -eq 0 ]] \
  || handoff_die "Signed device build failed (exit $status). Fix the Apple Account in Xcode, then repeat this script."

app="$(newest_device_app "$derived_data")"
[[ -n "$app" && -d "$app" ]] || handoff_die "The signed RocketFlow.app was not found in DerivedData."
verify_signed_app "$app" "$bundle" "$team" "$device" "$mode" "$temporary_root"

handoff_note "Signed device build passed."
handoff_note "built_app=RocketFlow.app"
handoff_note "No archive or IPA was created."
