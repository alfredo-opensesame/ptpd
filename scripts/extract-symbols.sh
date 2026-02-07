#!/bin/bash
# extract-symbols.sh
# Extract and analyze symbols from a binary

if [ $# -lt 1 ]; then
    echo "Usage: $0 <binary> [output_file]"
    exit 1
fi

BINARY="$1"
OUTPUT="${2:-}"

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found: $BINARY"
    exit 1
fi

if [ -n "$OUTPUT" ]; then
    exec > "$OUTPUT"
fi

echo "Symbol Analysis for: $BINARY"
echo "================================"
echo ""

echo "### Global Symbols (exported)"
nm -g "$BINARY" | sort
echo ""

echo"### Symbol Count by Type"
nm "$BINARY" | awk '{print $2}' | sort | uniq -c | sort -rn
echo ""

echo "### Undefined Symbols (external dependencies)"
nm -u "$BINARY" | sort
echo ""

echo "### Text Symbols (functions)"
nm "$BINARY" | grep " T " | awk '{print $3}' | sort | head -50
echo ""

echo "### Data Symbols"
nm "$BINARY" | grep " D \| B " | awk '{print $2, $3}' | sort | head -30
echo ""

echo "### Statistics"
echo "  Total symbols: $(nm "$BINARY" | wc -l | tr -d ' ')"
echo "  Global symbols: $(nm -g "$BINARY" | wc -l | tr -d ' ')"
echo "  Undefined symbols: $(nm -u "$BINARY" | wc -l | tr -d ' ')"
echo "  Text (functions): $(nm "$BINARY" | grep -c " T ")"
echo "  Data: $(nm "$BINARY" | grep -c " D ")"
echo "  BSS: $(nm "$BINARY" | grep -c " B ")"
