#import "FBDiskManager.h"
#include <sys/types.h>
#include <sys/sysctl.h>
#include <libgeom.h>
#include <string.h>

@implementation FBDiskManager

+ (NSArray *)getDiskNames {
    size_t size;
    sysctlbyname("kern.disks", NULL, &size, NULL, 0);

    char *buffer = malloc(size);
    if (!buffer) return nil;

    sysctlbyname("kern.disks", buffer, &size, NULL, 0);
    NSString *disksString = [NSString stringWithUTF8String:buffer];
    free(buffer);

    NSArray *disksArray = [disksString componentsSeparatedByString:@" "];
    return disksArray;
}

+ (NSMutableDictionary *)getAllDiskInfo {
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
    LIST_FOREACH(classPtr, &mesh.lg_class, lg_class) {
        // Only process the "DISK" class
        if (strcmp(classPtr->lg_name, "DISK") != 0) {
            continue;
        }

        // Iterate through each geom in the DISK class
        LIST_FOREACH(geomPtr, &classPtr->lg_geom, lg_geom) {
            LIST_FOREACH(providerPtr, &geomPtr->lg_provider, lg_provider) {
                NSString *diskName = [NSString stringWithFormat:@"%s", providerPtr->lg_name];
                NSString *diskPath = [NSString stringWithFormat:@"/dev/%s", providerPtr->lg_name];

                // Store disk attributes in dictionary
                NSDictionary *diskInfo = @{
                    @"name": diskName,
                    @"path": diskPath,
                    @"mediasize_bytes": @(providerPtr->lg_mediasize),
                    @"sectorsize_bytes": @(providerPtr->lg_sectorsize),
                    @"stripe_size": @(providerPtr->lg_stripesize),
                    @"stripe_offset": @(providerPtr->lg_stripeoffset),
                    @"mode": @(providerPtr->lg_mode)
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

+ (NSMutableDictionary *)getDiskInfo:(NSString *)diskName {
    NSDictionary *allDisks = [self getAllDiskInfo];
    if (!allDisks) {
        return nil; // Handle case where no disk info is available
    }

    NSDictionary *diskInfo = allDisks[diskName];
    if (diskInfo) {
        return [diskInfo mutableCopy];
    } else {
        NSLog(@"Disk %@ not found", diskName);
        return nil;
    }
}

@end

