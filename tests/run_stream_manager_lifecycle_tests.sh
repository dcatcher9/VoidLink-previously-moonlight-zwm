#!/bin/bash
set -euo pipefail
manager_repo="$(cd "$(dirname "$0")/.." && pwd)"
manager_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-manager-lifecycle.XXXXXX")"
trap 'rm -rf "$manager_run"' EXIT
mkdir "$manager_run/dependencies"

# Copy exact production sources to make quote-import lookup select controlled
# dependency doubles. No manager code is rewritten or removed by this harness.
cp "$manager_repo/VoidLink/Stream/StreamManager.m" "$manager_repo/VoidLink/Stream/StreamManager.h" "$manager_run/"
cp "$manager_repo/VoidLink/Network/HttpRequest.m" "$manager_run/"
for manager_header in Connection CryptoManager HttpManager Utils DataManager StreamView ServerInfoResponse IdManager LocalizationHelper VoidLink-Swift; do
    printf '#import "stream_manager_lifecycle_doubles.h"\n' > "$manager_run/dependencies/$manager_header.h"
done
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-format-extra-args \
    -I "$manager_run" -I "$manager_run/dependencies" -I "$manager_repo/tests" \
    -I "$manager_repo/VoidLink/Stream" -I "$manager_repo/VoidLink/Network" \
    -I "$manager_repo/VoidLink/Utility" \
    -I "$manager_repo/moonlight-common/moonlight-common-c/src" \
    -I "$manager_repo/libs/opus/include/opus" \
    -I "$(xcrun --sdk macosx --show-sdk-path)/usr/include/libxml2" \
    -include "$manager_repo/tests/http_response_test_prefix.h" \
    "$manager_run/StreamManager.m" \
    "$manager_repo/VoidLink/Stream/StreamConfiguration.m" \
    "$manager_repo/VoidLink/Network/HttpResponse.m" \
    "$manager_run/HttpRequest.m" \
    "$manager_repo/tests/stream_manager_lifecycle_tests.m" \
    -framework Foundation -lxml2 -o "$manager_run/lifecycle"
"$manager_run/lifecycle"
