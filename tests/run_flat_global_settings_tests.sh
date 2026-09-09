#!/bin/bash
set -euo pipefail
flat_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
flat_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-flat-global.XXXXXX")"
trap 'rm -f "$flat_test_dir/flat.m" "$flat_test_dir/flat"; rmdir "$flat_test_dir"' EXIT
python3 - "$flat_repo_dir" "$flat_test_dir/flat.m" <<'PY'
from pathlib import Path
import sys
repo = Path(sys.argv[1])
source = (repo / 'VoidLink/ViewControllers/SettingsViewController.m').read_text()
helpers = []
for marker in ['SUNLIGHT_CATEGORY_EDITED_VALUES', 'SUNLIGHT_FLAT_GLOBAL_QUALITY']:
    begin, end = '// '+marker+'_BEGIN', '// '+marker+'_END'
    assert source.count(begin) == source.count(end) == 1
    helpers.append(source.split(begin, 1)[1].split(end, 1)[0])
tests = (repo / 'tests/flat_global_settings_tests.m').read_text()
methods = []
for signature in [
    '- (CMVideoDimensions)getChosenPresetStreamDimensions {',
    '- (CMVideoDimensions)getChosenStreamDimensions {',
    '- (InterpolationResolutionConfiguration *)getCurrentInterpolationResolutionConfiguration {',
    '- (void)streamDimensionScaleSliderMoved:(UISlider *)sender {',
]:
    assert source.count(signature) == 1, signature
    start = source.index(signature)
    # These standalone methods end immediately before the next Objective-C
    # method. Copy the original source intact; doubles only replace dependencies.
    end = source.index('\n- (', start + len(signature))
    methods.append(source[start:end])
placeholder = '// SUNLIGHT_ACTUAL_NATIVE_RESOLUTION_METHODS'
assert tests.count(placeholder) == 1
tests = tests.replace(placeholder, '\n'.join(methods))
Path(sys.argv[2]).write_text('#import <Foundation/Foundation.h>\n' + '\n'.join(helpers) + '\n' + tests)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    "$flat_test_dir/flat.m" -framework Foundation -o "$flat_test_dir/flat"
"$flat_test_dir/flat"
