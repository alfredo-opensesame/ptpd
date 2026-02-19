#!/bin/bash
# Build ptpd and iOS PTP Monitor app for iOS Simulator

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==> Building ptpd for iOS Simulator..."

# Create iOS build directory
mkdir -p "$PROJECT_ROOT/build-cmake/ios-simulator"
cd "$PROJECT_ROOT/build-cmake/ios-simulator"

# Configure for iOS Simulator
cmake ../.. \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="15.0" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DCMAKE_C_FLAGS="-DPTPD_IOS=1 -DPTPD_LIBRARY_MODE=1" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DBUILD_WITH_SWCLOCK=ON \
    -DENABLE_DAEMON=OFF \
    -DENABLE_PCAP=OFF \
    -DENABLE_SNMP=OFF

echo "==> Building ptpd libraries..."
xcodebuild -project ptpd.xcodeproj \
    -scheme ALL_BUILD \
    -configuration Debug \
    -sdk iphonesimulator \
    -arch x86_64 \
    -arch arm64 \
    build

echo ""
echo "==> Checking build outputs..."
find . -name "*.a" -type f

echo "==> Building iOS PTP Monitor app..."
mkdir -p "$PROJECT_ROOT/build-cmake/ios-app"
cd "$PROJECT_ROOT/build-cmake/ios-app"

# Configure iOS app
cmake ../../src-app/ios \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="15.0"

echo "==> Opening Xcode project..."
open PTPMonitor.xcodeproj

echo ""
echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "1. Xcode should now be open with the PTPMonitor projet"
echo "2. Select an iOS Simulator from the scheme dropdown"
echo "3. Press Cmd+R to build and run"
echo ""
