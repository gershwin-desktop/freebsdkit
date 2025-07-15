#import <Foundation/Foundation.h>

@interface FBDiskManager : NSObject
+ (NSArray *)getDiskNames;
+ (NSMutableDictionary *)getAllDiskInfo;
+ (NSMutableDictionary *)getDiskInfo:(NSString *)diskName;

// Mount and unmount methods for non-ZFS volumes
+ (BOOL)mountVolume:(NSString *)devicePath
         mountPoint:(NSString *)mountPoint
         filesystem:(NSString *)filesystem
              error:(NSError **)error;
+ (BOOL)unmountVolume:(NSString *)mountPoint error:(NSError **)error;
+ (NSArray *)getMountedVolumes;
+ (BOOL)isMounted:(NSString *)devicePath;

// ZFS detection methods
+ (BOOL)isZFSDevice:(NSString *)devicePath error:(NSError **)error;
+ (NSString *)detectFilesystem:(NSString *)devicePath;

// Volume name detection methods
+ (NSString *)getVolumeLabel:(NSString *)devicePath;
+ (NSString *)sanitizeVolumeName:(NSString *)volumeName;

// ZFS pool information methods
+ (NSString *)getZFSPoolName:(NSString *)devicePath;
+ (NSDictionary *)getZFSPoolSummary:(NSString *)poolName;
@end
