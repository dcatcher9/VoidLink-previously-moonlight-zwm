#!/bin/bash
set -euo pipefail
startup_repo="$(cd "$(dirname "$0")/.." && pwd)"
startup_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-controller-startup.XXXXXX")"
trap 'rm -rf "$startup_run"' EXIT
python3 - "$startup_repo/VoidLink/Input/ControllerSupport.m" "$startup_run/controller_startup.inc" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('-(void)connectionEstablished {')
end = source.index('\n-(void)stopTimerForController:', start)
Path(sys.argv[2]).write_text(source[start:end] + '\n')
PY
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -I "$startup_run" -I "$startup_repo/moonlight-common/moonlight-common-c/src" \
    "$startup_repo/tests/controller_startup_tests.m" -framework Foundation -o "$startup_run/startup"
"$startup_run/startup"
