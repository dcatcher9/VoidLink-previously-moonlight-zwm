#!/bin/bash
set -euo pipefail
termination_repo="$(cd "$(dirname "$0")/.." && pwd)"
termination_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-common-termination.XXXXXX")"
trap 'rm -rf "$termination_run"' EXIT
termination_common="$termination_repo/moonlight-common/moonlight-common-c"
termination_sanitizer_flags=(-g)
if [[ "${COMMON_TERMINATION_ASAN:-0}" == "1" ]]; then
    termination_sanitizer_flags=(-g -fsanitize=address,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer)
fi
xcrun --sdk macosx clang -std=c11 -DNDEBUG -Wall -Wextra -Werror -Wno-unused-parameter \
    "${termination_sanitizer_flags[@]}" \
    -ffunction-sections -fdata-sections -Wl,-dead_strip \
    -I "$termination_common/src" -I "$termination_common/reedsolomon" -I "$termination_common/enet/include" \
    -I "$termination_repo/libs/opus/include/opus" \
    "$termination_repo/tests/common_termination_tests.c" "$termination_common/src/Misc.c" \
    -o "$termination_run/termination"
if [[ "${COMMON_TERMINATION_ASAN:-0}" == "1" ]]; then
    # Immediate detached entry may free its payload and replace the session
    # before thread creation returns. Keep lifetime failures fatal in this run.
    ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_stack_use_after_return=1:halt_on_error=1" \
    UBSAN_OPTIONS="${UBSAN_OPTIONS:+$UBSAN_OPTIONS:}halt_on_error=1" \
        "$termination_run/termination"
else
    "$termination_run/termination"
fi
