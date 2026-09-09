#include "SunlightDecoderRecovery.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned cases;
static void require(bool condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void pass(const char *message) { cases++; printf("PASS %s\n", message); }

int main(void) {
    SunlightDecoderRecovery state = SunlightDecoderRecoveryInitial();
    require(!SunlightDecoderRecoveryCanDecode(&state, false), "empty decoder must reject inter frames");
    require(SunlightDecoderRecoveryCanDecode(&state, true), "first IDR must be admissible");
    require(state.awaitingIDR, "admitting an IDR must not mark it decoded");
    pass("new decoder waits for a successfully decoded IDR");

    SunlightDecoderRecoveryDecodedIDR(&state);
    require(SunlightDecoderRecoveryCanDecode(&state, false), "normal inter frames must continue after IDR");
    require(!SunlightDecoderRecoveryRequestIDR(&state, 1), "healthy stream must not request recovery");
    pass("ordinary foreground playback does not request recovery");

    SunlightDecoderRecoveryInvalidate(&state);
    unsigned admittedInterFrames = 0, requests = 0;
    for (unsigned frame = 0; frame < 120; frame++) {
        double now = frame / 120.0;
        admittedInterFrames += SunlightDecoderRecoveryCanDecode(&state, false);
        requests += SunlightDecoderRecoveryRequestIDR(&state, now);
    }
    require(admittedInterFrames == 0, "120 pending P frames must never reach a reset decoder");
    require(requests == 2, "120 pending P frames should request at most twice per second");
    require(SunlightDecoderRecoveryCanDecode(&state, true), "recovery IDR must bypass inter-frame gate");
    SunlightDecoderRecoveryDecodedIDR(&state);
    require(SunlightDecoderRecoveryCanDecode(&state, false), "good recovery IDR releases pending inter frames");
    pass("reset then P-frame burst waits for IDR without request storm");

    SunlightDecoderRecoveryInvalidate(&state);
    require(SunlightDecoderRecoveryRequestIDR(&state, 10), "first failure asks immediately");
    for (int repeat = 1; repeat < 50; repeat++) {
        SunlightDecoderRecoveryInvalidate(&state);
        require(!SunlightDecoderRecoveryRequestIDR(&state, 10 + repeat / 100.0),
                "repeated failed keyframes or resets must preserve request cooldown");
    }
    require(SunlightDecoderRecoveryRequestIDR(&state, 10.5), "missing/failed keyframe must retry after cooldown");
    pass("failed keyframes and repeated resets retain bounded retry");

    SunlightDecoderRecoveryDecodedIDR(&state);
    SunlightDecoderRecoverySetPaused(&state, true);
    for (int frame = 0; frame < 1000; frame++) {
        require(!SunlightDecoderRecoveryCanDecode(&state, frame % 30 == 0),
                "background without PiP rejects both inter frames and keyframes");
        require(!SunlightDecoderRecoveryRequestIDR(&state, 20 + frame),
                "background without PiP must not request IDR frames");
    }
    pass("non-PiP background does not decode, recreate, or request IDR");

    SunlightDecoderRecoverySetPaused(&state, false);
    require(!SunlightDecoderRecoveryCanDecode(&state, false), "resume must not accept a P frame into a reset decoder");
    require(SunlightDecoderRecoveryRequestIDR(&state, 1021), "resume must permit an immediate recovery request");
    require(!SunlightDecoderRecoveryRequestIDR(&state, 1021.01), "resume request must coalesce");
    require(SunlightDecoderRecoveryCanDecode(&state, true), "resume must admit a new IDR");
    SunlightDecoderRecoveryDecodedIDR(&state);
    pass("foreground resume requests one fresh IDR before inter frames");

    SunlightDecoderRecoverySetPaused(&state, false);
    require(SunlightDecoderRecoveryCanDecode(&state, false) && !state.awaitingIDR,
            "PiP's unpaused state must not invalidate healthy references");
    require(!SunlightDecoderRecoveryRequestIDR(&state, 2000), "PiP must not request recovery just for a background notification");
    pass("active PiP preserves healthy decode references");

    SunlightDecoderRecoverySetPaused(&state, true);
    SunlightDecoderRecoveryDecodedIDR(&state);
    require(state.awaitingIDR && !SunlightDecoderRecoveryCanDecode(&state, false),
            "a stale completion cannot reopen a paused decoder");
    SunlightDecoderRecoverySetPaused(&state, false);
    require(SunlightDecoderRecoveryRequestIDR(&state, 3000), "stale background completion cannot suppress foreground recovery");
    pass("completion while paused cannot release the recovery gate");

    require(SunlightDecoderRecoveryRequestIDR(&state, 2999), "clock reset must not permanently suppress recovery");
    require(!SunlightDecoderRecoveryRequestIDR(&state, 2999.1), "clock-reset request still coalesces");
    pass("request timer recovers from a clock rollback");
    printf("PASS: %u production decoder-recovery cases\n", cases);
    return 0;
}
