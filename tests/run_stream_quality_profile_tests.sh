#!/bin/bash
set -euo pipefail
quality_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
quality_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-quality-profile-tests.XXXXXX")"
trap 'rm -f "$quality_test_dir/profiles"; rmdir "$quality_test_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -I "$quality_repo_dir/VoidLink" -I "$quality_repo_dir/VoidLink/Stream" \
    "$quality_repo_dir/VoidLink/SunlightStreamQualityProfile.m" \
    "$quality_repo_dir/tests/stream_quality_profile_tests.m" \
    -framework Foundation -o "$quality_test_dir/profiles"
"$quality_test_dir/profiles"
