#!/bin/bash
set -euo pipefail
pair_repo="$(cd "$(dirname "$0")/.." && pwd)"
pair_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-crypto-pairing.XXXXXX")"
trap 'rm -rf "$pair_run"' EXIT
pair_sdk="$(xcrun --sdk macosx --show-sdk-path)"
pair_framework="${SUNLIGHT_TEST_OPENSSL_FRAMEWORK:-$pair_repo/build/DerivedData/SourcePackages/artifacts/openssl-package/OpenSSL/OpenSSL.xcframework/macos-arm64_x86_64/OpenSSL.framework}"
if [[ ! -f "$pair_framework/Versions/A/OpenSSL" ]]; then
    printf 'OpenSSL macOS framework unavailable: set SUNLIGHT_TEST_OPENSSL_FRAMEWORK.\n' >&2
    exit 1
fi
ln -s "$pair_framework/Headers" "$pair_run/openssl"
pair_sanitizers=(-g)
if [[ "${SANITIZE:-0}" == 1 ]]; then
    pair_sanitizers=(-g -fsanitize=address,undefined -fno-omit-frame-pointer -fsanitize-address-use-after-scope)
    export ASAN_OPTIONS="detect_stack_use_after_return=1:halt_on_error=1"
    export UBSAN_OPTIONS="halt_on_error=1"
fi
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations -Wno-unused-parameter \
    "${pair_sanitizers[@]}" -isysroot "$pair_sdk" \
    -I "$pair_repo/tests/crypto_pairing_support" -I "$pair_run" \
    -I "$pair_repo/VoidLink/Crypto" -I "$pair_repo/VoidLink/Network" \
    -I "$pair_repo/VoidLink/Stream" -I "$pair_repo/moonlight-common/moonlight-common-c/src" \
    -I "$pair_sdk/usr/include/libxml2" -include "$pair_repo/tests/crypto_pairing_support/prefix.h" \
    "$pair_repo/VoidLink/Crypto/CryptoManager.m" "$pair_repo/VoidLink/Network/PairManager.m" \
    "$pair_repo/VoidLink/Network/HttpManager.m" "$pair_repo/VoidLink/Network/HttpRequest.m" \
    "$pair_repo/VoidLink/Network/HttpResponse.m" "$pair_repo/VoidLink/Stream/StreamConfiguration.m" \
    "$pair_repo/tests/crypto_pairing_tests.m" \
    "$pair_framework/Versions/A/OpenSSL" -Wl,-rpath,"$(dirname "$pair_framework")" \
    -framework Foundation -framework Security -lxml2 -o "$pair_run/pairing"
"$pair_run/pairing"
