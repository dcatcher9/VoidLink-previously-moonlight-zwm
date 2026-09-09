#!/bin/bash
set -euo pipefail

detached_repo="$(cd "$(dirname "$0")/.." && pwd)"
detached_common="$detached_repo/moonlight-common/moonlight-common-c"
detached_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-detached-threads.XXXXXX")"
trap 'rm -rf "$detached_run"' EXIT
if [[ "$(uname -s)" != Darwin ]]; then
    printf 'This regression exercises the real Darwin pthread implementation.\n' >&2
    exit 1
fi
if ! rg -q 'int PltCreateThreadDetached\(' "$detached_common/src/PlatformThreads.h"; then
    printf 'Production PltCreateThreadDetached declaration is required.\n' >&2
    exit 1
fi
# Address/undefined sanitizers check ownership without instrumenting the common
# library's unrelated activeThreads bookkeeping as a thread-sanitizer target.
detached_sanitizers=(-g)
if [[ "${COMMON_DETACHED_THREAD_ASAN:-0}" == 1 ]]; then
    detached_sanitizers=(-g -fsanitize=address,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer)
fi
xcrun --sdk macosx clang -std=c11 -DLC_DEBUG -Wall -Wextra -Werror -Wno-unused-parameter \
    "${detached_sanitizers[@]}" -ffunction-sections -fdata-sections -Wl,-dead_strip \
    -I "$detached_common/src" -I "$detached_common/reedsolomon" -I "$detached_common/enet/include" \
    -I "$detached_repo/libs/opus/include/opus" \
    "$detached_repo/tests/common_detached_thread_tests.c" \
    -o "$detached_run/detached-threads"
if [[ "${COMMON_DETACHED_THREAD_ASAN:-0}" == 1 ]]; then
    ASAN_OPTIONS="${ASAN_OPTIONS:+$ASAN_OPTIONS:}detect_stack_use_after_return=1:halt_on_error=1" \
    UBSAN_OPTIONS="${UBSAN_OPTIONS:+$UBSAN_OPTIONS:}halt_on_error=1" \
        "$detached_run/detached-threads"
else
    "$detached_run/detached-threads"
fi
