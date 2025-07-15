#import "FBDiskManager.h"
#include <libgeom.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>


@implementation FBDiskManager

+ (NSArray *)getDiskNames
{
  size_t size;
  sysctlbyname("kern.disks", NULL, &size, NULL, 0);

  char *buffer = malloc(size);
  if (!buffer)
    return nil;

  sysctlbyname("kern.disks", buffer, &size, NULL, 0);
  NSString *disksString = [NSString stringWithUTF8String:buffer];
  free(buffer);

  NSArray *disksArray = [disksString componentsSeparatedByString:@" "];
  return disksArray;
}

+ (NSMutableDictionary *)getAllDiskInfo
{
  struct gmesh mesh;
  struct gclass *classPtr;
  struct ggeom *geomPtr;
  struct gprovider *providerPtr;

  NSMutableDictionary *disksDictionary = [NSMutableDictionary dictionary];

  // Initialize libgeom and fetch the disk tree
  if (geom_gettree(&mesh) != 0) {
    NSLog(@"Error: Failed to get GEOM tree.");
    return nil;
  }

  // Iterate through all GEOM classes
  LIST_FOREACH(classPtr, &mesh.lg_class, lg_class)
  {
    // Only process the "DISK" class
    if (strcmp(classPtr->lg_name, "DISK") != 0) {
      continue;
    }

    // Iterate through each geom in the DISK class
    LIST_FOREACH(geomPtr, &classPtr->lg_geom, lg_geom)
    {
      LIST_FOREACH(providerPtr, &geomPtr->lg_provider, lg_provider)
      {
        NSString *diskName = [NSString stringWithFormat:@"%s", providerPtr->lg_name];
        NSString *diskPath = [NSString stringWithFormat:@"/dev/%s", providerPtr->lg_name];

        // Search for "descr" in the geom's config list
        const char *descrCStr = NULL;
        struct gconfig *configPtr;
        LIST_FOREACH(configPtr, &geomPtr->lg_config, lg_config) {
          if (strcmp(configPtr->lg_name, "descr") == 0) {
            descrCStr = configPtr->lg_val;
            break;
          }
        }
        NSString *descr = descrCStr ? [NSString stringWithUTF8String:descrCStr] : @"";

        // Store disk attributes in dictionary
        NSDictionary *diskInfo = @{
          @"name" : diskName,
          @"path" : diskPath,
          @"mediasize_bytes" : @(providerPtr->lg_mediasize),
          @"sectorsize_bytes" : @(providerPtr->lg_sectorsize),
          @"stripe_size" : @(providerPtr->lg_stripesize),
          @"stripe_offset" : @(providerPtr->lg_stripeoffset),
          @"mode" : @(providerPtr->lg_mode),
          @"description" : descr
        };

        // Add entry with disk name as the key
        disksDictionary[diskName] = diskInfo;
      }
    }
  }

  // Free memory allocated by libgeom
  geom_deletetree(&mesh);

  return disksDictionary;
}

+ (NSMutableDictionary *)getDiskInfo:(NSString *)diskName
{
  NSDictionary *allDisks = [self getAllDiskInfo];
  if (!allDisks) {
    return nil; // Handle case where no disk info is available
  }

  NSDictionary *diskInfo = allDisks[diskName];
  if (diskInfo) {
    return [diskInfo mutableCopy];
  }
  else {
    NSLog(@"Disk %@ not found", diskName);
    return nil;
  }
}

