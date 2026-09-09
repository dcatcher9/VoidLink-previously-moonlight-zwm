#import <Foundation/Foundation.h>
@interface Utils : NSObject
+ (NSData *)randomBytes:(NSUInteger)length;
+ (NSString *)bytesToHex:(NSData *)data;
+ (NSString *)addressPortStringToAddress:(NSString *)address;
+ (unsigned short)addressPortStringToPort:(NSString *)address;
@end
