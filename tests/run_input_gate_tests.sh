#!/bin/bash
set -euo pipefail
input_repo="$(cd "$(dirname "$0")/.." && pwd)"
input_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-input-gate.XXXXXX")"
trap 'rm -rf "$input_run"' EXIT
input_flags=(-g)
if [[ "${INPUT_GATE_TSAN:-0}" == "1" ]]; then
    input_flags=(-g -fsanitize=thread)
fi
xcrun --sdk macosx clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror \
    "${input_flags[@]}" -I "$input_repo/VoidLink/Input" \
    "$input_repo/VoidLink/Input/SunlightInputGate.m" \
    "$input_repo/tests/input_gate_tests.m" -framework Foundation -o "$input_run/input-gate"
"$input_run/input-gate"
