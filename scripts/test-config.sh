#!/bin/bash
#
# Test Configuration Script for PTPd CMake Migration
# Tests a specific configuration with both autotools and CMake
#

set -e

CONFIG_NAME="${1:-default}"
VERBOSE="${VERBOSE:-0}"

echo "=========================================="
echo "Testing Configuration: $CONFIG_NAME"
echo "=========================================="
echo ""

# Define test configurations (from CONFIGURATION-MATRIX.txt)
case "$CONFIG_NAME" in
    "default"|"1")
        AUTOTOOLS_OPTS=""
        CMAKE_OPTS="-DENABLE_SNMP=OFF"
        ;;
    "minimal"|"2")
        AUTOTOOLS_OPTS="--disable-posix-timers --disable-pcap --disable-snmp --disable-daemon --disable-statistics --disable-so-timestamping --with-max-unicast-destinations=16"
        CMAKE_OPTS="-DENABLE_POSIX_TIMERS=OFF -DENABLE_PCAP=OFF -DENABLE_SNMP=OFF -DENABLE_DAEMON=OFF -DENABLE_STATISTICS=OFF -DENABLE_SO_TIMESTAMPING=OFF -DMAX_UNICAST_DESTINATIONS=16"
        ;;
    "sw-clock"|"3")
        AUTOTOOLS_OPTS="--enable-sw-clock"
        CMAKE_OPTS="-DENABLE_SW_CLOCK=ON -DENABLE_SNMP=OFF"
        ;;
    "slave-only"|"4")
        AUTOTOOLS_OPTS="--enable-slave-only"
        CMAKE_OPTS="-DENABLE_SLAVE_ONLY=ON -DENABLE_SNMP=OFF"
        ;;
    "no-posix-timers"|"5")
        AUTOTOOLS_OPTS="--disable-posix-timers"
        CMAKE_OPTS="-DENABLE_POSIX_TIMERS=OFF -DENABLE_SNMP=OFF"
        ;;
    "no-pcap"|"6")
        AUTOTOOLS_OPTS="--disable-pcap"
        CMAKE_OPTS="-DENABLE_PCAP=OFF -DENABLE_SNMP=OFF"
        ;;
    "no-snmp"|"7")
        AUTOTOOLS_OPTS="--disable-snmp"
        CMAKE_OPTS="-DENABLE_SNMP=OFF"
        ;;
    "no-statistics"|"8")
        AUTOTOOLS_OPTS="--disable-statistics"
        CMAKE_OPTS="-DENABLE_STATISTICS=OFF -DENABLE_SNMP=OFF"
        ;;
    "debug-basic"|"9")
        AUTOTOOLS_OPTS="--enable-debug-level=basic"
        CMAKE_OPTS="-DDEBUG_LEVEL=basic -DENABLE_SNMP=OFF"
        ;;
    "debug-medium"|"10")
        AUTOTOOLS_OPTS="--enable-debug-level=medium"
        CMAKE_OPTS="-DDEBUG_LEVEL=medium -DENABLE_SNMP=OFF"
        ;;
    "debug-all"|"11")
        AUTOTOOLS_OPTS="--enable-debug-level=all"
        CMAKE_OPTS="-DDEBUG_LEVEL=all -DENABLE_SNMP=OFF"
        ;;
    "runtime-debug"|"12")
        AUTOTOOLS_OPTS="--enable-runtime-debug"
        CMAKE_OPTS="-DENABLE_RUNTIME_DEBUG=ON -DENABLE_SNMP=OFF"
        ;;
    "experimental"|"13")
        AUTOTOOLS_OPTS="--enable-experimental-options"
        CMAKE_OPTS="-DENABLE_EXPERIMENTAL=ON -DENABLE_SNMP=OFF"
        ;;
    "no-daemon"|"14")
        AUTOTOOLS_OPTS="--disable-daemon"
        CMAKE_OPTS="-DENABLE_DAEMON=OFF -DENABLE_SNMP=OFF"
        ;;
    "high-unicast"|"15")
        AUTOTOOLS_OPTS="--with-max-unicast-destinations=2048"
        CMAKE_OPTS="-DMAX_UNICAST_DESTINATIONS=2048 -DENABLE_SNMP=OFF"
        ;;
    "combined"|"16")
        AUTOTOOLS_OPTS="--enable-sw-clock --enable-slave-only --enable-debug-level=all --with-max-unicast-destinations=512"
        CMAKE_OPTS="-DENABLE_SW_CLOCK=ON -DENABLE_SLAVE_ONLY=ON -DDEBUG_LEVEL=all -DMAX_UNICAST_DESTINATIONS=512 -DENABLE_SNMP=OFF"
        ;;
    *)
        echo "Unknown configuration: $CONFIG_NAME"
        echo "Valid configurations:"
        echo "  1|default         - Default configuration"
        echo "  2|minimal         - Minimal (all optional features OFF)"
        echo "  3|sw-clock        - Software clock enabled"
        echo "  4|slave-only      - Slave-only mode"
        echo "  5|no-posix-timers - Without POSIX timers"
        echo "  6|no-pcap         - Without PCAP"
        echo "  7|no-snmp         - Without SNMP"
        echo "  8|no-statistics   - Without statistics"
        echo "  9|debug-basic     - Debug level basic"
        echo "  10|debug-medium   - Debug level medium"
        echo "  11|debug-all      - Debug level all"
        echo "  12|runtime-debug  - Runtime debug enabled"
        echo "  13|experimental   - Experimental features"
        echo "  14|no-daemon      - Without daemon mode"
        echo "  15|high-unicast   - Max unicast 2048"
        echo "  16|combined       - Combined features test"
        exit 1
        ;;
