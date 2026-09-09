#!/bin/bash
set -euo pipefail
command_repo="$(cd "$(dirname "$0")/.." && pwd)"
command_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-command-execution.XXXXXX")"
trap 'rm -rf "$command_run"' EXIT
command_sdk="$(xcrun --sdk macosx --show-sdk-path)"
# This production file imports UIKit without using UIKit types. A no-op module
# satisfies that import while its actual command code runs unchanged on macOS.
printf '// No UIKit API is used by CommandManager.\n' > "$command_run/UIKit.swift"
xcrun swiftc -sdk "$command_sdk" -emit-module -module-name UIKit \
    "$command_run/UIKit.swift" -emit-module-path "$command_run/UIKit.swiftmodule"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -I "$command_repo/tests" -I "$command_repo/moonlight-common/moonlight-common-c/src" \
    -I "$command_repo/libs/opus/include/opus" \
    -c "$command_repo/tests/command_execution_test_sink.m" -o "$command_run/sink.o"
xcrun swiftc -sdk "$command_sdk" -I "$command_run" \
    -I "$command_repo/moonlight-common/moonlight-common-c/src" -I "$command_repo/libs/opus/include/opus" \
    -import-objc-header "$command_repo/tests/command_execution_test_bridge.h" \
    "$command_repo/VoidLink/Input/CommandManager.swift" \
    "$command_repo/tests/command_execution_tests.swift" "$command_run/sink.o" \
    -o "$command_run/command-tests"
"$command_run/command-tests"
