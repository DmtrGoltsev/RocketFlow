#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=mac-handoff-common.sh
source "$SCRIPT_DIR/mac-handoff-common.sh"

usage() {
  cat <<'EOF'
Usage: bash ios/scripts/mac-install-device.sh --device UDID [options]

Validates and installs an already signed RocketFlow.app with devicectl. It does
not create an archive or IPA and never prints device, signing, or app paths.

Options:
  --device UDID          Required physical-device identifier
  --app PATH             Built RocketFlow.app (default: newest device build)
  --derived-data PATH    DerivedData searched when --app is omitted
  --config PATH          Local Device.xcconfig path
  --mode no-push|push    Expected signed capability mode (default: no-push)
  --launch               Launch the app after a successful install
  --dry-run              Validate local arguments without codesign/devicectl
  -h, --help             Show this help
EOF
}

device=""
app=""
derived_data="$IOS_ROOT/DerivedData/Device"
config="$DEFAULT_DEVICE_CONFIG"
mode="no-push"
launch=false
dry_run=false

while (($#)); do
  case "$1" in
    --device)
      require_value "$1" "${2:-}"
      device="$2"
      shift 2
      ;;
    --app)
      require_value "$1" "${2:-}"
      app="$2"
      shift 2
      ;;
    --derived-data)
      require_value "$1" "${2:-}"
      derived_data="$2"
      shift 2
      ;;
    --config)
      require_value "$1" "${2:-}"
      config="$2"
      shift 2
      ;;
    --mode)
      require_value "$1" "${2:-}"
      mode="$2"
      shift 2
      ;;
    --launch)
      launch=true
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
bundle="$(xcconfig_value "$config" PRODUCT_BUNDLE_IDENTIFIER)"
team="$(xcconfig_value "$config" DEVELOPMENT_TEAM)"
derived_data="$(validate_derived_data_path "$derived_data")" || exit $?
verify_security_ignores
validate_source_api_contract

if [[ -z "$app" ]]; then
  app="$(newest_device_app "$derived_data")"
fi
[[ -n "$app" ]] || handoff_die "A built .app directory is required."
app="$(canonical_existing_directory "$app" "Built app")" || exit $?
[[ "$app" == *.app ]] || handoff_die "Built app must be an .app directory."

if [[ "$dry_run" == true ]]; then
  handoff_note "DRY-RUN device install validated"
  handoff_note "device=validated"
  handoff_note "app=validated"
  handoff_note "mode=$mode"
  handoff_note "launch=$launch"
  handoff_note "archive_or_ipa=not-created"
  exit 0
fi

require_macos
for command_name in codesign mktemp python3 security stat xcrun; do
  require_command "$command_name"
done
private_dir="$(create_private_temp_dir rocketflow-device-install)"
trap 'cleanup_private_temp_dir "$private_dir"' EXIT

verify_signed_app "$app" "$bundle" "$team" "$device" "$mode" "$private_dir"

status=0
capture_command "$private_dir/device-info.log" xcrun devicectl device info details --device "$device" || status=$?
[[ "$status" -eq 0 ]] || handoff_die "Connected-device validation failed (exit $status)."

status=0
capture_command "$private_dir/device-install.log" \
  xcrun devicectl device install app --device "$device" "$app" || status=$?
if [[ "$status" -ne 0 ]]; then
  handoff_die "Device installation failed (exit $status). Use Xcode Window > Devices and Simulators to install the already signed RocketFlow.app, or fix the Apple Account in Xcode and repeat the build script."
fi

if [[ "$launch" == true ]]; then
  status=0
  capture_command "$private_dir/device-launch.log" \
    xcrun devicectl device process launch --device "$device" "$bundle" || status=$?
  [[ "$status" -eq 0 ]] || handoff_die "The app was installed but device launch failed (exit $status)."
fi

handoff_note "Device installation passed."
handoff_note "No archive or IPA was created."
