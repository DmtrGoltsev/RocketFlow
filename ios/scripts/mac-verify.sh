#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=mac-handoff-common.sh
source "$SCRIPT_DIR/mac-handoff-common.sh"

usage() {
  cat <<'EOF'
Usage: bash ios/scripts/mac-verify.sh [options]

Regenerates RocketFlow.xcodeproj in a temporary snapshot, verifies parity,
resolves locked packages, and builds/tests an iPhone simulator without signing.
The committed project is never generated in place.

Options:
  --build-only              Build the simulator app without running tests
  --skip-package-resolution Use already cached packages for a shorter verify
  --simulator UDID          Use a specific available iPhone simulator
  --derived-data PATH       DerivedData output path
  --dry-run                 Print the sanitized verification contract only
  -h, --help                Show this help
EOF
}

build_only=false
skip_packages=false
simulator=""
derived_data="$IOS_ROOT/DerivedData/MacVerify"
dry_run=false

while (($#)); do
  case "$1" in
    --build-only)
      build_only=true
      shift
      ;;
    --skip-package-resolution)
      skip_packages=true
      shift
      ;;
    --simulator)
      require_value "$1" "${2:-}"
      simulator="$2"
      shift 2
      ;;
    --derived-data)
      require_value "$1" "${2:-}"
      derived_data="$2"
      shift 2
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

[[ -z "$simulator" ]] || validate_device_identifier "$simulator"
derived_data="$(validate_derived_data_path "$derived_data")" || exit $?
verify_security_ignores
validate_source_api_contract

if [[ "$dry_run" == true ]]; then
  handoff_note "DRY-RUN simulator verification validated"
  handoff_note "project_generation=temporary"
  handoff_note "package_resolution=$([[ "$skip_packages" == true ]] && printf skipped || printf enabled)"
  handoff_note "tests=$([[ "$build_only" == true ]] && printf skipped || printf enabled)"
  handoff_note "signing=disabled"
  exit 0
fi

require_macos
for command_name in diff git mktemp python3 rsync xcodebuild xcodegen xcrun; do
  require_command "$command_name"
done
verify_xcodegen_version
mkdir -p "$derived_data"

temporary_root="$(create_private_temp_dir rocketflow-mac-verify)"
trap 'cleanup_private_temp_dir "$temporary_root"' EXIT
snapshot="$temporary_root/ios"
prepare_ios_snapshot "$snapshot" no-push
generate_snapshot_project "$snapshot"

diff -qr -x xcuserdata -x Package.resolved \
  "$IOS_ROOT/RocketFlow.xcodeproj" "$snapshot/RocketFlow.xcodeproj" >/dev/null \
  || handoff_die "XcodeGen output differs from the committed RocketFlow.xcodeproj."

source_packages="$derived_data/SourcePackages"
if [[ "$skip_packages" == false ]]; then
  xcodebuild -resolvePackageDependencies \
    -project "$snapshot/RocketFlow.xcodeproj" \
    -scheme RocketFlow-CI \
    -clonedSourcePackagesDirPath "$source_packages"
  cmp -s \
    "$IOS_ROOT/RocketFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    "$snapshot/RocketFlow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    || handoff_die "Swift package resolution differs from committed Package.resolved."
fi

package_flags=()
if [[ "$skip_packages" == true ]]; then
  package_flags+=("-disableAutomaticPackageResolution")
fi

if [[ "$build_only" == true ]]; then
  destination="generic/platform=iOS Simulator"
  if [[ -n "$simulator" ]]; then
    destination="platform=iOS Simulator,id=$simulator"
  fi
  xcodebuild build \
    -project "$snapshot/RocketFlow.xcodeproj" \
    -scheme RocketFlow-CI \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -clonedSourcePackagesDirPath "$source_packages" \
    "${package_flags[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""
else
  require_command python3
  if [[ -z "$simulator" ]]; then
    simulator="$(select_simulator_identifier)"
  fi
  xcodebuild test \
    -project "$snapshot/RocketFlow.xcodeproj" \
    -scheme RocketFlow-CI \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$derived_data" \
    -clonedSourcePackagesDirPath "$source_packages" \
    "${package_flags[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""
fi

handoff_note "Simulator verification passed without modifying the committed Xcode project."
