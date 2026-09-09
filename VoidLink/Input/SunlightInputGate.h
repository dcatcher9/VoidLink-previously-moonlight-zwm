#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Serializes final host delivery with local UI transitions. Delayed work must
// retain its scheduling generation so closing a panel cannot revive old input.
@interface SunlightInputGate : NSObject
@property (nonatomic, readonly) NSUInteger generation;
@property (nonatomic, readonly, getter=isAllowed) BOOL allowed;
// Blocks execute synchronously while the gate holds its delivery lock.
- (void)setConnected:(BOOL)connected cancellation:(NS_NOESCAPE dispatch_block_t)cancellation;
- (void)setBlocked:(BOOL)blocked cancellation:(NS_NOESCAPE dispatch_block_t)cancellation;
- (void)cancelCurrentInput:(NS_NOESCAPE dispatch_block_t)cancellation;
- (void)invalidateWithCancellation:(NS_NOESCAPE dispatch_block_t)cancellation;
- (void)performForGeneration:(NSUInteger)generation action:(NS_NOESCAPE dispatch_block_t)action;
- (void)perform:(NS_NOESCAPE dispatch_block_t)action;
@end

NS_ASSUME_NONNULL_END
