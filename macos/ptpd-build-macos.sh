#!/usr/bin/env bash
# build-ptpd-macos.sh
# Build PTPd from THIS ptpd/ tree into ./build on macOS (no install).
# Enables runtime debug & stats and patches macOS timer/typo issues.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/src"
BUILD_DIR="$SCRIPT_DIR/build"

echo "▶ PTPd Root    : $PROJECT_ROOT"
echo "▶ Src folder   : $SRC_DIR"
echo "▶ Build folder : $BUILD_DIR"
echo "▶ Scripts      : $SCRIPT_DIR"

# 1) Tooling checks
if ! xcode-select -p >/dev/null 2>&1; then
  echo "✖ Xcode Command Line Tools missing. Install with: xcode-select --install"
  exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "✖ Homebrew required. Install from https://brew.sh/"
  exit 1
fi

# 2) Deps
brew install autoconf automake libtool pkgconf openssl@3 || true

OPENSSL_PREFIX="$(brew --prefix openssl@3)"
export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$OPENSSL_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$OPENSSL_PREFIX/lib ${LDFLAGS:-}"

# Strongly suggested for verbose debugging:
export CFLAGS="-O0 -g -fno-omit-frame-pointer \
  -DRUNTIME_DEBUG -DPTPD_STATISTICS -DPTPD_PCAP \
  ${CFLAGS:-}"

# 3) Fresh build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 4) QUICK PATCHES (macOS portability + tiny typo)
# - macOS lacks POSIX timers (timer_t); when POSIX timers are disabled,
#   don't declare timer_t in eventtimer.h.
# - Also fix 'const const' in signaling.c (harmless but noisy).
cd "$PROJECT_ROOT"
if [ -f src/dep/eventtimer.h ]; then
  awk '
    BEGIN { patched=0 }
    /struct IntervalTimer/ {
      print; getline; print;
      if ($0 ~ /timer_t[[:space:]]+timerId;/) {
        print "#ifdef POSIX_TIMERS_SUPPORTED";
        print "        timer_t timerId;";
        print "#else";
        print "        int timerId; /* unused on platforms without POSIX timers (e.g., macOS) */";
        print "#endif";
        # skip the original line
        patched=1;
        next;
      }
    }
    { print }
    END {
      if (patched) {
        print "" > "/dev/stderr"
      }
    }
  ' src/dep/eventtimer.h > src/dep/eventtimer.h.patched
  mv src/dep/eventtimer.h.patched src/dep/eventtimer.h
fi

# remove duplicate const in signaling.c if present
if [ -f src/signaling.c ]; then
  perl -pi -e 's/\bconst\s+const\b/const /g' src/signaling.c
fi

# 5) Autotools bootstrap (only if needed)
if [[ -x "./bootstrap" ]]; then
  echo "▶ Running bootstrap…"
  ./bootstrap || true
elif [[ -x "./bootstrap.sh" ]]; then
  echo "▶ Running bootstrap.sh…"
  ./bootstrap.sh || true
fi

if [[ ! -f configure ]]; then
  echo "▶ Running autoreconf…"
  autoreconf -fi
fi

# 6) Configure to output into ./build (prefix -> build to keep paths self-contained)
cd "$BUILD_DIR"
"$PROJECT_ROOT/configure" --prefix="$BUILD_DIR" || {
  echo "✖ configure failed. See: $BUILD_DIR/config.log"
  exit 1
}

# 7) Build
JOBS="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)"
echo "▶ Building with $JOBS jobs…"
make -j"$JOBS"

# 8) Tests (non-fatal but reported)
echo "▶ Running tests (make check)…"
set +e
TEST_VERBOSE=1 make -k check
TEST_STATUS=$?
set -e

if [[ "$TEST_STATUS" -eq 0 ]]; then
  echo "✅ Tests passed."
else
  echo "⚠ Some tests failed (exit $TEST_STATUS). Check logs under $BUILD_DIR (look for .log / .trs)."
fi

# 9) Run hints
echo
echo "✅ Build complete."
echo
echo "Run in SLAVE-ONLY with max debug + CSV stats (replace en5 with your iface):"
echo "  sudo $BUILD_DIR/src/ptpd2 -s -D -D -D -i en5 \\"
echo "       --global:log_file=$BUILD_DIR/ptpd.log \\"
echo "       --global:statistics_file=$BUILD_DIR/ptpd-stats.csv"
echo
echo "Notes:"
echo "  - -s/--slaveonly is the modern flag (old compat is -g)."
echo "  - -D -D -D gives maximum runtime debug (needs RUNTIME_DEBUG at compile)."
echo "  - Add -n / --clock:no_adjust to observe without touching systime."