+ (BOOL)mountVolume:(NSString *)devicePath
         mountPoint:(NSString *)mountPoint
         filesystem:(NSString *)filesystem
              error:(NSError **)error
{
  if (!devicePath || !mountPoint || !filesystem) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                              code:1001
                          userInfo:@{ NSLocalizedDescriptionKey : @"Invalid parameters provided" }];
    }
    return NO;
  }

  // Check if device is ZFS before attempting mount
  NSError *zfsError = nil;
  if ([self isZFSDevice:devicePath error:&zfsError]) {
    if (error) {
      *error = [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                                   code:1005
                               userInfo:@{ NSLocalizedDescriptionKey : @"The disk is part of a ZFS pool. Please mount with ZFS command." }];
    }
    return NO;
  }

  // Check if mount point exists, create if it doesn't
  NSFileManager *fileManager = [NSFileManager defaultManager];
  if (![fileManager fileExistsAtPath:mountPoint]) {
    NSError *createError = nil;
    if (![fileManager createDirectoryAtPath:mountPoint
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&createError]) {
      if (error) {
        *error = [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                                     code:1002
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Failed to create mount point",
                                   NSUnderlyingErrorKey : createError
                                 }];
      }
      return NO;
    }
  }

  // Construct mount command
  NSString *mountCommand =
      [NSString stringWithFormat:@"mount -t %@ %@ %@", filesystem, devicePath, mountPoint];

  // Execute mount command
  FILE *pipe = popen([mountCommand UTF8String], "r");
  if (!pipe) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"FBDiskManagerErrorDomain"
                     code:1003
                 userInfo:@{ NSLocalizedDescriptionKey : @"Failed to execute mount command" }];
    }
    return NO;
  }

  int result = pclose(pipe);
  if (result != 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"FBDiskManagerErrorDomain"
                     code:1004
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Mount command failed with exit code %d", result]
                 }];
    }
    return NO;
  }

  return YES;
}

+ (BOOL)unmountVolume:(NSString *)mountPoint error:(NSError **)error
{
  if (!mountPoint) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"FBDiskManagerErrorDomain"
                     code:2001
                 userInfo:@{ NSLocalizedDescriptionKey : @"Invalid mount point provided" }];
    }
    return NO;
  }

  // Check if the mounted device is ZFS before attempting unmount
  NSArray *mountedVolumes = [self getMountedVolumes];
  for (NSDictionary *mount in mountedVolumes) {
    NSString *currentMountPoint = mount[@"mountpoint"];
    if ([currentMountPoint isEqualToString:mountPoint]) {
      NSString *devicePath = mount[@"device"];
      NSError *zfsError = nil;
      if ([self isZFSDevice:devicePath error:&zfsError]) {
        if (error) {
          *error = [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                                       code:2005
                                   userInfo:@{ NSLocalizedDescriptionKey : @"The disk is part of a ZFS pool. Please unmount with ZFS command." }];
        }
        return NO;
      }
      break;
    }
  }

  // Check if the mount point is actually mounted
  if (![self isMounted:mountPoint]) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                              code:2002
                          userInfo:@{ NSLocalizedDescriptionKey : @"Mount point is not mounted" }];
    }
    return NO;
  }

  // Construct unmount command
  NSString *unmountCommand = [NSString stringWithFormat:@"umount %@", mountPoint];

  // Execute unmount command
  FILE *pipe = popen([unmountCommand UTF8String], "r");
  if (!pipe) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"FBDiskManagerErrorDomain"
                     code:2003
                 userInfo:@{ NSLocalizedDescriptionKey : @"Failed to execute unmount command" }];
    }
    return NO;
  }

  int result = pclose(pipe);
  if (result != 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"FBDiskManagerErrorDomain"
                     code:2004
                 userInfo:@{
                   NSLocalizedDescriptionKey : [NSString
                       stringWithFormat:@"Unmount command failed with exit code %d", result]
                 }];
    }
    return NO;
  }

  return YES;
}

+ (NSArray *)getMountedVolumes
{
  NSMutableArray *mountedVolumes = [NSMutableArray array];

  // Use getmntinfo() to get mounted filesystems
  struct statfs *mounts;
  int count = getmntinfo(&mounts, MNT_NOWAIT);

  if (count < 0) {
    NSLog(@"Error: Failed to get mount information");
    return nil;
  }

  for (int i = 0; i < count; i++) {
    // Skip ZFS filesystems as requested
    if (strcmp(mounts[i].f_fstypename, "zfs") == 0) {
      continue;
    }

    NSDictionary *mountInfo = @{
      @"device" : [NSString stringWithUTF8String:mounts[i].f_mntfromname],
      @"mountpoint" : [NSString stringWithUTF8String:mounts[i].f_mntonname],
      @"filesystem" : [NSString stringWithUTF8String:mounts[i].f_fstypename],
      @"flags" : @(mounts[i].f_flags)
    };

    [mountedVolumes addObject:mountInfo];
  }

  return [mountedVolumes copy];
}

