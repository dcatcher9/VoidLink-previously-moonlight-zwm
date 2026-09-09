#pragma once
#include <stdbool.h>

// The renderer serializes access with its decoder/session lock. Keep recovery
// policy separate from VT resources so the real admission gate can be tested.
typedef struct {
    bool awaitingIDR;
    bool paused;
    bool requestSent;
    double lastRequestTime;
} SunlightDecoderRecovery;

static inline SunlightDecoderRecovery SunlightDecoderRecoveryInitial(void) {
    return (SunlightDecoderRecovery){ .awaitingIDR = true };
}

static inline void SunlightDecoderRecoveryInvalidate(SunlightDecoderRecovery *state) {
    if (!state->awaitingIDR) state->requestSent = false;
    state->awaitingIDR = true;
}

static inline void SunlightDecoderRecoverySetPaused(SunlightDecoderRecovery *state, bool paused) {
    if (state->paused == paused) return;
    state->paused = paused;
    state->awaitingIDR = true;
    state->requestSent = false;
}

static inline bool SunlightDecoderRecoveryCanDecode(const SunlightDecoderRecovery *state, bool isIDR) {
    return !state->paused && (!state->awaitingIDR || isIDR);
}

static inline bool SunlightDecoderRecoveryRequestIDR(SunlightDecoderRecovery *state, double now) {
    if (state->paused || !state->awaitingIDR) return false;
    if (state->requestSent && now >= state->lastRequestTime && now - state->lastRequestTime < 0.5) return false;
    state->requestSent = true;
    state->lastRequestTime = now;
    return true;
}

static inline void SunlightDecoderRecoveryDecodedIDR(SunlightDecoderRecovery *state) {
    if (state->paused) return;
    state->awaitingIDR = false;
    state->requestSent = false;
}
