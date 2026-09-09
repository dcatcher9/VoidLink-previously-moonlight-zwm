#!/bin/bash
set -euo pipefail
interpolator_repo="$(cd "$(dirname "$0")/.." && pwd)"
interpolator_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-interpolator-queue.XXXXXX")"
trap 'rm -rf "$interpolator_run"' EXIT
python3 - "$interpolator_repo" "$interpolator_run/main.swift" <<'PY'
from pathlib import Path
import re, sys
repo = Path(sys.argv[1])
source = (repo / 'VoidLink/Stream/FrameInterpolator.swift').read_text()
def method(signature):
    start = source.index(signature)
    body = source.index('{', start)
    depth = 1
    end = body + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
methods = [method(s) for s in [
    '    func processFrame(_ frame: Frame, completion: @escaping Completion)',
    '    func setPaused(_ paused: Bool)',
    '    private func showTransientHUDText(_ text: String)',
    '    private func requestResetLocked()',
]]
reset_start = source.index('                if self.resetRequested {', source.index('processor.process(parameters:'))
reset_end = source.index('\n\n                self.previousInterpolationPixelBuffer', reset_start)
fixture = (repo / 'tests/frame_interpolator_queue_tests.swift').read_text()
fixture = fixture.replace('// SUNLIGHT_ACTUAL_INTERPOLATOR_METHODS', '\n\n'.join(methods))
fixture = fixture.replace('// SUNLIGHT_ACTUAL_PENDING_LIMIT', re.search(r'private let maximumPendingFrames = \d+', source)[0])
fixture = fixture.replace('// SUNLIGHT_ACTUAL_PROCESSING_RESET_BRANCH', source[reset_start:reset_end])
Path(sys.argv[2]).write_text(fixture)
PY
xcrun --sdk macosx swiftc -warnings-as-errors "$interpolator_run/main.swift" -o "$interpolator_run/interpolator-tests"
"$interpolator_run/interpolator-tests"
