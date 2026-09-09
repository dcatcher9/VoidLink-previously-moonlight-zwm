#import "ExternalDisplayCoordinator.h"
#import "Stream/StreamConfiguration.h"

// A new connection may use 3D only with confirmed SBS output. In particular,
// remembered preferences and a disconnected scene cannot enable conversion.
static inline SunlightStreamMode SunlightAllowedStreamMode(SunlightStreamMode requested,
                                                           BOOL glassesEnabled,
                                                           SunlightExternalDisplayMode displayMode) {
    if (!glassesEnabled || displayMode != SunlightExternalDisplayMode3D ||
        requested < SunlightStreamMode2D || requested > SunlightStreamModeRawHalfSBS) {
        return SunlightStreamMode2D;
    }
    return requested == SunlightStreamModeRawHalfSBS ? SunlightStreamModeRawFullSBS : requested;
}

// During an existing connection, unknown output is a transient state. Wait for
// a settled normal canvas and an established session before downgrading it.
static inline BOOL SunlightShouldReturnTo2D(SunlightStreamMode active,
                                           SunlightExternalDisplayMode displayMode,
                                           BOOL glassesEnabled,
                                           BOOL connectionReady,
                                           BOOL endingStream) {
    return active >= SunlightStreamModeHost3D && active <= SunlightStreamModeRawHalfSBS &&
        displayMode == SunlightExternalDisplayMode2D && glassesEnabled &&
        connectionReady && !endingStream;
}
