#!/bin/bash
set -euo pipefail
recovery_repo="$(cd "$(dirname "$0")/.." && pwd)"
recovery_run="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-decoder-recovery.XXXXXX")"
trap 'rm -rf "$recovery_run"' EXIT
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
    -I "$recovery_repo/VoidLink/Stream" "$recovery_repo/tests/decoder_recovery_tests.c" \
    -o "$recovery_run/recovery"
"$recovery_run/recovery"

# Exercise the actual decoded-frame packing, view layout and deferred
# interpolation methods using real CoreVideo/CoreMedia ownership and controlled
# UI/queue boundaries. No simulator, decoder hardware or app launch is needed.
python3 - "$recovery_repo" "$recovery_run/presentation.m" <<'PY'
from pathlib import Path
import sys
repo = Path(sys.argv[1])
source = (repo / 'VoidLink/Stream/VideoDecoderRenderer.m').read_text()
methods = []
for signature in [
    '- (void)updateDisplayLayerLayout\n{',
    '- (FrameInterpolator *)newFrameInterpolatorWithMaximumDimension:(NSInteger)dimension\n',
    '- (void)setRequeuingRequired:(BOOL)required {',
    '- (void) checkDisplayLayer {',
    '- (void)recordIncomingFrameTiming:(Frame *)frame {',
    '- (void)startOrRestartFrameInterpolation {',
    '- (void)stopFrameInterpolation {',
    '- (Frame *)frameForDecodedImage:(CVImageBufferRef)imageBuffer\n',
]:
    # The packing selector also has a private declaration; choose its method body.
    starts = [i for i in range(len(source)) if source.startswith(signature, i)]
    start = starts[-1]
    end = source.index('\n- (', start + len(signature))
    methods.append(source[start:end])
fixture = (repo / 'tests/decoder_presentation_tests.m').read_text()
marker = '// SUNLIGHT_ACTUAL_DECODER_PRESENTATION_METHODS'
assert fixture.count(marker) == 1
Path(sys.argv[2]).write_text(fixture.replace(marker, '\n'.join(methods)))
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -Wno-trigraphs \
    -fsanitize=address,undefined -include QuartzCore/QuartzCore.h \
    -I "$recovery_repo/VoidLink/Stream" -I "$recovery_repo/VoidLink/Utility" \
    -I "$recovery_repo/moonlight-common/moonlight-common-c/src" \
    "$recovery_run/presentation.m" "$recovery_repo/VoidLink/Utility/Frame.m" \
    -framework Foundation -framework AVFoundation -framework QuartzCore -framework VideoToolbox \
    -framework CoreMedia -framework CoreVideo -framework CoreGraphics -o "$recovery_run/presentation"
"$recovery_run/presentation"
