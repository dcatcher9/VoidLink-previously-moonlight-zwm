#include "SunlightVideoTimestamp.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;

static void Require(bool condition, const char *message) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static CMTime Present(SunlightVideoTimestamp *clock, uint32_t milliseconds) {
    DECODE_UNIT unit = {0};
    unit.presentationTimeMs = milliseconds;
    return SunlightVideoPresentationTime(clock, &unit);
}

int main(void) {
    SunlightVideoTimestamp clock = {0};
    CMTime first = Present(&clock, 0);
    Require(CMTIME_IS_VALID(first) && first.value == 0 && first.timescale == 90000,
            "zero is a valid first presentation timestamp");
    CMTime next = Present(&clock, 16);
    Require(next.value == 1440 && CMTimeCompare(CMTimeSubtract(next, first), CMTimeMake(16, 1000)) == 0,
            "normal frames preserve source millisecond spacing on Frame's 90k clock");

    clock = (SunlightVideoTimestamp){0};
    Require(Present(&clock, 123456).value == INT64_C(123456) * 90,
            "a nonzero starting epoch is retained");

    // Millisecond PTS quantizes 60/90/120 FPS cadence; do not synthesize an
    // idealized frame duration or progressively round each interval.
    const unsigned rates[] = {60, 90, 120};
    for (unsigned rateIndex = 0; rateIndex < sizeof(rates) / sizeof(rates[0]); rateIndex++) {
        clock = (SunlightVideoTimestamp){0};
        const unsigned rate = rates[rateIndex];
        bool validCadence = true;
        for (unsigned frame = 0; frame <= rate * 30; frame++) {
            const uint32_t sourceMs = frame * 1000 / rate;
            const CMTime pts = Present(&clock, sourceMs);
            validCadence &= pts.value == (int64_t)sourceMs * 90;
        }
        Require(validCadence, "fractional frame cadence retains each published PTS without drift");
    }

    // Reproduce the actual shared-core conversion: uint32 RTP / 90, including
    // the fractional final millisecond that a 2^32-tick wrap introduces.
    clock = (SunlightVideoTimestamp){0};
    const uint64_t rtpCycle = UINT64_C(1) << 32;
    uint64_t extendedTicks = rtpCycle - 3000;
    first = Present(&clock, (uint32_t)extendedTicks / 90);
    bool validRollover = true;
    for (unsigned frame = 1; frame < 1200; frame++) {
        extendedTicks += 750; // 120 FPS around rollover
        const uint32_t wireTicks = (uint32_t)extendedTicks;
        next = Present(&clock, wireTicks / 90);
        const int64_t precisionLoss = (int64_t)extendedTicks - next.value;
        validRollover &= next.value > first.value && precisionLoss >= 0 && precisionLoss < 90;
        first = next;
    }
    Require(validRollover, "RTP rollover stays increasing with less than one millisecond precision loss");

    clock = (SunlightVideoTimestamp){0};
    extendedTicks = 0;
    bool validRepeatedWraps = true;
    for (unsigned step = 0; step < 24; step++) {
        const uint32_t wireTicks = (uint32_t)extendedTicks;
        next = Present(&clock, wireTicks / 90);
        validRepeatedWraps &= next.value == (int64_t)(extendedTicks - wireTicks % 90);
        extendedTicks += rtpCycle / 4;
    }
    Require(validRepeatedWraps, "successive RTP epochs do not accumulate rounding drift");

    clock = (SunlightVideoTimestamp){0};
    const uint32_t beforeSyntheticWrap = UINT32_MAX - 9;
    first = Present(&clock, beforeSyntheticWrap);
    next = Present(&clock, 10);
    Require(CMTimeCompare(CMTimeSubtract(next, first), CMTimeMake(20, 1000)) == 0,
            "the core's synthesized uint32 elapsed-ms rollover also stays continuous");

    clock = (SunlightVideoTimestamp){0};
    first = Present(&clock, 10000);
    next = Present(&clock, 9900);
    Require(CMTimeCompare(CMTimeSubtract(next, first), CMTimeMake(-100, 1000)) == 0,
            "a timestamp regression must not be mistaken for a whole clock rollover");
    Require(Present(&clock, 9900).value == next.value, "duplicate PTS remains a duplicate");
    Require(Present(&clock, 10100).value == 909000,
            "a valid timestamp after a regression returns to the same epoch");

    clock = (SunlightVideoTimestamp){0};
    first = Present(&clock, 1000);
    next = Present(&clock, 301000);
    Require(CMTimeCompare(CMTimeSubtract(next, first), CMTimeMake(300, 1)) == 0,
            "a real delivery gap retains source elapsed time rather than one frame duration");

    clock = (SunlightVideoTimestamp){0};
    DECODE_UNIT unit = {0};
    unit.presentationTimeMs = 125;
    unit.receiveTimeMs = UINT64_C(9000000000);
    unit.enqueueTimeMs = unit.receiveTimeMs + 400;
    Require(SunlightVideoPresentationTime(&clock, &unit).value == 11250,
            "receiver clock and packet assembly delay must not change presentation time");

    SunlightVideoTimestamp successor = {0};
    Require(Present(&successor, 0).value == 0 && Present(&clock, 126).value == 11340,
            "renderer sessions have independent epochs");
    clock = (SunlightVideoTimestamp){0};
    Require(Present(&clock, 0).value == 0, "explicit new-session reset removes previous clock history");

    printf("PASS: %u production video-timestamp checks\n", checks);
    return 0;
}
