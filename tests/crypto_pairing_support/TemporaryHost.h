#import <Foundation/Foundation.h>
@interface TemporaryHost : NSObject
@property NSString *activeAddress;
@property unsigned short httpsPort;
@property NSData *serverCert;
@end
