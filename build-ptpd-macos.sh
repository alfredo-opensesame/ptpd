#!/usr/bin/env bash
# build-ptpd-macos.sh
# Build PTPd from THIS ptpd/ tree into ./build on macOS (no install).
# Also runs `make check` (non-fatal).

set -euo pipefail

echo "▶ PTPd source : $PWD"
BUILD_DIR="$PWD/build"
echo "▶ Build folder: $BUILD_DIR"

# 1) Tooling checks
if ! xcode-select -p >/dev/null 2>&1; then
  echo "✖ Xcode Command Line Tools missing. Install with: xcode-select --install"
  exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "✖ Homebrew required. Install from https://brew.sh/"
  exit 1
fi
/Users/alfredo/Workspace/PTP-Implementation/ptpd/INSTALL

# 2) Deps
brew install autoconf automake libtool pkgconf openssl@3 || true

OPENSSL_PREFIX="$(brew --prefix openssl@3)"
export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$OPENSSL_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$OPENSSL_PREFIX/lib ${LDFLAGS:-}"

# 3) Fresh build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 4) Autotools bootstrap (only if needed)
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

# 5) Configure to output into ./build (prefix -> build to keep paths self-contained)
cd "$BUILD_DIR"
"$PWD/../configure" --prefix="$BUILD_DIR" --with-ssl="$OPENSSL_PREFIX" || {
  echo "✖ configure failed. See: $BUILD_DIR/config.log"
  exit 1
}

# 6) Build
JOBS="$(sysctl -n hw.physicalcpu 2>/dev/null || echo 4)"
echo "▶ Building with $JOBS jobs…"
make -j"$JOBS"

# 7) Tests (non-fatal but reported)
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

# 8) Done
echo "✅ Build complete."
echo "Run with:"
echo "  $BUILD_DIR/src/ptpd2 --help"
