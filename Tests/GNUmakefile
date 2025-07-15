include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = FBDiskManagerTests

# Source files for the test bundle
FBDiskManagerTests_OBJC_FILES = \
	FBDiskManagerTest.m \
	../FBDiskManager.m

# Header files to include
FBDiskManagerTests_HEADER_FILES = \
	FBDiskManagerTest.h

# Libraries to link
FBDiskManagerTests_OBJC_LIBS = -lUnitKit -lgeom

# Include directories
FBDiskManagerTests_INCLUDE_DIRS = -I..

# Framework dependencies
FBDiskManagerTests_GUI_LIBS = 
FBDiskManagerTests_FOUNDATION_LIBS = 

include $(GNUSTEP_MAKEFILES)/bundle.make

# Custom target to run tests
test: all
	ukrun FBDiskManagerTests.bundle

# Clean test artifacts
clean-test:
	rm -rf FBDiskManagerTests.bundle

# Override clean target to include bundle cleanup
clean::
	rm -rf FBDiskManagerTests.bundle

.PHONY: test clean-test clean