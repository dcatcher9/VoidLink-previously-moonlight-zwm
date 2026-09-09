#!/bin/bash
set -euo pipefail
discovery_repo="$(cd "$(dirname "$0")/.." && pwd)"
discovery_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-discovery-address.XXXXXX")"
trap 'rm -rf "$discovery_run"' EXIT
python3 - "$discovery_repo/VoidLink/Network/DiscoveryWorker.m" "$discovery_run/discovery_address.inc" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('- (NSArray*) getHostAddressList {')
end = source.index('\n- (void) discoverHost {', start)
Path(sys.argv[2]).write_text(source[start:end] + '\n')
PY
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-sign-compare \
    -I "$discovery_run" "$discovery_repo/tests/discovery_address_tests.m" \
    -framework Foundation -o "$discovery_run/discovery"
"$discovery_run/discovery"
