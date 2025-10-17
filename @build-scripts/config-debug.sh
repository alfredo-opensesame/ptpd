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
echo "Next step: run 'make clean && make' in build/debug directory"
