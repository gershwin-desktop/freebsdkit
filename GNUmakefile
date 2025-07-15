include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = FreeBSDKit

# List of headers to install
FreeBSDKit_HEADER_FILES = FreeBSDKit.h FBDiskManager.h
FreeBSDKit_HEADER_INSTALLDIR = FreeBSDKit.framework/Headers

# Source files
FreeBSDKit_OBJC_FILES = FreeBSDKit.m FBDiskManager.m

# To set install location like macOS, remove `/usr/local/GNUstep` prefix
FreeBSDKit_INSTALLDIR = /System/Library/Frameworks

include $(GNUSTEP_MAKEFILES)/framework.make

# Test target
test:
	cd Tests && gmake test

# Clean test artifacts
clean-test:
	cd Tests && gmake clean-test

.PHONY: test clean-test

