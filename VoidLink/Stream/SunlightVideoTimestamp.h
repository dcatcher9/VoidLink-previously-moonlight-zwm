#pragma once

#include <CoreMedia/CoreMedia.h>
#include <Limelight.h>
#include <limits.h>

// Owned by one renderer's sequential decode consumer. The shared core exposes
// milliseconds, obtained by dividing the 32-bit RTP clock by 90. That clock
// wraps after about 13.26 hours; it is not a 32-bit millisecond clock.
typedef struct {
    bool initialized;
    uint32_t previousTicks;
    int64_t presentationTicks;
} SunlightVideoTimestamp;

static inline CMTime SunlightVideoPresentationTime(SunlightVideoTimestamp *clock,
                                                  const DECODE_UNIT *decodeUnit) {
    // Keep Frame's existing 90 kHz time scale without inventing sub-ms source
    // precision. The wider multiplication also accepts the core's synthesized
    // elapsed-ms timestamps when a host does not send a usable RTP timestamp.
    const int64_t ticks = (int64_t)decodeUnit->presentationTimeMs * 90;
    const uint32_t currentTicks = (uint32_t)ticks;
    if (!clock->initialized) {
        clock->initialized = true;
        clock->presentationTicks = ticks;
    }
    else {
        // Choose the nearest RTP epoch. This requires successive delivered
        // timestamps to be less than half a clock cycle apart (~6.63 hours).
        // Small regressions and duplicate PTS retain their source meaning; a
        // backward timestamp alone must not add a complete rollover period.
        int64_t delta = (uint32_t)(currentTicks - clock->previousTicks);
        if (delta > INT32_MAX) delta -= (INT64_C(1) << 32);
        clock->presentationTicks += delta;
    }
    clock->previousTicks = currentTicks;
    return CMTimeMake(clock->presentationTicks, 90000);
}
