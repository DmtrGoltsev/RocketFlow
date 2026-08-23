#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=mac-handoff-common.sh
source "$SCRIPT_DIR/mac-handoff-common.sh"

usage() {
  cat <<'EOF'
Usage: bash ios/scripts/mac-preflight.sh [options]

Validates a Mac before a signed personal-device build. It never asks for an
Apple password, a 2FA code, or provisioning credentials.

Options:
  --mode no-push|push       Build capability mode (default: no-push)
  --config PATH             Local Device.xcconfig path
  --firebase-plist PATH     Local GoogleService-Info.plist for push mode
  --device UDID             Validate one connected device without printing it
  --list-devices            Validate connected-device inventory with redacted output
  --dry-run                 Validate repository/config contracts without macOS tools
  -h, --help                Show this help
EOF
}

mode="no-push"
config="$DEFAULT_DEVICE_CONFIG"
firebase_plist="$GOOGLE_SERVICE_INFO"
device=""
list_devices=false
dry_run=false

while (($#)); do
  case "$1" in
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
    --device)
      require_value "$1" "${2:-}"
      device="$2"
      shift 2
      ;;
    --list-devices)
      list_devices=true
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

validate_mode "$mode"
[[ -z "$device" ]] || validate_device_identifier "$device"
config="$(canonical_sensitive_input "$config" "Device xcconfig")" || exit $?
validate_device_config "$config"
verify_security_ignores
validate_source_api_contract

[[ -f "$IOS_ROOT/project.yml" ]] || handoff_die "ios/project.yml is missing."
[[ -f "$IOS_ROOT/RocketFlow.xcodeproj/project.pbxproj" ]] || handoff_die "Committed RocketFlow.xcodeproj is missing."
lockfile="$IOS_ROOT/RocketFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
[[ -f "$lockfile" ]] || handoff_die "Committed SwiftPM Package.resolved is missing."
git -C "$REPO_ROOT" ls-files --error-unmatch \
  ios/RocketFlow.xcodeproj/project.pbxproj \
  ios/RocketFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  >/dev/null || handoff_die "Generated project and package lock must be tracked."

bundle="$(xcconfig_value "$config" PRODUCT_BUNDLE_IDENTIFIER)"
if [[ "$mode" == "push" ]]; then
  firebase_plist="$(canonical_sensitive_input "$firebase_plist" "Firebase plist")" || exit $?
  validate_push_contract "$firebase_plist" "$bundle"
fi

if [[ "$dry_run" == true ]]; then
  handoff_note "DRY-RUN preflight contract passed"
  handoff_note "mode=$mode"
  handoff_note "credentials=not-requested"
  exit 0
fi

require_macos
for command_name in git mktemp python3 rsync stat xcode-select xcodebuild xcodegen xcrun; do
  require_command "$command_name"
done

private_dir="$(create_private_temp_dir rocketflow-preflight)"
trap 'cleanup_private_temp_dir "$private_dir"' EXIT
status=0
capture_command "$private_dir/xcode-select.log" xcode-select -p || status=$?
[[ "$status" -eq 0 ]] || handoff_die "A full Xcode installation is not selected (exit $status)."
status=0
capture_command "$private_dir/xcode-version.log" xcodebuild -version || status=$?
[[ "$status" -eq 0 ]] || handoff_die "Xcode version inspection failed (exit $status)."
validate_xcode_version_file "$private_dir/xcode-version.log"
status=0
capture_command "$private_dir/xcode-first-launch.log" xcodebuild -checkFirstLaunchStatus || status=$?
[[ "$status" -eq 0 ]] || handoff_die "Complete the Xcode license and first-launch setup, then retry (exit $status)."
status=0
capture_command "$private_dir/xcode-sdks.log" xcodebuild -showsdks || status=$?
[[ "$status" -eq 0 ]] || handoff_die "Installed SDK inspection failed (exit $status)."
validate_iphoneos_sdk_file "$private_dir/xcode-sdks.log"
verify_xcodegen_version

if [[ -n "$device" ]]; then
  status=0
  capture_command "$private_dir/device-info.log" xcrun devicectl device info details --device "$device" || status=$?
  [[ "$status" -eq 0 ]] || handoff_die "Connected-device validation failed (exit $status)."
fi
if [[ "$list_devices" == true ]]; then
  status=0
  capture_command "$private_dir/device-list.log" xcrun devicectl list devices || status=$?
  [[ "$status" -eq 0 ]] || handoff_die "Connected-device inventory failed (exit $status)."
  handoff_note "connected_device_inventory=validated-redacted"
fi

handoff_note "Mac handoff preflight passed."
handoff_note "mode=$mode"
handoff_note "credentials=not-requested"
