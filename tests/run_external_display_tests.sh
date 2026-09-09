#!/bin/bash
set -euo pipefail

external_display_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
external_display_run_dir="$external_display_repo_dir/Build/external-display-tests/$(date +%Y%m%d-%H%M%S)-$$"
external_display_app_dir="$external_display_run_dir/SunlightExternalDisplayTests.app"
external_display_log="$external_display_run_dir/console.log"
external_display_simulator=""

cleanup_external_display_tests() {
    if [[ -n "$external_display_simulator" ]]; then
        xcrun simctl shutdown "$external_display_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$external_display_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_external_display_tests EXIT

mkdir -p "$external_display_app_dir"
external_display_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
external_display_arch="$(uname -m)"
external_display_runtime="${EXTERNAL_DISPLAY_TEST_RUNTIME:-}"
if [[ -z "$external_display_runtime" ]]; then
    external_display_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi

cat > "$external_display_app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>SunlightExternalDisplayTests</string>
    <key>CFBundleIdentifier</key><string>com.sunlight.tests.external-display</string>
    <key>CFBundleName</key><string>Sunlight Display Tests</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>MinimumOSVersion</key><string>16.0</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>UILaunchScreen</key><dict/>
    <key>UIDeviceFamily</key><array><integer>1</integer></array>
    <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST

xcrun --sdk iphonesimulator clang \
    -target "$external_display_arch-apple-ios16.0-simulator" \
    -isysroot "$external_display_sdk" -fobjc-arc -fmodules -DDEBUG=1 \
    -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    -I "$external_display_repo_dir/VoidLink" \
    -I "$external_display_repo_dir/VoidLink/Utility" \
    -I "$external_display_repo_dir/VoidLink/Metal" \
    -I "$external_display_repo_dir/VoidLink/Stats" \
    -I "$external_display_repo_dir/moonlight-common/moonlight-common-c/src" \
    -I "$external_display_repo_dir/libs/opus/include/opus" \
    -include "$external_display_repo_dir/tests/external_display_test_prefix.h" \
    "$external_display_repo_dir/VoidLink/ExternalDisplayCoordinator.m" \
    "$external_display_repo_dir/VoidLink/ExternalDisplayViewController.m" \
    "$external_display_repo_dir/VoidLink/SBSCalibrationView.m" \
    "$external_display_repo_dir/VoidLink/Utility/Logger.m" \
    "$external_display_repo_dir/VoidLink/Metal/MetalView.m" \
    "$external_display_repo_dir/VoidLink/Utility/FrameQueue.m" \
    "$external_display_repo_dir/VoidLink/Utility/Frame.m" \
    "$external_display_repo_dir/VoidLink/Utility/FloatBuffer.m" \
    "$external_display_repo_dir/tests/external_display_tests.m" \
    "$external_display_repo_dir/tests/metal_view_lifecycle_tests.m" \
    "$external_display_repo_dir/tests/frame_queue_tests.m" \
    "$external_display_repo_dir/tests/sbs_calibration_tests.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework Metal \
    -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
    -o "$external_display_app_dir/SunlightExternalDisplayTests" \
    > "$external_display_run_dir/build.log" 2>&1 || {
        cat "$external_display_run_dir/build.log"
        exit 1
    }

codesign --force --sign - "$external_display_app_dir" > "$external_display_run_dir/signing.log" 2>&1
external_display_simulator="$(xcrun simctl create "Sunlight Display Tests $$" \
    "${EXTERNAL_DISPLAY_TEST_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" \
    "$external_display_runtime")"
printf '%s\n' "$external_display_simulator" > "$external_display_run_dir/simulator-id.txt"
xcrun simctl boot "$external_display_simulator"
xcrun simctl bootstatus "$external_display_simulator" -b > "$external_display_run_dir/boot.log" 2>&1
xcrun simctl install "$external_display_simulator" "$external_display_app_dir"

# This app contains only display presentation code. No networking, pairing, or
# session secrets are created. Preserve its live stdout/stderr for diagnostics.
printf 'Live test console: %s\n' "$external_display_log"
xcrun simctl launch --console "$external_display_simulator" \
    com.sunlight.tests.external-display > "$external_display_log" 2>&1 || true
external_display_data_dir="$(xcrun simctl get_app_container "$external_display_simulator" com.sunlight.tests.external-display data)"
if [[ -f "$external_display_data_dir/Documents/readiness-1920x1080.png" ]]; then
    cp "$external_display_data_dir/Documents/readiness-1920x1080.png" "$external_display_run_dir/readiness-1920x1080.png"
fi
for external_display_preview_name in calibration-normal-3840x1080.png calibration-swapped-3840x1080.png; do
    if [[ -f "$external_display_data_dir/Documents/$external_display_preview_name" ]]; then
        cp "$external_display_data_dir/Documents/$external_display_preview_name" "$external_display_run_dir/$external_display_preview_name"
    fi
done
cat "$external_display_log"
if ! rg -q '^EXTERNAL_DISPLAY_TESTS_RESULT: PASS ' "$external_display_log"; then
    printf 'External display tests failed; diagnostics: %s\n' "$external_display_run_dir" >&2
    exit 1
fi
printf 'External display test artifacts: %s\n' "$external_display_run_dir"
