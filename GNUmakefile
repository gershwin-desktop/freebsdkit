include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = FreeBSDKit

# List of headers to install
FreeBSDKit_HEADER_FILES = FreeBSDKit.h FBDiskManager.h
FreeBSDKit_HEADER_INSTALLDIR = FreeBSDKit.framework/Headers

# Source files
FreeBSDKit_OBJC_FILES = FreeBSDKit.m FBDiskManager.m

# To set install location like macOS, remove `/usr/local/GNUstep` prefix
FreeBSDKit_INSTALLDIR = /usr/local/GNUstep/System/Library/Frameworks

include $(GNUSTEP_MAKEFILES)/framework.make

