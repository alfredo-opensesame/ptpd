#!/usr/bin/env bash
# scripts/tools/clean-ptpd.sh
# Clean PTPd CMake build artifacts.
#   Default: remove CMake build directories and object/temp files.
#   -L : also remove ./ptp_test and ./ptp_logs
#   -n : dry run (show what would be removed)

set -euo pipefail

WIPE_LOGS=0  # -L
DRY=0        # -n

usage() {
  echo "Usage: $0 [-L] [-n]"
  echo "  -L : also remove ./ptp_test and ./ptp_logs"
  echo "  -n : dry run (show actions only)"
  exit 1
}

while getopts ":Ln" opt; do
  case "$opt" in
    L) WIPE_LOGS=1 ;;
    n) DRY=1 ;;
    *) usage ;;
  esac
done

# Repo root = parent of parent of this script's directory (scripts/tools -> scripts -> root)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

echo "▶ Repo root      : $ROOT_DIR"
echo "▶ Mode           : clean$([[ $WIPE_LOGS -eq 1 ]] && echo ' +logs')$([[ $DRY -eq 1 ]] && echo ' (dry)')"

rmx() { if [[ $DRY -eq 1 ]]; then echo "  (dry) rm -rf $*"; else rm -rf "$@"; fi; }
runmake() { if [[ $DRY -eq 1 ]]; then echo "  (dry) make -C $1 $2"; else make -C "$1" "$2" -k || true; fi; }

# 1) CMake build directories
for build_dir in build-cmake build/ninja-debug-macos build/ninja-release-macos; do
  if [[ -d "$build_dir" ]]; then
    echo "▶ Cleaning ./$build_dir..."
    [[ -f "$build_dir/Makefile" ]] && runmake "$build_dir" clean
    [[ -f "$build_dir/build.ninja" ]] && {
      if [[ $DRY -eq 1 ]]; then
        echo "  (dry) ninja -C $build_dir clean"
      else
        (cd "$build_dir" && ninja clean) 2>/dev/null || true
      fi
    }
    rmx "$build_dir"
  fi
done

# 2) Compiled artifacts
echo "▶ Removing .o / .lo / .la / .a / ptpd2 in src/…"
find src -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' -o -name '*.a' -o -name 'ptpd2' \) -not -path './.git/*' -exec sh -c 'if [[ '$DRY' -eq 1 ]]; then echo "  (dry) rm {}"; else rm "{}"; fi' \; 2>/dev/null || true

# 3) macOS junk
if [[ $DRY -eq 1 ]]; then
  find . -name '.DS_Store' -not -path './.git/*' -print | sed 's/^/  (dry) rm /'
else
  find . -name '.DS_Store' -not -path './.git/*' -delete 2>/dev/null || true
fi

# 4) Optional: test artifacts
if [[ $WIPE_LOGS -eq 1 ]]; then
  [[ -d ptp_test ]] && { echo "▶ Removing ./ptp_test…"; rmx ptp_test; }
  [[ -d ptp_logs ]] && { echo "▶ Removing ./ptp_logs…"; rmx ptp_logs; }
fi

# 5) Symlink (if present)
[[ -L compile_commands.json ]] && { echo "▶ Removing compile_commands.json symlink…"; rmx compile_commands.json; }

echo "✅ Done."

# 2) In-tree 'make clean' if Makefile exists
if [[ -f Makefile ]]; then
  echo "▶ make clean (top-level)…"
  runmake . clean
fi

# 3) Purge objects/temp under src/
echo "▶ Removing object/temp files under src/…"
if [[ $DRY -eq 1 ]]; then
  find src -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' -o -name '.nfs*' \) -print | sed 's/^/  (dry) rm /'
else
  find src -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' -o -name '.nfs*' \) -delete || true
fi
if [[ $DRY -eq 1 ]]; then
  find src -type d \( -name .deps -o -name .libs \) -print | sed 's/^/  (dry) rm -rf /'
else
  find src -type d \( -name .deps -o -name .libs \) -exec rm -rf {} + || true
fi
# built binaries / dSYMs
[[ $DRY -eq 1 ]] && echo "  (dry) rm -rf src/ptpd2 src/*.dSYM" || rm -rf src/ptpd2 src/*.dSYM 2>/dev/null || true

# 3.5) Remove common temporary/backup files throughout the tree
echo "▶ Removing temporary and backup files…"
TEMP_PATTERNS=('*~' '*.orig' '*.rej' '*.bak' '.*.swp' '.*.tmp' '*.pyc' 'core.*' '*.core')
for pattern in "${TEMP_PATTERNS[@]}"; do
  if [[ $DRY -eq 1 ]]; then
    find . -name "$pattern" -not -path './build/*' -not -path './.git/*' -print | sed 's/^/  (dry) rm /'
  else
    find . -name "$pattern" -not -path './build/*' -not -path './.git/*' -delete 2>/dev/null || true
  fi
done

# Remove Python cache directories
if [[ $DRY -eq 1 ]]; then
  find . -type d -name '__pycache__' -not -path './.git/*' -print | sed 's/^/  (dry) rm -rf /'
else
  find . -type d -name '__pycache__' -not -path './.git/*' -exec rm -rf {} + 2>/dev/null || true
fi

# Remove macOS metadata files
if [[ $DRY -eq 1 ]]; then
  find . -name '.DS_Store' -not -path './.git/*' -print | sed 's/^/  (dry) rm /'
else
  find . -name '.DS_Store' -not -path './.git/*' -delete 2>/dev/null || true
fi

# 4) Optional: test artifacts
if [[ $WIPE_LOGS -eq 1 ]]; then
  [[ -d ptp_test ]] && { echo "▶ Removing ./ptp_test…"; rmx ptp_test; }
  [[ -d ptp_logs ]] && { echo "▶ Removing ./ptp_logs…"; rmx ptp_logs; }
fi

echo "✅ Done."
