#import "../FBDiskManager.h"
#import <Foundation/Foundation.h>
#import <UnitKit/UnitKit.h>

@interface FBDiskManagerTest : NSObject <UKTest>

// Test methods for existing functionality
- (void)testGetDiskNames;
- (void)testGetAllDiskInfo;
- (void)testGetDiskInfo;
- (void)testGetDiskInfoWithInvalidDisk;

// Test methods for new mount/unmount functionality
- (void)testMountVolumeWithInvalidParameters;
- (void)testUnmountVolumeWithInvalidParameters;
- (void)testGetMountedVolumes;
- (void)testIsMountedWithNilParameter;

// Helper methods
- (NSString *)createTemporaryMountPoint;
- (void)cleanupTemporaryMountPoint:(NSString *)mountPoint;
- (NSString *)findTestDevice;
- (NSString *)findZFSDevice;
- (NSString *)findNonZFSDevice;

@end