#import "FBDiskManagerTest.h"
#include <sys/stat.h>
#include <unistd.h>

@implementation FBDiskManagerTest

- (void)testGetDiskNames
{
  NSArray *diskNames = [FBDiskManager getDiskNames];

  UKNotNil(diskNames);
  UKTrue([diskNames isKindOfClass:[NSArray class]]);

  // Should have at least one disk on any system
  UKTrue([diskNames count] > 0);

  // Check that all entries are strings
  for (id diskName in diskNames) {
    UKTrue([diskName isKindOfClass:[NSString class]]);
    UKTrue([(NSString *)diskName length] > 0);
  }
}

- (void)testGetAllDiskInfo
{
  NSMutableDictionary *allDiskInfo = [FBDiskManager getAllDiskInfo];

  UKNotNil(allDiskInfo);
  UKTrue([allDiskInfo isKindOfClass:[NSMutableDictionary class]]);

  // Should have at least one disk
  UKTrue([allDiskInfo count] > 0);

  // Check structure of disk info
  for (NSString *diskName in allDiskInfo) {
    UKTrue([diskName isKindOfClass:[NSString class]]);

    NSDictionary *diskInfo = allDiskInfo[diskName];
    UKNotNil(diskInfo);
    UKTrue([diskInfo isKindOfClass:[NSDictionary class]]);

    // Check required keys
    UKNotNil(diskInfo[@"name"]);
    UKNotNil(diskInfo[@"path"]);
    UKNotNil(diskInfo[@"mediasize_bytes"]);
    UKNotNil(diskInfo[@"sectorsize_bytes"]);

    // Verify types
    UKTrue([diskInfo[@"name"] isKindOfClass:[NSString class]]);
    UKTrue([diskInfo[@"path"] isKindOfClass:[NSString class]]);
    UKTrue([diskInfo[@"mediasize_bytes"] isKindOfClass:[NSNumber class]]);
    UKTrue([diskInfo[@"sectorsize_bytes"] isKindOfClass:[NSNumber class]]);
  }
}

- (void)testGetDiskInfo
{
  NSArray *diskNames = [FBDiskManager getDiskNames];
  UKTrue([diskNames count] > 0);

  NSString *firstDisk = [diskNames firstObject];
  NSMutableDictionary *diskInfo = [FBDiskManager getDiskInfo:firstDisk];

  UKNotNil(diskInfo);
  UKTrue([diskInfo isKindOfClass:[NSMutableDictionary class]]);

  // Check that it contains expected keys
  UKNotNil(diskInfo[@"name"]);
  UKNotNil(diskInfo[@"path"]);
  UKNotNil(diskInfo[@"mediasize_bytes"]);
  UKNotNil(diskInfo[@"sectorsize_bytes"]);

  // Verify the name matches what we requested
  UKStringsEqual(diskInfo[@"name"], firstDisk);
}

- (void)testGetDiskInfoWithInvalidDisk
{
  NSMutableDictionary *diskInfo = [FBDiskManager getDiskInfo:@"nonexistent_disk"];
  UKNil(diskInfo);
}

- (void)testMountVolumeWithInvalidParameters
{
  NSError *error = nil;

  // Test with nil device path
  BOOL result = [FBDiskManager mountVolume:nil
                                mountPoint:@"/tmp/test"
                                filesystem:@"ufs"
                                     error:&error];
  UKFalse(result);
  UKNotNil(error);
  UKIntsEqual([error code], 1001);

  // Test with nil mount point
  error = nil;
  result = [FBDiskManager mountVolume:@"/dev/ada0p1" mountPoint:nil filesystem:@"ufs" error:&error];
  UKFalse(result);
  UKNotNil(error);
  UKIntsEqual([error code], 1001);

  // Test with nil filesystem
  error = nil;
  result = [FBDiskManager mountVolume:@"/dev/ada0p1"
                           mountPoint:@"/tmp/test"
                           filesystem:nil
                                error:&error];
  UKFalse(result);
  UKNotNil(error);
  UKIntsEqual([error code], 1001);
}

- (void)testUnmountVolumeWithInvalidParameters
{
  NSError *error = nil;

  // Test with nil mount point
  BOOL result = [FBDiskManager unmountVolume:nil error:&error];
  UKFalse(result);
  UKNotNil(error);
  UKIntsEqual([error code], 2001);

  // Test with non-existent mount point
  error = nil;
  result = [FBDiskManager unmountVolume:@"/nonexistent/mount/point" error:&error];
  UKFalse(result);
  UKNotNil(error);
  UKIntsEqual([error code], 2002);
}

- (void)testGetMountedVolumes
{
  NSArray *mountedVolumes = [FBDiskManager getMountedVolumes];

  UKNotNil(mountedVolumes);
  UKTrue([mountedVolumes isKindOfClass:[NSArray class]]);

  // Should have at least root filesystem mounted
  UKTrue([mountedVolumes count] > 0);

  // Check structure of mounted volume info
  for (NSDictionary *mountInfo in mountedVolumes) {
    UKTrue([mountInfo isKindOfClass:[NSDictionary class]]);

    // Check required keys
    UKNotNil(mountInfo[@"device"]);
    UKNotNil(mountInfo[@"mountpoint"]);
    UKNotNil(mountInfo[@"filesystem"]);
    UKNotNil(mountInfo[@"flags"]);

    // Verify types
    UKTrue([mountInfo[@"device"] isKindOfClass:[NSString class]]);
    UKTrue([mountInfo[@"mountpoint"] isKindOfClass:[NSString class]]);
    UKTrue([mountInfo[@"filesystem"] isKindOfClass:[NSString class]]);
    UKTrue([mountInfo[@"flags"] isKindOfClass:[NSNumber class]]);

    // Verify no ZFS filesystems are included
    UKFalse([mountInfo[@"filesystem"] isEqualToString:@"zfs"]);
  }
}

- (void)testIsMountedWithNilParameter
{
  BOOL result = [FBDiskManager isMounted:nil];
  UKFalse(result);
}

- (void)testMountUnmountFlow
{
  // This test requires a test device/image file
  // For now, we'll test the basic flow with error handling

  NSString *testMountPoint = [self createTemporaryMountPoint];
  UKNotNil(testMountPoint);

  // Try to mount a non-existent device (should fail)
  NSError *error = nil;
  BOOL result = [FBDiskManager mountVolume:@"/dev/nonexistent"
                                mountPoint:testMountPoint
                                filesystem:@"ufs"
                                     error:&error];
  UKFalse(result);
  UKNotNil(error);

  // Clean up
  [self cleanupTemporaryMountPoint:testMountPoint];
}

// Helper methods

- (NSString *)createTemporaryMountPoint
{
  NSString *tempDir = NSTemporaryDirectory();
  NSString *mountPoint = [tempDir stringByAppendingPathComponent:@"fbdiskmanager_test"];

  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSError *error = nil;

  if ([fileManager createDirectoryAtPath:mountPoint
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:&error]) {
    return mountPoint;
  }

  return nil;
}

- (void)cleanupTemporaryMountPoint:(NSString *)mountPoint
{
  if (mountPoint) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:mountPoint error:nil];
  }
}

- (NSString *)findTestDevice
{
  // This would find a suitable test device for mounting tests
  // For now, return nil to indicate no test device available
  return nil;
}

@end