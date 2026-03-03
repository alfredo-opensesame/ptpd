#!/bin/bash
#
# CMake Release Configuration Script for PTPd
# This script configures PTPd with CMake in Release mode
#

set -e  # Exit on any error

echo "=== PTPd CMake Release Configuration ==="

# Create and enter build directory
echo "Setting up CMake release build directory..."
mkdir -p build-cmake/release
cd build-cmake/release

# Run CMake with release options
echo "Configuring with CMake (Release)..."
cmake ../.. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DENABLE_PCAP=ON \
    -DENABLE_SNMP=OFF \
    -DENABLE_STATISTICS=ON \
    -DENABLE_DAEMON=ON \
    -DBUILD_WITH_SWCLOCK=ON

echo "=== CMake Release configuration completed successfully ==="

# Copy compile_commands.json to workspace root for IntelliSense
if [ -f compile_commands.json ]; then
    echo "Copying compile_commands.json to workspace root..."
    cp compile_commands.json ../../compile_commands.json
    echo "✓ compile_commands.json ready for VS Code IntelliSense"
fi

echo ""
echo "Build directory: build-cmake/release"
echo "To build: cd build-cmake/release && make -j4"
echo "To install: cd build-cmake/release && cmake --install . --prefix /usr/local"