+ (BOOL)isMounted:(NSString *)devicePath
{
  if (!devicePath) {
    return NO;
  }

  NSArray *mountedVolumes = [self getMountedVolumes];
  for (NSDictionary *mount in mountedVolumes) {
    NSString *mountedDevice = mount[@"device"];
    NSString *mountPoint = mount[@"mountpoint"];

    // Check if the device matches or if the devicePath is actually a mount point
    if ([mountedDevice isEqualToString:devicePath] || [mountPoint isEqualToString:devicePath]) {
      return YES;
    }
  }

  return NO;
}

+ (BOOL)isZFSDevice:(NSString *)devicePath error:(NSError **)error
{
  if (!devicePath) {
    if (error) {
      *error = [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                                   code:3001
                               userInfo:@{ NSLocalizedDescriptionKey : @"Invalid device path provided" }];
    }
    return NO;
  }

  // Method 1: Check using gpart show for ZFS partition type
  NSString *gpartCommand = [NSString stringWithFormat:@"gpart show %@", devicePath];
  FILE *pipe = popen([gpartCommand UTF8String], "r");
  if (pipe) {
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe)) {
      NSString *line = [NSString stringWithUTF8String:buffer];
      if ([line containsString:@"freebsd-zfs"] || [line containsString:@"516e7cba-6ecf-11d6-8ff8-00022d09712b"]) {
        pclose(pipe);
        return YES;
      }
    }
    pclose(pipe);
  }

  // Method 2: Check if device is listed in any ZFS pool
  NSString *zpoolCommand = @"zpool status -v";
  pipe = popen([zpoolCommand UTF8String], "r");
  if (pipe) {
    char buffer[256];
    NSString *deviceName = [devicePath lastPathComponent];
    while (fgets(buffer, sizeof(buffer), pipe)) {
      NSString *line = [NSString stringWithUTF8String:buffer];
      if ([line containsString:deviceName] && ![line containsString:@"pool:"]) {
        pclose(pipe);
        return YES;
      }
    }
    pclose(pipe);
  }

  return NO;
}

+ (NSString *)detectFilesystem:(NSString *)devicePath
{
  if (!devicePath) {
    return nil;
  }

  // First try fstyp for more accurate FreeBSD detection
  NSString *fstypCommand = [NSString stringWithFormat:@"fstyp %@", devicePath];
  FILE *pipe = popen([fstypCommand UTF8String], "r");
  if (pipe) {
    char buffer[256];
    if (fgets(buffer, sizeof(buffer), pipe)) {
      NSString *fstype = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      pclose(pipe);
      if (fstype && ![fstype isEqualToString:@""]) {
        return fstype;
      }
    } else {
      pclose(pipe);
    }
  }

  // Fallback to file command for broader detection
  NSString *fileCommand = [NSString stringWithFormat:@"file -s %@", devicePath];
  pipe = popen([fileCommand UTF8String], "r");
  if (!pipe) {
    return nil;
  }

  char buffer[512];
  NSString *result = nil;
  if (fgets(buffer, sizeof(buffer), pipe)) {
    NSString *output = [NSString stringWithUTF8String:buffer];
    
    if ([output containsString:@"Unix Fast File system"]) {
      result = @"ufs";
    } else if ([output containsString:@"DOS/MBR boot sector"] || [output containsString:@"FAT"]) {
      result = @"msdosfs";
    } else if ([output containsString:@"ext2"] || [output containsString:@"ext3"] || [output containsString:@"ext4"]) {
      result = @"ext2fs";
    } else if ([output containsString:@"NTFS"]) {
      result = @"ntfs";
    } else if ([output containsString:@"ISO 9660"] || [output containsString:@"CD-ROM"]) {
      result = @"cd9660";
    } else {
      result = @"unknown";
    }
  }
  
  pclose(pipe);
  return result;
}

@end
