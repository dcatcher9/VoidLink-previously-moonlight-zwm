#!/bin/bash
set -euo pipefail
pad_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
pad_run_dir="$pad_repo_dir/build/control-pad-tests/$(date +%Y%m%d-%H%M%S)-$$"
pad_app_dir="$pad_run_dir/SunlightControlPadTests.app"
pad_simulator=""
cleanup_pad_tests() {
    if [[ -n "$pad_simulator" ]]; then
        xcrun simctl shutdown "$pad_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$pad_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_pad_tests EXIT
mkdir -p "$pad_app_dir"
pad_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
pad_arch="$(uname -m)"
pad_runtime="${CONTROL_PAD_TEST_RUNTIME:-}"
if [[ -z "$pad_runtime" ]]; then
    pad_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi
cat > "$pad_app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SunlightControlPadTests</string>
<key>CFBundleIdentifier</key><string>com.sunlight.tests.control-pad</string>
<key>CFBundleName</key><string>Sunlight Control Pad Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>16.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict></plist>
PLIST
xcrun --sdk iphonesimulator clang \
    -target "$pad_arch-apple-ios16.0-simulator" -isysroot "$pad_sdk" \
    -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter \
    -I "$pad_repo_dir/VoidLink" \
    -I "$pad_repo_dir/moonlight-common/moonlight-common-c/src" \
    -I "$pad_repo_dir/libs/opus/include/opus" \
    "$pad_repo_dir/VoidLink/SunlightControlPadView.m" "$pad_repo_dir/tests/control_pad_tests.m" \
    "$pad_repo_dir/VoidLink/SunlightUITheme.m" \
    -framework UIKit -framework Foundation -framework QuartzCore \
    -o "$pad_app_dir/SunlightControlPadTests" > "$pad_run_dir/build.log" 2>&1 || {
        cat "$pad_run_dir/build.log"
        exit 1
    }
codesign --force --sign - "$pad_app_dir" > "$pad_run_dir/signing.log" 2>&1
pad_simulator="$(xcrun simctl create "Sunlight Control Pad Tests $$" \
    "${CONTROL_PAD_TEST_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" "$pad_runtime")"
xcrun simctl boot "$pad_simulator"
xcrun simctl bootstatus "$pad_simulator" -b > "$pad_run_dir/boot.log" 2>&1
xcrun simctl install "$pad_simulator" "$pad_app_dir"
printf 'Live test console: %s\n' "$pad_run_dir/console.log"
xcrun simctl launch --console "$pad_simulator" com.sunlight.tests.control-pad > "$pad_run_dir/console.log" 2>&1 || true
pad_data_dir="$(xcrun simctl get_app_container "$pad_simulator" com.sunlight.tests.control-pad data)"
for pad_preview in control-pad-portrait.png control-pad-landscape.png control-pad-tablet.png; do
    if [[ -f "$pad_data_dir/Documents/$pad_preview" ]]; then
        cp "$pad_data_dir/Documents/$pad_preview" "$pad_run_dir/$pad_preview"
    fi
done
cat "$pad_run_dir/console.log"
if ! rg -q '^CONTROL_PAD_TESTS_RESULT: PASS ' "$pad_run_dir/console.log"; then
    printf 'Control pad tests failed; diagnostics: %s\n' "$pad_run_dir" >&2
    exit 1
fi
printf 'Control pad test artifacts: %s\n' "$pad_run_dir"
