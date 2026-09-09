#import "SunlightInputGate.h"

@implementation SunlightInputGate {
    NSUInteger _generation;
    BOOL _connected;
    BOOL _blocked;
    BOOL _invalidated;
}
- (NSUInteger)generation { @synchronized (self) { return _generation; } }
- (BOOL)isAllowed { @synchronized (self) { return _connected && !_blocked && !_invalidated; } }
- (void)setConnected:(BOOL)connected cancellation:(NS_NOESCAPE dispatch_block_t)cancellation {
    @synchronized (self) {
        if (_invalidated || _connected == connected) return;
        BOOL wasConnected = _connected;
        _connected = connected;
        _generation++;
        if (wasConnected) cancellation();
    }
}
- (void)setBlocked:(BOOL)blocked cancellation:(NS_NOESCAPE dispatch_block_t)cancellation {
    @synchronized (self) {
        if (_invalidated || _blocked == blocked) return;
        _blocked = blocked;
        _generation++;
        if (blocked && _connected) cancellation();
    }
}
- (void)cancelCurrentInput:(NS_NOESCAPE dispatch_block_t)cancellation {
    @synchronized (self) {
        if (_invalidated) return;
        _generation++;
        if (_connected && !_blocked) cancellation();
    }
}
- (void)invalidateWithCancellation:(NS_NOESCAPE dispatch_block_t)cancellation {
    @synchronized (self) {
        if (_invalidated) return;
        BOOL wasConnected = _connected;
        _invalidated = YES;
        _connected = NO;
        _generation++;
        if (wasConnected) cancellation();
    }
}
- (void)performForGeneration:(NSUInteger)generation action:(NS_NOESCAPE dispatch_block_t)action {
    @synchronized (self) {
        if (_connected && !_blocked && !_invalidated && generation == _generation) action();
    }
}
- (void)perform:(NS_NOESCAPE dispatch_block_t)action {
    @synchronized (self) {
        if (_connected && !_blocked && !_invalidated) action();
    }
}
@end
