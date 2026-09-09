#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// moonlight-common owns process-wide C state. A lifecycle keeps that state
// assigned to one Connection until its stop and decoder cleanup have finished.
@interface ConnectionLifecycle : NSObject
@property (nonatomic, readonly) uint64_t sessionToken;
- (instancetype)initWithCleanup:(dispatch_block_t)cleanup interrupt:(dispatch_block_t)interrupt;
- (void)runWithContext:(id)context
              prepare:(dispatch_block_t)prepare
                start:(int (^)(void))start
                 stop:(dispatch_block_t)stop
             teardown:(dispatch_block_t)teardown;
- (void)cancel;
// Cancels without blocking its caller. Each completion runs asynchronously on
// a worker queue after C stop, decoder cleanup and ownership teardown finish.
- (void)cancelWithCompletion:(dispatch_block_t)completion;
- (BOOL)isCurrentOwner;
// Run a short external callback only while this session is active. The block
// must not call lifecycle methods; ownership cannot change during the block.
- (void)performIfCurrentOwner:(dispatch_block_t)action;
+ (nullable id)activeContext;
// Capture an instance-owned notification sink once, while its token still owns
// the session. The short capture block must not call lifecycle methods. Deliver
// outside this block so notification code may cancel its Connection safely.
+ (BOOL)claimTerminationForSessionToken:(uint64_t)token capture:(void (^)(id context))capture;
// The first C stage callback follows the C interrupt-flag reset. Reasserting
// here closes cancellation between the caller's final check and that reset.
+ (BOOL)reassertActiveCancellation;
+ (void)cleanupActiveDecoder;
@end

NS_ASSUME_NONNULL_END
