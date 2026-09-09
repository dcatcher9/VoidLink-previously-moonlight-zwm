#!/bin/bash
set -euo pipefail
migration_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
migration_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunlight-global-quality-migration.XXXXXX")"
trap 'rm -f "$migration_test_dir/migration.m" "$migration_test_dir/migration"; rmdir "$migration_test_dir"' EXIT
# Keep the large UIKit/Core Data/Swift settings controller out of this Foundation
# test binary, but compile its production decision/removal helper verbatim.
python3 - "$migration_repo_dir" "$migration_test_dir/migration.m" <<'PY'
from pathlib import Path
import sys
repo = Path(sys.argv[1])
source = (repo / 'VoidLink/ViewControllers/SettingsViewController.m').read_text()
begin = '// SUNLIGHT_GLOBAL_QUALITY_MIGRATION_BEGIN'
end = '// SUNLIGHT_GLOBAL_QUALITY_MIGRATION_END'
assert source.count(begin) == source.count(end) == 1
helper = source.split(begin, 1)[1].split(end, 1)[0]
tests = (repo / 'tests/legacy_global_quality_migration_tests.m').read_text()
Path(sys.argv[2]).write_text('#import <Foundation/Foundation.h>\n' + helper + '\n' + tests)
PY
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    "$migration_test_dir/migration.m" -framework Foundation -o "$migration_test_dir/migration"
"$migration_test_dir/migration"
