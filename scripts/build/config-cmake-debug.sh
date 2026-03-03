#!/bin/bash
#
# CMake Debug Configuration Script for PTPd
# This script configures PTPd with CMake in Debug mode
#

set -e  # Exit on any error

echo "=== PTPd CMake Debug Configuration ==="

# Create and enter build directory
echo "Setting up CMake debug build directory..."
mkdir -p build-cmake/debug
cd build-cmake/debug

# Run CMake with debug options
echo "Configuring with CMake (Debug)..."
cmake ../.. \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DENABLE_RUNTIME_DEBUG=ON \
    -DDEBUG_LEVEL=all \
    -DENABLE_PCAP=ON \
    -DENABLE_SNMP=OFF \
    -DENABLE_STATISTICS=ON \
    -DENABLE_DAEMON=OFF \
    -DBUILD_WITH_SWCLOCK=ON

echo "=== CMake Debug configuration completed successfully ==="

# Copy compile_commands.json to workspace root for IntelliSense
if [ -f compile_commands.json ]; then
    echo "Copying compile_commands.json to workspace root..."
    cp compile_commands.json ../../compile_commands.json
    echo "✓ compile_commands.json ready for VS Code IntelliSense"
fi

echo ""
echo "Build directory: build-cmake/debug"
echo "To build: cd build-cmake/debug && make -j4"
echo "To run: ./build-cmake/debug/src/ptpd2 -f ptpd.conf -m"
