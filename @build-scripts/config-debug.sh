#!/bin/bash
#
# Debug Configuration Script for PTPd
# This script configures PTPd with full debugging capabilities
#

set -e  # Exit on any error

echo "=== PTPd Debug Configuration ==="

# Generate configure script if needed
if [ ! -f configure ]; then
    echo "Generating configure script..."
    autoreconf -fiv
fi

# Create and enter build directory
echo "Setting up debug build directory..."
mkdir -p build/debug
cd build/debug

# Run configure with debug options
echo "Configuring with debug options..."
../../configure \
    --enable-runtime-debug \
    --enable-debug-level=all \
    --enable-pcap \
    --enable-snmp \
    --enable-statistics \
    --disable-daemon \
    --enable-sw-clock

echo "=== Debug configuration completed successfully ==="

# Build with bear to generate compile_commands.json
echo "Building with bear to generate compile_commands.json..."
if command -v bear >/dev/null 2>&1; then
    bear -- make clean && bear -- make
    
    # Verify compile_commands.json was generated
    if [ -f compile_commands.json ]; then
        echo "✓ compile_commands.json generated in build/debug directory"
        echo "✓ VS Code IntelliSense should now recognize SW_CLOCK_ENABLED and other definitions"
    else
        echo "Warning: compile_commands.json was not generated"
    fi
else
    echo "Warning: bear not found. Install bear with 'brew install bear' to generate compile_commands.json"
    echo "Running regular build..."
    make clean && make
fi

echo "=== Debug build completed successfully ==="
