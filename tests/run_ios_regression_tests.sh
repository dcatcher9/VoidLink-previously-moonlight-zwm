#!/bin/bash
set -euo pipefail
regression_repo="$(cd "$(dirname "$0")/.." && pwd)"
regression_mode="${1:-core}"
case "$regression_mode" in core|ui|all) ;; *) echo 'Usage: bash tests/run_ios_regression_tests.sh [core|ui|all]' >&2; exit 2;; esac
regression_logs="${SUNLIGHT_TEST_LOG_DIR:-$regression_repo/build/ios-regression-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$regression_logs"
regression_failed=0
run_suite() {
    local name="$1"
    if bash "$regression_repo/tests/run_${name}_tests.sh" > "$regression_logs/$name.log" 2>&1; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s (%s)\n' "$name" "$regression_logs/$name.log" >&2
        tail -20 "$regression_logs/$name.log" >&2
        regression_failed=1
    fi
}
if [[ "$regression_mode" != ui ]]; then
    for suite in crypto_pairing http_response discovery_address connection_lifecycle audio_playback_lifecycle video_stats_ownership \
        common_termination common_detached_thread stream_manager_lifecycle decoder_recovery frame_interpolator_queue \
        video_timestamp stereo_layout stream_configuration stream_quality_profile \
        stream_quality_session shared_settings machine_controls_settings flat_global_settings \
        legacy_global_quality_migration input_gate command_execution microphone_lifecycle \
        haptic_context controller_startup stream_controller_ownership; do
        run_suite "$suite"
    done
fi
if [[ "$regression_mode" != core ]]; then
    # Each runner creates and deletes its own simulator. Run sequentially to
    # avoid competing boot/build activity and keep evidence attributable.
    for suite in external_display settings_persistence startup_storage stream_controls control_pad relative_touch browser_ui; do
        run_suite "$suite"
    done
fi
printf 'Logs: %s\n' "$regression_logs"
exit "$regression_failed"
