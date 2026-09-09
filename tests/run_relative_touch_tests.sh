#!/bin/bash
set -euo pipefail
touch_repo="$(cd "$(dirname "$0")/.." && pwd)"
touch_run="$touch_repo/build/relative-touch-tests/$(date +%Y%m%d-%H%M%S)-$$"
touch_app="$touch_run/SunlightRelativeTouchTests.app"
touch_simulator=""
cleanup_touch_tests() {
    if [[ -n "$touch_simulator" ]]; then
        xcrun simctl shutdown "$touch_simulator" >/dev/null 2>&1 || true
        xcrun simctl delete "$touch_simulator" >/dev/null 2>&1 || true
    fi
}
trap cleanup_touch_tests EXIT
mkdir -p "$touch_app" "$touch_run/source" "$touch_run/dependencies"
# Exact copies change quote-import lookup only; no production code is rewritten.
for touch_file in RelativeTouchHandler.h RelativeTouchHandler.m CustomTapGestureRecognizer.h CustomTapGestureRecognizer.m SunlightInputDispatch.h SunlightInputGate.h SunlightInputGate.m; do
    cp "$touch_repo/VoidLink/Input/$touch_file" "$touch_run/source/"
    cmp "$touch_repo/VoidLink/Input/$touch_file" "$touch_run/source/$touch_file"
done
for touch_header in StreamView DataManager VoidLink-Swift; do
    printf '#import "relative_touch_test_doubles.h"\n' > "$touch_run/dependencies/$touch_header.h"
done
cat > "$touch_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SunlightRelativeTouchTests</string>
<key>CFBundleIdentifier</key><string>com.sunlight.tests.relative-touch</string>
<key>CFBundleName</key><string>Relative Touch Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>16.0</string><key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/><key>UIDeviceFamily</key><array><integer>1</integer></array>
</dict></plist>
PLIST
xcrun --sdk iphonesimulator clang -target "$(uname -m)-apple-ios16.0-simulator" \
    -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" -fobjc-arc -fblocks -fmodules \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-variable -Wno-deprecated-declarations \
    -I "$touch_run/source" -I "$touch_run/dependencies" -I "$touch_repo/tests" \
    -I "$touch_repo/moonlight-common/moonlight-common-c/src" -I "$touch_repo/libs/opus/include/opus" \
    -include "$touch_repo/tests/relative_touch_test_doubles.h" \
    "$touch_run/source/RelativeTouchHandler.m" "$touch_run/source/CustomTapGestureRecognizer.m" \
    "$touch_run/source/SunlightInputGate.m" "$touch_repo/tests/relative_touch_tests.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -o "$touch_app/SunlightRelativeTouchTests" \
    > "$touch_run/build.log" 2>&1 || { cat "$touch_run/build.log"; exit 1; }
if [[ "${RELATIVE_TOUCH_COMPILE_ONLY:-0}" == "1" ]]; then
    printf 'Relative touch fixture compiled: %s\n' "$touch_run"
    exit 0
fi
codesign --force --sign - "$touch_app" > "$touch_run/signing.log" 2>&1
touch_runtime="${RELATIVE_TOUCH_TEST_RUNTIME:-}"
if [[ -z "$touch_runtime" ]]; then
    touch_runtime="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]; print(max(r,key=lambda x: tuple(map(int,x["version"].split("."))))["identifier"])')"
fi
touch_simulator="$(xcrun simctl create "Sunlight Relative Touch Tests $$" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$touch_runtime")"
printf '%s\n' "$touch_simulator" > "$touch_run/simulator-id.txt"
xcrun simctl boot "$touch_simulator"
xcrun simctl bootstatus "$touch_simulator" -b > "$touch_run/boot.log" 2>&1
xcrun simctl install "$touch_simulator" "$touch_app"
xcrun simctl launch --console "$touch_simulator" com.sunlight.tests.relative-touch > "$touch_run/console.log" 2>&1 || true
cat "$touch_run/console.log"
rg -q '^RELATIVE_TOUCH_TESTS_RESULT: PASS ' "$touch_run/console.log"
printf 'Relative touch artifacts: %s\n' "$touch_run"
