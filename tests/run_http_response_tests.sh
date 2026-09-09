#!/bin/bash
set -euo pipefail

http_response_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
http_response_sdk="$(xcrun --sdk macosx --show-sdk-path)"
http_response_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/voidlink-http-response-tests.XXXXXX")"
trap 'rm -f "$http_response_test_dir/http_response_tests"; rmdir "$http_response_test_dir"' EXIT

xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -isysroot "$http_response_sdk" \
    -I "$http_response_repo_dir/VoidLink/Network" \
    -I "$http_response_repo_dir/tests/crypto_pairing_support" \
    -I "$http_response_sdk/usr/include/libxml2" \
    -include "$http_response_repo_dir/tests/http_response_test_prefix.h" \
    "$http_response_repo_dir/VoidLink/Network/HttpResponse.m" \
    "$http_response_repo_dir/VoidLink/Network/AppListResponse.m" \
    "$http_response_repo_dir/tests/http_response_tests.m" \
    -framework Foundation -lxml2 \
    -o "$http_response_test_dir/http_response_tests"

"$http_response_test_dir/http_response_tests"
