#!/bin/bash
set -euo pipefail

startup_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
startup_run_dir="$startup_repo_dir/Build/startup-storage-tests/$(date +%Y%m%d-%H%M%S)-$$"
startup_app_dir="$startup_run_dir/SunlightStartupStorageTests.app"
startup_log="$startup_run_dir/console.log"
startup_simulator=""

cleanup_startup_tests() {
    if [[ -n "$startup_simulator" ]]; then
        xcrun simctl shutdown "$startup_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$startup_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_startup_tests EXIT

mkdir -p "$startup_app_dir"
startup_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
startup_arch="$(uname -m)"
startup_runtime="${STARTUP_STORAGE_TEST_RUNTIME:-}"
if [[ -z "$startup_runtime" ]]; then
    startup_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi

cat > "$startup_app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>SunlightStartupStorageTests</string>
    <key>CFBundleIdentifier</key><string>com.sunlight.tests.startup-storage</string>
    <key>CFBundleName</key><string>Sunlight Startup Storage Tests</string>
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

python3 - "$startup_repo_dir" "$startup_run_dir/fixture.m" <<'PY_FIXTURE'
from pathlib import Path
import sys
repo = Path(sys.argv[1]); scene = (repo / 'VoidLink/SceneDelegate.m').read_text()
a = scene.index('- (void)refreshExternalDisplayPreference {'); b = scene.index('\n- (void)', a + 1)
fixture = (repo / 'tests/startup_storage_tests.m').read_text()
Path(sys.argv[2]).write_text(fixture.replace('// SUNLIGHT_ACTUAL_STORAGE_PREFERENCE_METHOD', scene[a:b]))
PY_FIXTURE
xcrun --sdk iphonesimulator clang -target "$startup_arch-apple-ios16.0-simulator" \
    -isysroot "$startup_sdk" -fobjc-arc -fmodules -DDEBUG=1 \
    -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -Wno-incomplete-implementation \
    -I "$startup_repo_dir/tests/startup_storage_support" \
    -I "$startup_repo_dir/VoidLink" -I "$startup_repo_dir/VoidLink/Utility" \
    -include "$startup_repo_dir/tests/settings_persistence_test_prefix.h" \
    "$startup_repo_dir/VoidLink/AppDelegate.m" "$startup_repo_dir/VoidLink/Utility/Logger.m" \
    "$startup_repo_dir/VoidLink/SunlightUITheme.m" \
    "$startup_run_dir/fixture.m" -framework UIKit -framework Foundation -framework CoreData \
    -o "$startup_app_dir/SunlightStartupStorageTests" > "$startup_run_dir/build.log" 2>&1 || { cat "$startup_run_dir/build.log"; exit 1; }

codesign --force --sign - "$startup_app_dir" > "$startup_run_dir/signing.log" 2>&1
startup_simulator="$(xcrun simctl create "Sunlight Startup Storage Tests $$" \
    "${STARTUP_STORAGE_TEST_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro}" \
    "$startup_runtime")"
printf '%s\n' "$startup_simulator" > "$startup_run_dir/simulator-id.txt"
xcrun simctl boot "$startup_simulator"
xcrun simctl bootstatus "$startup_simulator" -b > "$startup_run_dir/boot.log" 2>&1
xcrun simctl install "$startup_simulator" "$startup_app_dir"

# The fixture has an isolated store and no network or pairing code. Preserve
# live console output before deleting its dedicated simulator.
printf 'Live test console: %s\n' "$startup_log"
# Bound the UI/main/store concurrency regression too: a main-thread deadlock
# cannot execute the fixture's own watchdog. Keep this timeout outside the app.
/usr/bin/python3 - "$startup_simulator" "$startup_log" <<'PY_LAUNCH'
import subprocess
import sys
with open(sys.argv[2], "w") as output:
    process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", sys.argv[1],
                                "com.sunlight.tests.startup-storage"], stdout=output, stderr=subprocess.STDOUT)
    try:
        process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        output.write("\nSTARTUP_STORAGE_TESTS_RESULT: FAIL external 90-second deadline (possible main/store deadlock)\n")
PY_LAUNCH
cat "$startup_log"
if ! rg -q '^STARTUP_STORAGE_TESTS_RESULT: PASS ' "$startup_log"; then
    printf 'Startup storage tests failed; diagnostics: %s\n' "$startup_run_dir" >&2
    exit 1
fi
printf 'Startup storage test artifacts: %s\n' "$startup_run_dir"
