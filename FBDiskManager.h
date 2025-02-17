#import <Foundation/Foundation.h>

@interface FBDiskManager : NSObject
+ (NSArray *)getDiskNames;
+ (NSMutableDictionary *)getAllDiskInfo;
+ (NSMutableDictionary *)getDiskInfo:(NSString *)diskName;
@end

