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
echo "Next step: run 'make clean && make' in build/release directory"
