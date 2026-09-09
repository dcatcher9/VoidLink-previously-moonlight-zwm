#!/bin/bash
set -euo pipefail
lifecycle_repo="$(cd "$(dirname "$0")/.." && pwd)"
lifecycle_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-connection-lifecycle.XXXXXX")"
trap 'rm -rf "$lifecycle_run"' EXIT
lifecycle_sanitizer_flags=(-g)
if [[ "${CONNECTION_LIFECYCLE_TSAN:-0}" == "1" ]]; then
    lifecycle_sanitizer_flags=(-fsanitize=thread -g)
fi
xcrun --sdk macosx clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    "${lifecycle_sanitizer_flags[@]}" \
    -I "$lifecycle_repo/VoidLink/Stream" \
    "$lifecycle_repo/VoidLink/Stream/ConnectionLifecycle.m" \
    "$lifecycle_repo/tests/connection_lifecycle_tests.m" \
    -framework Foundation -o "$lifecycle_run/lifecycle"
"$lifecycle_run/lifecycle"
