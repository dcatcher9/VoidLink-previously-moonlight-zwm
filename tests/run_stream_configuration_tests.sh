#!/bin/bash
set -euo pipefail

stream_configuration_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
stream_configuration_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-stream-configuration-tests.XXXXXX")"
trap 'rm -f "$stream_configuration_test_dir/stream_configuration_tests"; rmdir "$stream_configuration_test_dir"' EXIT

xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -I "$stream_configuration_repo_dir/VoidLink/Stream" \
    -I "$stream_configuration_repo_dir/moonlight-common/moonlight-common-c/src" \
    -I "$stream_configuration_repo_dir/libs/opus/include/opus" \
    "$stream_configuration_repo_dir/VoidLink/Stream/StreamConfiguration.m" \
    "$stream_configuration_repo_dir/tests/stream_configuration_tests.m" \
    -framework Foundation -o "$stream_configuration_test_dir/stream_configuration_tests"

"$stream_configuration_test_dir/stream_configuration_tests"
