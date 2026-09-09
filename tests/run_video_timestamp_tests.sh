#!/bin/bash
set -euo pipefail
timestamp_repo="$(cd "$(dirname "$0")/.." && pwd)"
timestamp_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-video-timestamp.XXXXXX")"
trap 'rm -rf "$timestamp_run"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$timestamp_repo/VoidLink/Stream" \
    -I "$timestamp_repo/moonlight-common/moonlight-common-c/src" \
    "$timestamp_repo/tests/video_timestamp_tests.m" -framework CoreMedia \
    -o "$timestamp_run/timestamps"
"$timestamp_run/timestamps"
