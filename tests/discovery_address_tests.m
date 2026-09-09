#import <Foundation/Foundation.h>
@interface AddressHost : NSObject
@property NSString *localAddress, *address, *externalAddress, *ipv6Address;
// Production uses an unordered set. Deterministic iteration orders exercise both
// partitions, including orders that a set may choose after reconnect.
@property NSArray<NSString *> *activeAddressPool;
@end
@implementation AddressHost @end
@interface DiscoveryWorker : NSObject {
@public AddressHost *_host;
}
- (NSArray *)getHostAddressList;
@end
@implementation DiscoveryWorker
#include "discovery_address.inc"
@end
static unsigned checks;
static void Check(BOOL okay, NSString *message) { checks++; if (!okay) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
int main(void) { @autoreleasepool {
    DiscoveryWorker *worker = [DiscoveryWorker new]; worker->_host = [AddressHost new];
    worker->_host.localAddress = @"local"; worker->_host.address = @"manual";
    worker->_host.externalAddress = @"external"; worker->_host.ipv6Address = @"[::3]";
    for (NSArray *pool in @[@[@"[::1]", @"cached", @"[::2]", @"local"], @[@"cached", @"[::1]", @"local", @"[::2]"]]) {
        worker->_host.activeAddressPool = pool;
        NSArray *addresses = [worker getHostAddressList];
        Check([addresses isEqual:@[@"local", @"cached", @"[::1]", @"[::2]", @"manual", @"external", @"[::3]"]],
              @"Mixed cache order preserves every endpoint, family priority and first-occurrence deduplication");
        Check([worker->_host.activeAddressPool isEqual:pool], @"Address collection never mutates its cache snapshot");
    }
    worker->_host = [AddressHost new];
    Check([worker getHostAddressList].count == 0, @"Missing optional addresses yield an empty list");
    worker->_host.activeAddressPool = @[@"cached:47989", @"plain", @"[::1]:47989"];
    Check([[worker getHostAddressList] isEqual:@[@"plain", @"cached:47989", @"[::1]:47989"]], @"Explicit-port endpoints remain discoverable");
    printf("Discovery addresses: %u checks passed\n", checks);
} return 0; }
