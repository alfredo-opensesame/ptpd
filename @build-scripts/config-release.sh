#!/bin/bash
#
# Release Configuration Script for PTPd
# This script configures PTPd for optimized release builds
#

set -e  # Exit on any error

echo "=== PTPd Release Configuration ==="

# Generate configure script if needed
if [ ! -f configure ]; then
    echo "Generating configure script..."
    autoreconf -fiv
fi

# Create and enter build directory
echo "Setting up release build directory..."
mkdir -p build/release
cd build/release

# Run configure with release options
echo "Configuring with release options..."
../../configure \
    --enable-pcap \
    --enable-snmp \
    --enable-statistics \
    --disable-daemon \
    --enable-sw-clock

echo "=== Release configuration completed successfully ==="

# Build with bear to generate compile_commands.json
echo "Building with bear to generate compile_commands.json..."
if command -v bear >/dev/null 2>&1; then
    bear -- make clean && bear -- make
    
    # Copy compile_commands.json to project root for VS Code IntelliSense
    if [ -f compile_commands.json ]; then
        echo "Copying compile_commands.json to project root..."
        cp compile_commands.json ../../compile_commands.json
        echo "compile_commands.json generated successfully for VS Code IntelliSense"
    else
        echo "Warning: compile_commands.json was not generated"
    fi
else
    echo "Warning: bear not found. Install bear with 'brew install bear' to generate compile_commands.json"
    echo "Running regular build..."
    make clean && make
fi

echo "=== Release build completed successfully ==="
