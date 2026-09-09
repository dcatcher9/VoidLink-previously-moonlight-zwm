#pragma once

#include <opus.h>

// Swift cannot call the variadic Opus configuration API directly. Keep this
// capture/encoder adapter in the client; common-C only transports encoded Opus.
static inline int opus_encoder_ctl_wrapper(OpusEncoder *encoder, int request, opus_int32 value) {
    return opus_encoder_ctl(encoder, request, value);
}
