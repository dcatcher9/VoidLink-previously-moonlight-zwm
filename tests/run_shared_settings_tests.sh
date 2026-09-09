#!/bin/bash
set -euo pipefail
shared_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
shared_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-shared-settings-tests.XXXXXX")"
trap 'rm -f "$shared_test_dir/shared"; rmdir "$shared_test_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -I "$shared_repo_dir/VoidLink" \
    "$shared_repo_dir/VoidLink/SunlightSharedSettings.m" \
    "$shared_repo_dir/tests/shared_settings_tests.m" \
    -framework Foundation -o "$shared_test_dir/shared"
"$shared_test_dir/shared"
