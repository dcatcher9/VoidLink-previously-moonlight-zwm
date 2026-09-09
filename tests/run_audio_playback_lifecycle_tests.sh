#!/bin/bash
set -euo pipefail
audio_repo="$(cd "$(dirname "$0")/.." && pwd)"
audio_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-audio-playback.XXXXXX")"
trap 'rm -rf "$audio_run"' EXIT
python3 - "$audio_repo" "$audio_run/audio.m" <<'PY'
from pathlib import Path
import re, sys
repo = Path(sys.argv[1])
source = (repo / 'VoidLink/Stream/Connection.m').read_text()
start = source.index('static void PrepareAudioPlayback(void)')
end = source.index('\nint ArInit(', start)
owner = source.index('    } interrupt:^{', source.index('_lifecycle = [[ConnectionLifecycle alloc]'))
owner_end = source.index('\n    }];', owner)
fixture = (repo / 'tests/audio_playback_lifecycle_tests.m').read_text()
fixture = fixture.replace('// SUNLIGHT_ACTUAL_AUDIO_STOP_STATE', re.search(r'static atomic_bool audioRendererStopping = true;', source)[0])
fixture = fixture.replace('// SUNLIGHT_ACTUAL_AUDIO_GATE', source[start:end])
fixture = fixture.replace('// SUNLIGHT_ACTUAL_OWNER_INTERRUPT', source[owner + len('    } interrupt:^{'):owner_end])
Path(sys.argv[2]).write_text(fixture)
PY
audio_sanitizers=(-fsanitize=address,undefined)
if [[ "${AUDIO_PLAYBACK_TSAN:-0}" == "1" ]]; then
    audio_sanitizers=(-fsanitize=thread)
fi
xcrun --sdk macosx clang -fobjc-arc -fblocks -std=gnu11 -Wall -Wextra -Werror -g \
    "${audio_sanitizers[@]}" -I "$audio_repo/VoidLink/Stream" \
    "$audio_repo/VoidLink/Stream/ConnectionLifecycle.m" "$audio_run/audio.m" \
    -framework Foundation -o "$audio_run/audio-tests"
"$audio_run/audio-tests"
