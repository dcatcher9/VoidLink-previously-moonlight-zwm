#!/bin/bash
set -euo pipefail
ownership_repo="$(cd "$(dirname "$0")/.." && pwd)"
ownership_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-controller-ownership.XXXXXX")"
trap 'rm -rf "$ownership_dir"' EXIT
python3 - "$ownership_repo" "$ownership_dir/ownership.m" <<'PY'
from pathlib import Path
import sys
repo = Path(sys.argv[1])
fixture = (repo/'tests/stream_controller_ownership_tests.m').read_text()
def method(source, signature):
    start = source.index(signature)
    end = source.index('\n- (', start + len(signature))
    return source[start:end]
main = (repo/'VoidLink/ViewControllers/MainFrameViewController.m').read_text()
stream = (repo/'VoidLink/ViewControllers/StreamFrameViewController.m').read_text()
fixture = fixture.replace('// ACTUAL_MAIN_QUIT_METHOD', method(main, '- (void)disconnectAndQuitStreamFromController:'))
fixture = fixture.replace('// ACTUAL_STREAM_CALLBACK_METHODS', '\n'.join(method(stream, s) for s in [
    '- (void)retireStreamPresentation {', '- (void)rumble:', '- (void) rumbleTriggers:',
    '- (void) setMotionEventState:', '- (void) setControllerLed:', '- (void) setAdaptiveTriggers:',
]))
Path(sys.argv[2]).write_text(fixture)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter \
    -I "$ownership_repo/VoidLink/Stream" \
    -I "$ownership_repo/moonlight-common/moonlight-common-c/src" \
    "$ownership_repo/VoidLink/Stream/StreamConfiguration.m" \
    "$ownership_dir/ownership.m" -framework Foundation -o "$ownership_dir/ownership"
"$ownership_dir/ownership"
