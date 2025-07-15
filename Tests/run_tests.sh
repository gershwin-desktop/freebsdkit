#!/bin/sh

# FreeBSDKit Test Runner
# This script runs the unit tests for FreeBSDKit

echo "FreeBSDKit Test Runner"
echo "======================"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Check if UnitKit is available
if ! command -v ukrun >/dev/null 2>&1; then
    echo "Error: ukrun command not found. Please install UnitKit framework."
    echo "Visit: https://github.com/gnustep/framework-UnitKit"
    exit 1
fi

# Build the test bundle
echo "Building test bundle..."
gmake clean > /dev/null 2>&1
if ! gmake all; then
    echo "Error: Failed to build test bundle."
    exit 1
fi

echo "Test bundle built successfully."
echo ""

# Run the tests
echo "Running tests..."
echo "================"
ukrun FBDiskManagerTests.bundle

TEST_RESULT=$?

echo ""
echo "================"
if [ $TEST_RESULT -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Some tests failed. Exit code: $TEST_RESULT"
fi

exit $TEST_RESULT