esac

echo "Autotools options: $AUTOTOOLS_OPTS"
echo "CMake options: $CMAKE_OPTS"
echo ""

# Build with autotools
echo "Building with autotools..."
rm -rf build-test-autotools
mkdir -p build-test-autotools
cd build-test-autotools

if [ "$VERBOSE" = "1" ]; then
    ../configure $AUTOTOOLS_OPTS
    make -j4
else
    ../configure $AUTOTOOLS_OPTS > /dev/null 2>&1
    make -j4 > /dev/null 2>&1
fi

AUTOTOOLS_BINARY="src/ptpd2"
AUTOTOOLS_SIZE=$(ls -lh $AUTOTOOLS_BINARY | awk '{print $5}')
AUTOTOOLS_VERSION=$($AUTOTOOLS_BINARY --version 2>&1)
AUTOTOOLS_SYMBOLS=$(nm $AUTOTOOLS_BINARY | grep " [TtBbDd] " | wc -l | tr -d ' ')

cd ..

# Build with CMake
echo "Building with CMake..."
rm -rf build-test-cmake
mkdir -p build-test-cmake
cd build-test-cmake

if [ "$VERBOSE" = "1" ]; then
    cmake .. -DCMAKE_BUILD_TYPE=Release $CMAKE_OPTS
    make -j4
else
    cmake .. -DCMAKE_BUILD_TYPE=Release $CMAKE_OPTS > /dev/null 2>&1
    make -j4 > /dev/null 2>&1
fi

CMAKE_BINARY="src/ptpd2"
CMAKE_SIZE=$(ls -lh $CMAKE_BINARY | awk '{print $5}')
CMAKE_VERSION=$($CMAKE_BINARY --version 2>&1)
CMAKE_SYMBOLS=$(nm $CMAKE_BINARY | grep " [TtBbDd] " | wc -l | tr -d ' ')

cd ..

# Compare results
echo ""
echo "=========================================="
echo "Test Results: $CONFIG_NAME"
echo "=========================================="
echo ""
echo "Autotools:"
echo "  Size:    $AUTOTOOLS_SIZE"
echo "  Version: $AUTOTOOLS_VERSION"
echo "  Symbols: $AUTOTOOLS_SYMBOLS"
echo ""
echo "CMake:"
echo "  Size:    $CMAKE_SIZE"
echo "  Version: $CMAKE_VERSION"
echo "  Symbols: $CMAKE_SYMBOLS"
echo ""

# Check if versions match
if [ "$AUTOTOOLS_VERSION" = "$CMAKE_VERSION" ]; then
    echo "✓ Version strings match"
else
    echo "✗ Version strings differ!"
    exit 1
fi

# Check if symbol counts are close (within 10%)
SYMBOL_DIFF=$((CMAKE_SYMBOLS - AUTOTOOLS_SYMBOLS))
SYMBOL_DIFF=${SYMBOL_DIFF#-}  # absolute value
SYMBOL_PERCENT=$((SYMBOL_DIFF * 100 / AUTOTOOLS_SYMBOLS))

if [ $SYMBOL_PERCENT -le 10 ]; then
    echo "✓ Symbol counts close (within 10%): diff=$SYMBOL_DIFF ($SYMBOL_PERCENT%)"
else
    echo "✗ Symbol counts differ significantly: diff=$SYMBOL_DIFF ($SYMBOL_PERCENT%)"
fi

echo ""
echo "=========================================="
echo "Test PASSED: $CONFIG_NAME"
echo "=========================================="
