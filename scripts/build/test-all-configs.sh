#!/bin/bash
#
# Master Test Script for PTPd CMake Migration
# Tests all key configurations and generates a summary report
#

set -e

echo "=========================================="
echo "PTPd CMake Migration - Comprehensive Tests"
echo "Testing all 16 configurations from CONFIGURATION-MATRIX.txt"
echo "=========================================="
echo ""
echo "Testing key configurations..."
echo ""

# All 16 configurations from CONFIGURATION-MATRIX.txt
CONFIGS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12" "13" "14" "15" "16")
CONFIG_NAMES=("default" "minimal" "sw-clock" "slave-only" "no-posix-timers" "no-pcap" "no-snmp" "no-statistics" "debug-basic" "debug-medium" "debug-all" "runtime-debug" "experimental" "no-daemon" "high-unicast" "combined")
PASSED=0
FAILED=0

# Create test results directory
mkdir -p test-results
REPORT="test-results/test-report-$(date +%Y%m%d-%H%M%S).txt"

echo "PTPd CMake Migration Test Report" > "$REPORT"
echo "Generated: $(date)" >> "$REPORT"
echo "========================================" >> "$REPORT"
echo "" >> "$REPORT"

for i in "${!CONFIGS[@]}"; do
    config="${CONFIGS[$i]}"
    config_name="${CONFIG_NAMES[$i]}"
    echo "Testing configuration $config: $config_name"
    if ./scripts/test-config.sh "$config" >> "$REPORT" 2>&1; then
        echo "  ✓ PASSED"
        ((PASSED++))
    else
        echo "  ✗ FAILED"
        ((FAILED++))
    fi
    echo "" >> "$REPORT"
done

# Generate summary
echo "" >> "$REPORT"
echo "========================================" >> "$REPORT"
echo "Summary" >> "$REPORT"
echo "========================================" >> "$REPORT"
echo "Total configurations tested: $((PASSED + FAILED))" >> "$REPORT"
echo "Passed: $PASSED" >> "$REPORT"
echo "Failed: $FAILED" >> "$REPORT"
echo "" >> "$REPORT"

# Print summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total: $((PASSED + FAILED))"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""
echo "Full report: $REPORT"
echo ""

# Clean up test build directories
echo "Cleaning up test directories..."
rm -rf build-test-autotools build-test-cmake

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests PASSED!"
    exit 0
else
    echo "✗ Some tests FAILED!"
    exit 1
fi
