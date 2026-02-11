#!/bin/bash
# compare-binaries.sh
# Compare two binaries for equivalence (from PLAN.txt Phase 0)

if [ $# -ne 2 ]; then
    echo "Usage: $0 <autotools_binary> <cmake_binary>"
    exit 1
fi

AUTO_BIN="$1"
CMAKE_BIN="$2"

if [ ! -f "$AUTO_BIN" ]; then
    echo "Error: Autotools binary not found: $AUTO_BIN"
    exit 1
fi

if [ ! -f "$CMAKE_BIN" ]; then
    echo "Error: CMake binary not found: $CMAKE_BIN"
    exit 1
fi

echo "========================================="
echo "Binary Comparison Report"
echo "========================================="
echo "Autotools: $AUTO_BIN"
echo "CMake:     $CMAKE_BIN"
echo ""

echo "=== Size Comparison ==="
echo "Autotools:"
ls -lh "$AUTO_BIN" | awk '{print "  Size: " $5 ", Permissions: " $1}'
echo "CMake:"
ls -lh "$CMAKE_BIN" | awk '{print "  Size: " $5 ", Permissions: " $1}'
echo ""

AUTO_SIZE=$(stat -f%z "$AUTO_BIN" 2>/dev/null || stat -c%s "$AUTO_BIN" 2>/dev/null)
CMAKE_SIZE=$(stat -f%z "$CMAKE_BIN" 2>/dev/null || stat -c%s "$CMAKE_BIN" 2>/dev/null)

if [ -n "$AUTO_SIZE" ] && [ -n "$CMAKE_SIZE" ]; then
    DIFF=$(echo "scale=2; ($CMAKE_SIZE - $AUTO_SIZE) / $AUTO_SIZE * 100" | bc)
    echo "  Size difference: ${DIFF}%"

    # Check if within 5% tolerance
    ABS_DIFF=$(echo "$DIFF" | tr -d -)
    if (( $(echo "$ABS_DIFF < 5" | bc -l) )); then
        echo "  ✓ Within 5% tolerance"
    else
        echo "  ✗ Outside 5% tolerance"
    fi
fi
echo ""

echo "=== File Type ==="
echo "Autotools:"
file "$AUTO_BIN" | sed 's/^/  /'
echo "CMake:"
file "$CMAKE_BIN" | sed 's/^/  /'
echo ""

echo "=== Symbol Count ==="
AUTO_SYMS=$(nm -g "$AUTO_BIN" 2>/dev/null | wc -l | tr -d ' ')
CMAKE_SYMS=$(nm -g "$CMAKE_BIN" 2>/dev/null | wc -l | tr -d ' ')
echo "  Autotools: $AUTO_SYMS symbols"
echo "  CMake:     $CMAKE_SYMS symbols"

if [ "$AUTO_SYMS" -gt 0 ] && [ "$CMAKE_SYMS" -gt 0 ]; then
    SYM_DIFF=$(echo "scale=2; ($CMAKE_SYMS - $AUTO_SYMS) / $AUTO_SYMS * 100" | bc)
    echo "  Difference: ${SYM_DIFF}%"
fi
echo ""

echo "=== Symbol Diff ==="
TMP_DIR=$(mktemp -d)
nm -g "$AUTO_BIN" | awk '{print $NF}' | sort > "$TMP_DIR/sym-auto.txt"
nm -g "$CMAKE_BIN" | awk '{print $NF}' | sort > "$TMP_DIR/sym-cmake.txt"

if diff -q "$TMP_DIR/sym-auto.txt" "$TMP_DIR/sym-cmake.txt" > /dev/null 2>&1; then
    echo "  ✓ Symbols are IDENTICAL"
else
    echo "  ✗ Symbols differ:"
    echo ""
    echo "  Only in Autotools:"
    diff "$TMP_DIR/sym-auto.txt" "$TMP_DIR/sym-cmake.txt" | grep "^<" | head -10 | sed 's/^/    /'
    echo ""
    echo "  Only in CMake:"
    diff "$TMP_DIR/sym-auto.txt" "$TMP_DIR/sym-cmake.txt" | grep "^>" | head -10 | sed 's/^/    /'
fi
echo ""

echo "=== Linked Libraries ==="
echo "Autotools:"
if command -v otool > /dev/null 2>&1; then
    otool -L "$AUTO_BIN" | tail -n +2 | sed 's/^/  /'
elif command -v ldd > /dev/null 2>&1; then
    ldd "$AUTO_BIN" | sed 's/^/  /'
fi
echo ""
echo "CMake:"
if command -v otool > /dev/null 2>&1; then
    otool -L "$CMAKE_BIN" | tail -n +2 | sed 's/^/  /'
elif command -v ldd > /dev/null 2>&1; then
    ldd "$CMAKE_BIN" | sed 's/^/  /'
fi
echo ""

echo "=== Embedded Strings Sample (first 20 differences) ==="
strings "$AUTO_BIN" | grep -v "^/Users\|^/tmp\|^/build" | sort > "$TMP_DIR/str-auto.txt"
strings "$CMAKE_BIN" | grep -v "^/Users\|^/tmp\|^/build" | sort > "$TMP_DIR/str-cmake.txt"

if diff -q "$TMP_DIR/str-auto.txt" "$TMP_DIR/str-cmake.txt" > /dev/null 2>&1; then
    echo "  ✓ Strings are IDENTICAL (ignoring build paths)"
else
    echo "  ✗ Strings differ (showing first 20 differences):"
    diff "$TMP_DIR/str-auto.txt" "$TMP_DIR/str-cmake.txt" | head -40 | sed 's/^/  /'
fi
echo ""

echo "=== Function Test ==="
echo "Testing --help flag..."
if "$AUTO_BIN" --help > "$TMP_DIR/help-auto.txt" 2>&1; then
    echo "  ✓ Autotools binary runs"
else
    echo "  ✗ Autotools binary failed"
fi

if "$CMAKE_BIN" --help > "$TMP_DIR/help-cmake.txt" 2>&1; then
    echo "  ✓ CMake binary runs"
else
    echo "  ✗ CMake binary failed"
fi

if diff -q "$TMP_DIR/help-auto.txt" "$TMP_DIR/help-cmake.txt" > /dev/null 2>&1; then
    echo "  ✓ Help output is IDENTICAL"
else
    echo "  ✗ Help output differs"
fi
echo ""

# Cleanup
rm -rf "$TMP_DIR"

echo "========================================="
echo "Comparison Complete"
echo "========================================="
