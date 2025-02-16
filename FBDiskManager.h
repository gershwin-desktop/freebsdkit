#import <Foundation/Foundation.h>

@interface FBDiskManager : NSObject
+ (NSArray *)getDisks;
+ (NSMutableDictionary *)getAllDiskInfo;
@end

