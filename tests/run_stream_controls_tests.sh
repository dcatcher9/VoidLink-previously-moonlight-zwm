#!/bin/bash
set -euo pipefail

controls_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
controls_run_dir="$controls_repo_dir/Build/stream-controls-tests/$(date +%Y%m%d-%H%M%S)-$$"
controls_app_dir="$controls_run_dir/SunlightStreamControlsTests.app"
controls_log="$controls_run_dir/console.log"
controls_simulator=""

cleanup_controls_tests() {
    if [[ -n "$controls_simulator" ]]; then
        xcrun simctl shutdown "$controls_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$controls_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_controls_tests EXIT

mkdir -p "$controls_app_dir"
controls_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
controls_arch="$(uname -m)"
controls_runtime="${STREAM_CONTROLS_TEST_RUNTIME:-}"
if [[ -z "$controls_runtime" ]]; then
    controls_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi

cat > "$controls_app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>SunlightStreamControlsTests</string>
    <key>CFBundleIdentifier</key><string>com.sunlight.tests.stream-controls</string>
    <key>CFBundleName</key><string>Sunlight Controls Tests</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>MinimumOSVersion</key><string>16.0</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>UILaunchScreen</key><dict/>
    <key>UIDeviceFamily</key><array><integer>1</integer></array>
    <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST

xcrun --sdk iphonesimulator clang \
    -target "$controls_arch-apple-ios16.0-simulator" \
    -isysroot "$controls_sdk" -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    -I "$controls_repo_dir/VoidLink" -I "$controls_repo_dir/VoidLink/Stream" \
    -I "$controls_repo_dir/moonlight-common/moonlight-common-c/src" -I "$controls_repo_dir/libs/opus/include/opus" \
    "$controls_repo_dir/VoidLink/SunlightStreamControlsView.m" \
    "$controls_repo_dir/VoidLink/SunlightMoonlightIcons.m" \
    "$controls_repo_dir/VoidLink/SunlightUITheme.m" \
    "$controls_repo_dir/VoidLink/SunlightSharedSettingsViewController.m" \
    "$controls_repo_dir/VoidLink/SunlightMachineControlsSettings.m" \
    "$controls_repo_dir/VoidLink/SunlightSharedSettings.m" \
    "$controls_repo_dir/VoidLink/Stream/StreamConfiguration.m" \
    "$controls_repo_dir/tests/stream_controls_tests.m" \
    -framework UIKit -framework Foundation -framework QuartzCore \
    -o "$controls_app_dir/SunlightStreamControlsTests" > "$controls_run_dir/build.log" 2>&1 || {
        cat "$controls_run_dir/build.log"
        exit 1
    }

codesign --force --sign - "$controls_app_dir" > "$controls_run_dir/signing.log" 2>&1
controls_simulator="$(xcrun simctl create "Sunlight Controls Tests $$" \
    "${STREAM_CONTROLS_TEST_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" \
    "$controls_runtime")"
printf '%s\n' "$controls_simulator" > "$controls_run_dir/simulator-id.txt"
xcrun simctl boot "$controls_simulator"
xcrun simctl bootstatus "$controls_simulator" -b > "$controls_run_dir/boot.log" 2>&1
xcrun simctl install "$controls_simulator" "$controls_app_dir"

# The fixture contains only UI code and no network or pairing code. Preserve
# live console output and screenshots before deleting its dedicated simulator.
printf 'Live test console: %s\n' "$controls_log"
if [[ "${STREAM_CONTROLS_TEST_SHARED_ONLY:-0}" == 1 ]]; then
    xcrun simctl launch --console "$controls_simulator" com.sunlight.tests.stream-controls --shared-settings-only > "$controls_log" 2>&1 || true
elif [[ "${STREAM_CONTROLS_TEST_OVERLAY_ONLY:-0}" == 1 ]]; then
    xcrun simctl launch --console "$controls_simulator" com.sunlight.tests.stream-controls --overlay-only > "$controls_log" 2>&1 || true
else
    xcrun simctl launch --console "$controls_simulator" com.sunlight.tests.stream-controls > "$controls_log" 2>&1 || true
fi
controls_data_dir="$(xcrun simctl get_app_container "$controls_simulator" com.sunlight.tests.stream-controls data)"
for controls_preview in phone-control-surface-landscape.png picture-paused-hint.png picture-main-landscape.png picture-glasses-2d-landscape.png picture-host-landscape.png picture-raw-landscape.png picture-client-landscape.png picture-main-ipad.png picture-raw-portrait.png picture-large-text-top.png picture-large-text-bottom.png pc-settings-flat-video-landscape.png pc-settings-flat-input-landscape.png pc-settings-flat-actions-landscape.png pc-settings-flat-large-text.png; do
    if [[ -f "$controls_data_dir/Documents/$controls_preview" ]]; then
        cp "$controls_data_dir/Documents/$controls_preview" "$controls_run_dir/$controls_preview"
    fi
done
cat "$controls_log"
if ! rg -q '^STREAM_CONTROLS_TESTS_RESULT: PASS ' "$controls_log"; then
    printf 'Stream controls tests failed; diagnostics: %s\n' "$controls_run_dir" >&2
    exit 1
fi
printf 'Stream controls test artifacts: %s\n' "$controls_run_dir"
