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

        // Search for description in provider config first, then geom config
        const char *descrCStr = NULL;
        struct gconfig *configPtr;
        
        // Try provider config first
        LIST_FOREACH(configPtr, &providerPtr->lg_config, lg_config) {
          if (strcmp(configPtr->lg_name, "descr") == 0 || 
              strcmp(configPtr->lg_name, "desc") == 0 ||
              strcmp(configPtr->lg_name, "description") == 0) {
            descrCStr = configPtr->lg_val;
            break;
          }
        }
        
        // Fallback to geom config if not found in provider
        if (!descrCStr) {
          LIST_FOREACH(configPtr, &geomPtr->lg_config, lg_config) {
            if (strcmp(configPtr->lg_name, "descr") == 0 || 
                strcmp(configPtr->lg_name, "desc") == 0 ||
                strcmp(configPtr->lg_name, "description") == 0) {
              descrCStr = configPtr->lg_val;
              break;
            }
          }
        }
        
        NSString *descr = descrCStr ? [NSString stringWithUTF8String:descrCStr] : @"";

        // Detect filesystem for this disk
        NSString *filesystem = [self detectFilesystem:diskPath];
        
        // Check if it's a ZFS device and override filesystem if needed
        NSError *zfsError = nil;
        if ([self isZFSDevice:diskPath error:&zfsError]) {
          filesystem = @"zfs";
        }
        
        // Store disk attributes in dictionary
        NSDictionary *diskInfo = @{
          @"name" : diskName,
          @"path" : diskPath,
          @"mediasize_bytes" : @(providerPtr->lg_mediasize),
          @"sectorsize_bytes" : @(providerPtr->lg_sectorsize),
          @"stripe_size" : @(providerPtr->lg_stripesize),
          @"stripe_offset" : @(providerPtr->lg_stripeoffset),
          @"mode" : @(providerPtr->lg_mode),
          @"description" : descr,
          @"filesystem" : filesystem ?: @"unknown"
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
    NSMutableDictionary *mutableDiskInfo = [diskInfo mutableCopy];
    
    // Add filesystem information
    NSString *devicePath = diskInfo[@"path"];
    NSString *filesystem = [self detectFilesystem:devicePath];
    
    // Add ZFS information if device is ZFS
    NSError *zfsError = nil;
    if ([self isZFSDevice:devicePath error:&zfsError]) {
      // If we detect ZFS, override filesystem to "zfs"
      filesystem = @"zfs";
      
      NSString *poolName = [self getZFSPoolName:devicePath];
      if (poolName) {
        mutableDiskInfo[@"zfs_pool"] = poolName;
        
        NSDictionary *poolSummary = [self getZFSPoolSummary:poolName];
        if (poolSummary) {
          mutableDiskInfo[@"zfs_status"] = poolSummary[@"status"] ?: @"UNKNOWN";
          mutableDiskInfo[@"zfs_datasets_total"] = poolSummary[@"total_datasets"] ?: @(0);
          mutableDiskInfo[@"zfs_encrypted_datasets"] = poolSummary[@"encrypted_datasets"] ?: @(0);
        }
      }
    }
    
    // Set filesystem information
    if (filesystem) {
      mutableDiskInfo[@"filesystem"] = filesystem;
    }
    
    return mutableDiskInfo;
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
      NSString *poolName = [self getZFSPoolName:devicePath];
      NSString *errorMessage;
      
      if (poolName) {
        errorMessage = [NSString stringWithFormat:@"Device %@ is part of ZFS pool '%@'. Use: zpool import %@ && zfs mount <dataset>", devicePath, poolName, poolName];
      } else {
        errorMessage = [NSString stringWithFormat:@"Device %@ is part of a ZFS pool. Please mount with ZFS command.", devicePath];
      }
      
      *error = [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                                   code:1005
                               userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
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
          NSString *poolName = [self getZFSPoolName:devicePath];
          NSString *errorMessage;
          
          if (poolName) {
            errorMessage = [NSString stringWithFormat:@"Cannot unmount ZFS dataset from pool '%@'. Use: zfs unmount <dataset>", poolName];
          } else {
            errorMessage = @"Cannot unmount ZFS dataset. Use: zfs unmount <dataset>";
          }
          
          *error = [NSError errorWithDomain:@"FBDiskManagerErrorDomain"
                                       code:2005
                                   userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
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

  NSString *deviceName = [devicePath lastPathComponent];

  // Method 1: Check using gpart show for ZFS partition type on the disk
  NSString *gpartCommand = [NSString stringWithFormat:@"gpart show %@", deviceName];
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

  // Method 2: Check if device or any of its partitions are listed in ZFS pools
  NSString *zpoolCommand = @"zpool status -v";
  pipe = popen([zpoolCommand UTF8String], "r");
  if (pipe) {
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe)) {
      NSString *line = [NSString stringWithUTF8String:buffer];
      
      // Skip pool header lines
      if ([line containsString:@"pool:"] || [line containsString:@"state:"] || [line containsString:@"config:"]) {
        continue;
      }
      
      // Check if line contains the device name or any partition of it
      NSArray *lineComponents = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      for (NSString *component in lineComponents) {
        component = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Check exact match (for partition like ada0p4)
        if ([component isEqualToString:deviceName]) {
          pclose(pipe);
          return YES;
        }
        
        // Check if this is a partition of our device (ada0p4 contains ada0)
        if ([component hasPrefix:deviceName] && [component length] > [deviceName length]) {
          char nextChar = [component characterAtIndex:[deviceName length]];
          if (nextChar == 'p' || nextChar == 's') { // Common partition prefixes
            pclose(pipe);
            return YES;
          }
        }
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

  // First, check if the device is already mounted and get filesystem from mount table
  NSArray *mountedVolumes = [self getMountedVolumes];
  for (NSDictionary *mount in mountedVolumes) {
    NSString *mountedDevice = mount[@"device"];
    if ([mountedDevice isEqualToString:devicePath]) {
      return mount[@"filesystem"];
    }
  }

  // Try fstyp for more accurate FreeBSD detection (may fail without root)
  NSString *fstypCommand = [NSString stringWithFormat:@"fstyp %@ 2>/dev/null", devicePath];
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

  // Fallback to file command for broader detection (may also fail without root)
  NSString *fileCommand = [NSString stringWithFormat:@"file -s %@ 2>/dev/null", devicePath];
  pipe = popen([fileCommand UTF8String], "r");
  if (pipe) {
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
    if (result && ![result isEqualToString:@"unknown"]) {
      return result;
    }
  }
  
  // If all else fails, return unknown
  return @"unknown";
}

+ (NSString *)getVolumeLabel:(NSString *)devicePath
{
  if (!devicePath) {
    return nil;
  }

  // First detect the filesystem type
  NSString *filesystem = [self detectFilesystem:devicePath];
  if (!filesystem) {
    return nil;
  }

  NSString *volumeLabel = nil;
  
  // Try filesystem-specific volume label detection
  if ([filesystem isEqualToString:@"ufs"]) {
    // UFS: Use tunefs to get volume label
    NSString *tunefsCommand = [NSString stringWithFormat:@"tunefs -p %@ 2>/dev/null", devicePath];
    FILE *pipe = popen([tunefsCommand UTF8String], "r");
    if (pipe) {
      char buffer[512];
      while (fgets(buffer, sizeof(buffer), pipe)) {
        NSString *line = [NSString stringWithUTF8String:buffer];
        if ([line containsString:@"volume name"]) {
          // Extract volume name from line like "volume name: MyVolume"
          NSRange range = [line rangeOfString:@"volume name:"];
          if (range.location != NSNotFound) {
            volumeLabel = [[line substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          }
          break;
        }
      }
      pclose(pipe);
    }
  } else if ([filesystem isEqualToString:@"msdosfs"]) {
    // FAT32: Use file command to get volume label
    NSString *fileCommand = [NSString stringWithFormat:@"file -s %@", devicePath];
    FILE *pipe = popen([fileCommand UTF8String], "r");
    if (pipe) {
      char buffer[512];
      if (fgets(buffer, sizeof(buffer), pipe)) {
        NSString *output = [NSString stringWithUTF8String:buffer];
        // Look for volume label in file output
        NSRange labelRange = [output rangeOfString:@"label \""];
        if (labelRange.location != NSNotFound) {
          NSString *remainder = [output substringFromIndex:labelRange.location + labelRange.length];
          NSRange endQuote = [remainder rangeOfString:@"\""];
          if (endQuote.location != NSNotFound) {
            volumeLabel = [remainder substringToIndex:endQuote.location];
          }
        }
      }
      pclose(pipe);
    }
  } else if ([filesystem isEqualToString:@"ntfs"]) {
    // NTFS: Use ntfslabel if available
    NSString *ntfsCommand = [NSString stringWithFormat:@"ntfslabel %@ 2>/dev/null", devicePath];
    FILE *pipe = popen([ntfsCommand UTF8String], "r");
    if (pipe) {
      char buffer[256];
      if (fgets(buffer, sizeof(buffer), pipe)) {
        volumeLabel = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      }
      pclose(pipe);
    }
  } else if ([filesystem isEqualToString:@"ext2fs"]) {
    // ext2/3/4: Use e2label if available
    NSString *e2labelCommand = [NSString stringWithFormat:@"e2label %@ 2>/dev/null", devicePath];
    FILE *pipe = popen([e2labelCommand UTF8String], "r");
    if (pipe) {
      char buffer[256];
      if (fgets(buffer, sizeof(buffer), pipe)) {
        volumeLabel = [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      }
      pclose(pipe);
    }
  } else if ([filesystem isEqualToString:@"cd9660"]) {
    // ISO 9660: Use isoinfo if available, fallback to file command
    NSString *fileCommand = [NSString stringWithFormat:@"file -s %@", devicePath];
    FILE *pipe = popen([fileCommand UTF8String], "r");
    if (pipe) {
      char buffer[512];
      if (fgets(buffer, sizeof(buffer), pipe)) {
        NSString *output = [NSString stringWithUTF8String:buffer];
        // Look for volume identifier in ISO output
        NSRange volRange = [output rangeOfString:@"volume name "];
        if (volRange.location != NSNotFound) {
          NSString *remainder = [output substringFromIndex:volRange.location + volRange.length];
          NSArray *components = [remainder componentsSeparatedByString:@","];
          if (components.count > 0) {
            volumeLabel = [components[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
          }
        }
      }
      pclose(pipe);
    }
  }

  // Return sanitized volume name or nil if not found
  return volumeLabel ? [self sanitizeVolumeName:volumeLabel] : nil;
}

+ (NSString *)sanitizeVolumeName:(NSString *)volumeName
{
  if (!volumeName || [volumeName length] == 0) {
    return nil;
  }

  // Remove or replace invalid characters for filesystem paths
  NSMutableString *sanitized = [volumeName mutableCopy];
  
  // Replace invalid characters with underscores
  NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
  NSRange range = [sanitized rangeOfCharacterFromSet:invalidChars];
  while (range.location != NSNotFound) {
    [sanitized replaceCharactersInRange:range withString:@"_"];
    range = [sanitized rangeOfCharacterFromSet:invalidChars];
  }
  
  // Trim whitespace
  [sanitized setString:[sanitized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
  
  // Ensure it's not empty after sanitization
  if ([sanitized length] == 0) {
    return nil;
  }
  
  return [sanitized copy];
}

+ (NSString *)getZFSPoolName:(NSString *)devicePath
{
  if (!devicePath) {
    return nil;
  }

  // Use zpool status to find which pool contains this device
  NSString *zpoolCommand = @"zpool status -v";
  FILE *pipe = popen([zpoolCommand UTF8String], "r");
  if (!pipe) {
    return nil;
  }

  char buffer[256];
  NSString *currentPool = nil;
  NSString *deviceName = [devicePath lastPathComponent];
  
  while (fgets(buffer, sizeof(buffer), pipe)) {
    NSString *line = [NSString stringWithUTF8String:buffer];
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Check if this line starts a new pool
    if ([line hasPrefix:@"pool:"]) {
      currentPool = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    // Check if this line contains our device or any of its partitions
    else if (currentPool && [line containsString:deviceName]) {
      NSArray *components = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      for (NSString *component in components) {
        component = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        // Check exact match (for partition like ada0p4)
        if ([component isEqualToString:deviceName]) {
          pclose(pipe);
          return currentPool;
        }
        
        // Check if this is a partition of our device (ada0p4 contains ada0)
        if ([component hasPrefix:deviceName] && [component length] > [deviceName length]) {
          char nextChar = [component characterAtIndex:[deviceName length]];
          if (nextChar == 'p' || nextChar == 's') { // Common partition prefixes
            pclose(pipe);
            return currentPool;
          }
        }
      }
    }
  }
  
  pclose(pipe);
  return nil;
}

+ (NSDictionary *)getZFSPoolSummary:(NSString *)poolName
{
  if (!poolName) {
    return nil;
  }

  NSMutableDictionary *summary = [NSMutableDictionary dictionary];
  BOOL poolExists = NO;
  
  // Get pool status
  NSString *poolStatusCommand = [NSString stringWithFormat:@"zpool status %@", poolName];
  FILE *pipe = popen([poolStatusCommand UTF8String], "r");
  if (pipe) {
    char buffer[256];
    while (fgets(buffer, sizeof(buffer), pipe)) {
      NSString *line = [NSString stringWithUTF8String:buffer];
      if ([line containsString:@"state:"]) {
        NSArray *components = [line componentsSeparatedByString:@":"];
        if (components.count >= 2) {
          NSString *status = [[components[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
          summary[@"status"] = status;
          poolExists = YES;
        }
        break;
      }
    }
    pclose(pipe);
  }
  
  // If pool doesn't exist, return nil
  if (!poolExists) {
    return nil;
  }
  
  // Get dataset counts
  NSString *datasetCommand = [NSString stringWithFormat:@"zfs list -H -r %@", poolName];
  pipe = popen([datasetCommand UTF8String], "r");
  if (pipe) {
    int totalDatasets = 0;
    char buffer[512];
    while (fgets(buffer, sizeof(buffer), pipe)) {
      totalDatasets++;
    }
    summary[@"total_datasets"] = @(totalDatasets);
    pclose(pipe);
  }
  
  // Get encrypted dataset count
  NSString *encryptedCommand = [NSString stringWithFormat:@"zfs list -H -r -o name,encryption %@ | grep -v off | wc -l", poolName];
  pipe = popen([encryptedCommand UTF8String], "r");
  if (pipe) {
    char buffer[64];
    if (fgets(buffer, sizeof(buffer), pipe)) {
      int encryptedCount = atoi(buffer);
      summary[@"encrypted_datasets"] = @(encryptedCount);
    }
    pclose(pipe);
  }
  
  return [summary copy];
}

@end
