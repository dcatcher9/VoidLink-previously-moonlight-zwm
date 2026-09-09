#!/bin/bash
set -euo pipefail
mic_repo="$(cd "$(dirname "$0")/.." && pwd)"
mic_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-microphone-lifecycle.XXXXXX")"
trap 'rm -rf "$mic_run"' EXIT
python3 - "$mic_repo" "$mic_run" <<'PY'
from pathlib import Path
import sys
repo, out = map(Path, sys.argv[1:])
def method(source, signature):
    start = source.index(signature)
    body = source.index('{', start)
    depth = 1
    end = body + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
frame = (repo/'VoidLink/ViewControllers/StreamFrameViewController.m').read_text()
core = (repo/'moonlight-common/moonlight-common-c/src/Connection.c').read_text()
stages = core[core.index('static const char* stageNames'):core.index('// Interrupt a pending connection')]
(out/'stage_names.inc').write_text(stages)
(out/'stream_microphone_methods.inc').write_text('\n'.join(method(frame,sig) for sig in [
    '- (void)stopMicrophoneCapture {', '- (void) stageComplete:(const char*)stageName {']))
mic = (repo/'VoidLink/Input/MicHandler.swift').read_text()
methods = '\n'.join(method(mic,sig) for sig in [
    'private func handleInterruption(', '@objc public func startTapping()',
    '@objc public func stopTapping(', 'private func sendOpusFrameFromDequeBuffer()',
    '@objc public func clean()'])
# Substitute only the timer scheduler; invoke the actual delayed resume bodies explicitly.
methods = methods.replace('DispatchQueue.main.asyncAfter', 'FixtureScheduler.after').replace('private func ', 'func ')
fixture = (repo/'tests/microphone_capture_tests.swift').read_text()
(out/'capture.swift').write_text(fixture.replace('// PRODUCTION_METHODS', methods))
PY
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -I "$mic_run" -I "$mic_repo/moonlight-common/moonlight-common-c/src" \
    "$mic_repo/tests/microphone_lifecycle_tests.m" -framework Foundation -o "$mic_run/stages"
"$mic_run/stages"
xcrun --sdk macosx swiftc "$mic_run/capture.swift" -o "$mic_run/capture"
"$mic_run/capture"
