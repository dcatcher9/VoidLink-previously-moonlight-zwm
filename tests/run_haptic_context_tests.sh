#!/bin/bash
set -euo pipefail
haptic_repo="$(cd "$(dirname "$0")/.." && pwd)"
haptic_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-haptic-context.XXXXXX")"
trap 'rm -rf "$haptic_run"' EXIT
haptic_flags=(-g)
if [[ "${HAPTIC_TSAN:-0}" == 1 ]]; then haptic_flags=(-g -fsanitize=thread); fi
xcrun --sdk macosx clang -fobjc-arc -fblocks -fmodules -Wall -Wextra -Werror -Wno-unused-parameter \
    "${haptic_flags[@]}" -I "$haptic_repo/VoidLink/Input" \
    -include "$haptic_repo/tests/http_response_test_prefix.h" \
    "$haptic_repo/VoidLink/Input/HapticContext.m" "$haptic_repo/tests/haptic_context_tests.m" \
    -framework Foundation -framework CoreHaptics -framework GameController -o "$haptic_run/haptics"
"$haptic_run/haptics"
