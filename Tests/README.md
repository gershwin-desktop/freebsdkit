# FreeBSDKit Unit Tests

This directory contains unit tests for the FreeBSDKit framework using the UnitKit testing framework.

## Prerequisites

- GNUstep development environment
- UnitKit framework installed
- FreeBSD system (tests are platform-specific)

## Installing UnitKit

```bash
# Clone and build UnitKit
git clone https://github.com/gnustep/framework-UnitKit.git
cd framework-UnitKit
make && make install
```

## Running Tests

### Quick Test Run
```bash
# From the Tests directory
./run_tests.sh
```

### Manual Test Run
```bash
# Build the test bundle
gmake all

# Run tests
ukrun FBDiskManagerTests.bundle
```

### From Main Directory
```bash
# Run tests from the main FreeBSDKit directory
gmake test
```

## Important Notes

- **Use `gmake` instead of `make`**: FreeBSD's native `make` is BSD make, but GNUstep requires GNU make (`gmake`)
- The test script automatically handles this by using `gmake` internally

## Test Structure

### FBDiskManagerTest.m
Contains unit tests for the FBDiskManager class covering:

#### Existing Methods
- `testGetDiskNames` - Tests disk name retrieval
- `testGetAllDiskInfo` - Tests comprehensive disk information gathering
- `testGetDiskInfo` - Tests single disk information retrieval
- `testGetDiskInfoWithInvalidDisk` - Tests error handling for invalid disks

#### Mount/Unmount Methods
- `testMountVolumeWithInvalidParameters` - Tests parameter validation
- `testUnmountVolumeWithInvalidParameters` - Tests unmount parameter validation
- `testGetMountedVolumes` - Tests mounted volume enumeration
- `testIsMountedWithNilParameter` - Tests mount status checking
- `testMountUnmountFlow` - Tests the complete mount/unmount workflow

## Test Coverage

The tests cover:
- ✅ Parameter validation and error handling
- ✅ Return value types and structure validation
- ✅ Basic functionality verification
- ✅ Edge cases and error conditions
- ⚠️ Actual mount/unmount operations (limited due to system requirements)

## Notes

- Some tests require root privileges for actual mount operations
- ZFS filesystems are explicitly excluded from mount tests
- Tests create temporary mount points in system temp directory
- Mount tests use error simulation rather than actual devices for safety

## Contributing

When adding new tests:
1. Follow the existing naming convention
2. Include both positive and negative test cases
3. Clean up any resources created during testing
4. Update this README if adding new test categories