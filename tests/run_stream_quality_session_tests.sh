#!/bin/bash
set -euo pipefail
quality_session_repo="$(cd "$(dirname "$0")/.." && pwd)"
quality_session_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-quality-session.XXXXXX")"
trap 'rm -rf "$quality_session_dir"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -I "$quality_session_repo/VoidLink" -I "$quality_session_repo/VoidLink/Stream" \
    -I "$quality_session_repo/moonlight-common/moonlight-common-c/src" \
    "$quality_session_repo/VoidLink/SunlightStreamQualitySession.m" \
    "$quality_session_repo/VoidLink/SunlightStreamQualityProfile.m" \
    "$quality_session_repo/VoidLink/Stream/StreamConfiguration.m" \
    "$quality_session_repo/tests/stream_quality_session_tests.m" \
    -framework Foundation -framework CoreGraphics -o "$quality_session_dir/session"
"$quality_session_dir/session"
