#!/bin/bash
set -euo pipefail

persistence_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
persistence_run_dir="$persistence_repo_dir/Build/settings-persistence-tests/$(date +%Y%m%d-%H%M%S)-$$"
persistence_app_dir="$persistence_run_dir/SunlightSettingsPersistenceTests.app"
persistence_generated_dir="$persistence_run_dir/generated"
persistence_log="$persistence_run_dir/console.log"
persistence_simulator=""

cleanup_persistence_tests() {
    if [[ -n "$persistence_simulator" ]]; then
        xcrun simctl shutdown "$persistence_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$persistence_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_persistence_tests EXIT

mkdir -p "$persistence_app_dir" "$persistence_generated_dir"
persistence_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
persistence_arch="$(uname -m)"
persistence_runtime="${SETTINGS_PERSISTENCE_TEST_RUNTIME:-}"
if [[ -z "$persistence_runtime" ]]; then
    persistence_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi

cat > "$persistence_app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>SunlightSettingsPersistenceTests</string>
    <key>CFBundleIdentifier</key><string>com.sunlight.tests.settings-persistence</string>
    <key>CFBundleName</key><string>Sunlight Settings Persistence Tests</string>
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

xcrun momc --sdkroot="$persistence_sdk" --iphoneos-deployment-target 16.0 --action generate \
    "$persistence_repo_dir/VoidLink/Limelight.xcdatamodeld" "$persistence_generated_dir"
xcrun momc --sdkroot="$persistence_sdk" --iphoneos-deployment-target 16.0 \
    "$persistence_repo_dir/VoidLink/Limelight.xcdatamodeld" "$persistence_app_dir/Limelight.momd"
xcrun --sdk iphonesimulator clang \
    -target "$persistence_arch-apple-ios16.0-simulator" \
    -isysroot "$persistence_sdk" -fobjc-arc -fmodules -DDEBUG=1 \
    -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -Wno-incomplete-implementation \
    -I "$persistence_repo_dir/tests/settings_persistence_support" \
    -I "$persistence_generated_dir" \
    -I "$persistence_repo_dir/VoidLink" \
    -I "$persistence_repo_dir/VoidLink/Database" \
    -I "$persistence_repo_dir/VoidLink/Utility" \
    -I "$persistence_repo_dir/VoidLink/Stream" \
    -I "$persistence_repo_dir/moonlight-common/moonlight-common-c/src" \
    -I "$persistence_repo_dir/libs/opus/include/opus" \
    -include "$persistence_repo_dir/tests/settings_persistence_test_prefix.h" \
    "$persistence_repo_dir/VoidLink/Stream/StreamConfiguration.m" \
    "$persistence_repo_dir/VoidLink/ExternalDisplayCoordinator.m" \
    "$persistence_repo_dir/VoidLink/ExternalDisplayViewController.m" \
    "$persistence_repo_dir/VoidLink/SBSCalibrationView.m" \
    "$persistence_repo_dir/VoidLink/Database/DataManager.m" \
    "$persistence_repo_dir/VoidLink/SunlightStreamQualityProfile.m" \
    "$persistence_repo_dir/VoidLink/Database/TemporarySettings.m" \
    "$persistence_repo_dir/VoidLink/Database/TemporaryHost.m" \
    "$persistence_repo_dir/VoidLink/Database/TemporaryApp.m" \
    "$persistence_repo_dir/VoidLink/Utility/Logger.m" \
    "$persistence_generated_dir"/*.m \
    "$persistence_repo_dir/tests/settings_persistence_tests.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreData \
    -o "$persistence_app_dir/SunlightSettingsPersistenceTests" > "$persistence_run_dir/build.log" 2>&1 || {
        cat "$persistence_run_dir/build.log"
        exit 1
    }

codesign --force --sign - "$persistence_app_dir" > "$persistence_run_dir/signing.log" 2>&1
persistence_simulator="$(xcrun simctl create "Sunlight Settings Persistence Tests $$" \
    "${SETTINGS_PERSISTENCE_TEST_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" \
    "$persistence_runtime")"
printf '%s\n' "$persistence_simulator" > "$persistence_run_dir/simulator-id.txt"
xcrun simctl boot "$persistence_simulator"
xcrun simctl bootstatus "$persistence_simulator" -b > "$persistence_run_dir/boot.log" 2>&1
xcrun simctl install "$persistence_simulator" "$persistence_app_dir"

# The fixture has an isolated store and no network or pairing code. Preserve
# live console output before deleting its dedicated simulator.
printf 'Live test console: %s\n' "$persistence_log"
# Bound the UI/main/store concurrency regression too: a main-thread deadlock
# cannot execute the fixture's own watchdog. Keep this timeout outside the app.
/usr/bin/python3 - "$persistence_simulator" "$persistence_log" <<'PY_LAUNCH'
import subprocess
import sys
with open(sys.argv[2], "w") as output:
    process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", sys.argv[1],
                                "com.sunlight.tests.settings-persistence"], stdout=output, stderr=subprocess.STDOUT)
    try:
        process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        output.write("\nSETTINGS_PERSISTENCE_TESTS_RESULT: FAIL external 90-second deadline (possible main/store deadlock)\n")
PY_LAUNCH
cat "$persistence_log"
if ! rg -q '^SETTINGS_PERSISTENCE_TESTS_RESULT: PASS ' "$persistence_log"; then
    printf 'Settings persistence tests failed; diagnostics: %s\n' "$persistence_run_dir" >&2
    exit 1
fi
printf 'Settings persistence test artifacts: %s\n' "$persistence_run_dir"
