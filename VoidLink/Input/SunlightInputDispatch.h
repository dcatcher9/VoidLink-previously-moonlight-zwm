#import "StreamView.h"

// These helpers guard the actual send, and retain the generation at scheduling
// time for delayed touch work. They do not change the underlying protocol.
static inline int SunlightHostInput(StreamView *view, int (^action)(void)) {
    __block int result = -1;
    [view performHostInput:^{ result = action(); }];
    return result;
}
static inline void SunlightDispatchHostInput(StreamView *view, dispatch_queue_t queue,
                                            dispatch_block_t action) {
    NSUInteger generation = view.hostInputGeneration;
    dispatch_async(queue, ^{ [view performHostInputForGeneration:generation action:action]; });
}
static inline void SunlightDispatchHostInputAfter(StreamView *view, dispatch_time_t when,
                                                 dispatch_queue_t queue, dispatch_block_t action) {
    NSUInteger generation = view.hostInputGeneration;
    dispatch_after(when, queue, ^{ [view performHostInputForGeneration:generation action:action]; });
}
