#!/bin/bash
set -euo pipefail
stereo_repo="$(cd "$(dirname "$0")/.." && pwd)"
stereo_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-stereo-layout.XXXXXX")"
trap 'rm -f "$stereo_test_dir/layout"; rmdir "$stereo_test_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -I "$stereo_repo/VoidLink/Metal" "$stereo_repo/tests/stereo_layout_tests.m" \
    -framework Foundation -framework CoreGraphics -o "$stereo_test_dir/layout"
"$stereo_test_dir/layout"
