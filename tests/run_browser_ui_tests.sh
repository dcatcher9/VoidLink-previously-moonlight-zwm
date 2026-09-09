#!/bin/bash
set -euo pipefail

browser_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
browser_run_dir="$browser_repo_dir/Build/browser-ui-tests/$(date +%Y%m%d-%H%M%S)-$$"
browser_app_dir="$browser_run_dir/SunlightBrowserUITests.app"
browser_log="$browser_run_dir/console.log"
browser_simulator=""

cleanup_browser_tests() {
    if [[ -n "$browser_simulator" ]]; then
        xcrun simctl shutdown "$browser_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$browser_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_browser_tests EXIT

mkdir -p "$browser_app_dir"
browser_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
browser_arch="$(uname -m)"
browser_runtime="${BROWSER_UI_TEST_RUNTIME:-}"
if [[ -z "$browser_runtime" ]]; then
    browser_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi

cat > "$browser_app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>SunlightBrowserUITests</string>
    <key>CFBundleIdentifier</key><string>com.sunlight.tests.browser-ui</string>
    <key>CFBundleName</key><string>Sunlight Browser UI Tests</string>
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

xcrun --sdk iphonesimulator clang -target "$browser_arch-apple-ios16.0-simulator" \
    -isysroot "$browser_sdk" -fobjc-arc -fmodules -I "$browser_repo_dir/VoidLink" \
    -c "$browser_repo_dir/VoidLink/SunlightUITheme.m" -o "$browser_run_dir/theme.o"
xcrun --sdk iphonesimulator clang -target "$browser_arch-apple-ios16.0-simulator" \
    -isysroot "$browser_sdk" -fobjc-arc -fmodules -I "$browser_repo_dir/VoidLink" \
    -c "$browser_repo_dir/VoidLink/SunlightMoonlightIcons.m" -o "$browser_run_dir/icons.o"
xcrun --sdk iphonesimulator swiftc -target "$browser_arch-apple-ios16.0-simulator" \
    -sdk "$browser_sdk" -I "$browser_repo_dir/VoidLink" \
    -import-objc-header "$browser_repo_dir/tests/browser_ui_test_bridge.h" \
    "$browser_repo_dir/VoidLink/UIAppView.swift" \
    "$browser_repo_dir/VoidLink/HostCardView.swift" \
    "$browser_repo_dir/VoidLink/ViewControllers/HostCollectionViewController.swift" \
    "$browser_repo_dir/tests/browser_ui_tests.swift" \
    "$browser_run_dir/theme.o" "$browser_run_dir/icons.o" \
    -framework UIKit -framework Foundation -o "$browser_app_dir/SunlightBrowserUITests" \
    > "$browser_run_dir/build.log" 2>&1 || { cat "$browser_run_dir/build.log"; exit 1; }

codesign --force --sign - "$browser_app_dir" > "$browser_run_dir/signing.log" 2>&1
browser_simulator="$(xcrun simctl create "Sunlight Browser UI Tests $$" \
    "${BROWSER_UI_TEST_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" \
    "$browser_runtime")"
printf '%s\n' "$browser_simulator" > "$browser_run_dir/simulator-id.txt"
xcrun simctl boot "$browser_simulator"
xcrun simctl bootstatus "$browser_simulator" -b > "$browser_run_dir/boot.log" 2>&1
xcrun simctl install "$browser_simulator" "$browser_app_dir"

# The fixture contains only UI code and no network or pairing code. Preserve
# live console output and diagnostics before deleting its dedicated simulator.
printf 'Live test console: %s\n' "$browser_log"
/usr/bin/python3 - "$browser_simulator" "$browser_log" <<'PY_LAUNCH'
import subprocess
import sys
with open(sys.argv[2], "w") as output:
    process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", sys.argv[1],
                                "com.sunlight.tests.browser-ui"], stdout=output, stderr=subprocess.STDOUT)
    try:
        process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        output.write("\nBROWSER_UI_TESTS_RESULT: FAIL external 90-second deadline\n")
PY_LAUNCH
cat "$browser_log"
if ! rg -q '^BROWSER_UI_TESTS_RESULT: PASS ' "$browser_log"; then
    printf 'Browser UI tests failed; diagnostics: %s\n' "$browser_run_dir" >&2
    exit 1
fi
printf 'Browser UI test artifacts: %s\n' "$browser_run_dir"
