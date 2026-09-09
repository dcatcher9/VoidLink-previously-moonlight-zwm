#!/bin/bash
set -euo pipefail
machine_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
machine_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-machine-controls-tests.XXXXXX")"
trap 'rm -f "$machine_test_dir/machine-controls"; rmdir "$machine_test_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -I "$machine_repo_dir/VoidLink" \
    "$machine_repo_dir/VoidLink/SunlightMachineControlsSettings.m" \
    "$machine_repo_dir/tests/machine_controls_settings_tests.m" \
    -framework Foundation -o "$machine_test_dir/machine-controls"
"$machine_test_dir/machine-controls"
