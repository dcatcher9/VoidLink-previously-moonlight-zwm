#!/bin/bash
set -euo pipefail
stats_repo="$(cd "$(dirname "$0")/.." && pwd)"
stats_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-video-stats.XXXXXX")"
trap 'rm -rf "$stats_run"' EXIT
python3 - "$stats_repo" "$stats_run/stats.m" <<'PY'
from pathlib import Path
import sys
repo = Path(sys.argv[1])
source = (repo / 'VoidLink/Stream/Connection.m').read_text()
def function(signature):
    start = source.index(signature)
    pos = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[pos] == '{') - (source[pos] == '}')
        pos += 1
    return source[start:pos]
fixture = (repo / 'tests/video_stats_ownership_tests.m').read_text()
fixture = fixture.replace('// SUNLIGHT_ACTUAL_STATS_CALLBACKS', '\n\n'.join(function(s) for s in ['int DrDecoderSetup(', 'int DrSubmitDecodeUnit(']))
fixture = fixture.replace('// SUNLIGHT_ACTUAL_STATS_GETTER', function('-(BOOL) getVideoStats:'))
Path(sys.argv[2]).write_text(fixture)
PY
stats_sanitizers=(-fsanitize=address,undefined)
if [[ "${VIDEO_STATS_TSAN:-0}" == "1" ]]; then
    stats_sanitizers=(-fsanitize=thread)
fi
xcrun --sdk macosx clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter -g \
    "${stats_sanitizers[@]}" -I "$stats_repo/VoidLink/Stream" -I "$stats_repo/VoidLink/Utility" \
    -I "$stats_repo/moonlight-common/moonlight-common-c/src" \
    "$stats_repo/VoidLink/Stream/ConnectionLifecycle.m" "$stats_run/stats.m" \
    -framework Foundation -framework QuartzCore -o "$stats_run/stats-tests"
"$stats_run/stats-tests"
