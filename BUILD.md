# PTPd CMake Build System

This document describes how to build PTPd using CMake and named presets.

## Status

The CMake build system is the **only** supported build system. Autotools has been removed. All 12 CMake presets build cleanly on macOS.

## Project Structure

```
src/                  - PTPd core source code
src-app/macos/        - macOS example application (ptpd-app)
src-app/ios/          - iOS SwiftUI application (PTPMonitor)
src-gtests/           - GTest integration tests
libraries/swclock/    - Software clock backend (git submodule)
CMakeLists.txt        - Root CMake build definition
CMakePresets.json     - All 12 named build presets
cmake/                - CMake modules (platform detection, options)
scripts/testing/      - Test runners (ptp-app-run.sh, ptp-ios-run.sh)
scripts/analysis/     - Post-run analysis tools
scripts/tools/        - Utilities (clean-ptpd.sh, compare-binaries.sh)
resources/            - Configuration templates
```

Build outputs (`build-cmake/<preset-name>/`):

| Preset | Description |
|--------|-------------|
| `macos-debug` / `macos-release` | macOS library (debug / release) |
| `ios-simulator-debug` / `ios-simulator-release` | iOS simulator library |
| `ios-debug` / `ios-release` | iOS device library |
| `macos-ptpd-app-debug` / `macos-ptpd-app-release` | macOS `ptpd-app` binary |
| `macos-gtest-debug` / `macos-gtest-release` | GTest suite |
| `iossim-ptpd-app-debug` / `iossim-ptpd-app-release` | iOS sim `PTPMonitor.app` |

## Prerequisites

- **CMake** 3.25 or later (required for preset support)
- **C Compiler** supporting C99 (GCC, Clang, MSVC)
- **libpcap** development files (optional but recommended)
  - macOS: Already available with Xcode Command Line Tools
  - Ubuntu/Debian: `apt-get install libpcap-dev`
  - RHEL/CentOS: `yum install libpcap-devel`
- **Net-SNMP** development files (optional)
  - macOS: Already available
  - Ubuntu/Debian: `apt-get install libsnmp-dev`
  - RHEL/CentOS: `yum install net-snmp-devel`

### Linux-Specific

On Linux, if you want to use SO_TIMESTAMPING features, you may need kernel headers:
- Ubuntu/Debian: `apt-get install linux-headers-$(uname -r)`
- RHEL/CentOS: `yum install kernel-devel`

## Quick Start

This project uses **CMake Presets** (CMake 3.25+ required). Use `cmake --preset`
instead of `-B`/`-D` flags directly.

### Library Build (macOS)

```bash
# Debug library (libptpd2.a + libswclock.a)
cmake --preset macos-debug
cmake --build --preset macos-debug

# Release library
cmake --preset macos-release
cmake --build --preset macos-release
```

### Application Build (macOS)

Consumer presets link against a pre-built library; build the library first.

```bash
# macOS example app
cmake --preset macos-ptpd-app-debug
cmake --build --preset macos-ptpd-app-debug
# Binary: build-cmake/macos-ptpd-app-debug/src-app/ptpd-app

# GTest suite
cmake --preset macos-gtest-debug
cmake --build --preset macos-gtest-debug
```

### iOS Simulator

```bash
cmake --preset ios-simulator-debug
cmake --build --preset ios-simulator-debug
cmake --preset iossim-ptpd-app-debug
cmake --build --preset iossim-ptpd-app-debug
# App bundle: build-cmake/iossim-ptpd-app-debug/src-app/ios/Debug-iphonesimulator/PTPMonitor.app
```

### Clean

```bash
# Via VS Code task "Clean", or:
rm -rf build-cmake compile_commands.json
```

## Build Types

CMake supports multiple build types:

- **Debug** (default): `-O0 -g` - Best for development and debugging
- **Release**: `-O2` - Optimized for performance, no debug symbols
- **RelWithDebInfo**: `-O2 -g` - Optimized with debug symbols (matches autotools debug build)
- **MinSizeRel**: `-Os` - Optimized for size

To specify:
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
```

## Configuration Options

All autotools configuration options have CMake equivalents. Options are specified with `-D` flag:

```bash
cmake -B build -DENABLE_SNMP=ON -DDEBUG_LEVEL=all
```

### Complete Option Reference

| Autotools Option | CMake Option | Default | Description |
|-----------------|--------------|---------|-------------|
| `--enable-posix-timers` | `ENABLE_POSIX_TIMERS=ON` | Auto-detected | Use POSIX timers (timer_create) |
| `--disable-posix-timers` | `ENABLE_POSIX_TIMERS=OFF` | | Use interval timers (setitimer) |
| `--enable-snmp` | `ENABLE_SNMP=ON` | OFF | Enable SNMP support |
| `--disable-snmp` | `ENABLE_SNMP=OFF` | | Disable SNMP support |
| `--enable-statistics` | `ENABLE_STATISTICS=ON` | ON | Enable statistics collection |
| `--disable-statistics` | `ENABLE_STATISTICS=OFF` | | Disable statistics |
| `--enable-runtime-debug` | `ENABLE_RUNTIME_DEBUG=ON` | OFF | Enable runtime debug control |
| `--enable-debug-level=basic` | `DEBUG_LEVEL=basic` | none | Compile-time debug: PTPD_DBG only |
| `--enable-debug-level=medium` | `DEBUG_LEVEL=medium` | none | Compile-time debug: DBG + DBG2 |
| `--enable-debug-level=all` | `DEBUG_LEVEL=all` | none | Compile-time debug: DBG + DBG2 + DBGV |
| `--enable-slave-only` | `ENABLE_SLAVE_ONLY=ON` | OFF | Build slave-only version |
| `--disable-daemon` | `ENABLE_DAEMON=OFF` | OFF | Disable daemon mode |
| N/A | `ENABLE_ROOT_CHECK=ON/OFF` | OFF | Require root privileges at startup |
| `--with-max-unicast-destinations=N` | `MAX_UNICAST_DESTINATIONS=N` | 128 | Max unicast destinations (16-2048) |
| `--enable-experimental-options` | `ENABLE_EXPERIMENTAL=ON` | OFF | Enable experimental features |
| `--enable-sw-clock` | `BUILD_WITH_SWCLOCK=ON` | ON | Enable software clock backend |
| `--disable-sotimestamping` | `ENABLE_SO_TIMESTAMPING=OFF` | ON (Linux) | Disable SO_TIMESTAMPING |

### Common Configuration Examples

#### 1. Default Configuration (Production)
```bash
cmake --preset macos-release
cmake --build --preset macos-release
```
Features: PCAP, statistics, POSIX timers (if available), swclock enabled

#### 2. Minimal Build
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_PCAP=OFF \
  -DENABLE_STATISTICS=OFF
cmake --build build
```
Smallest binary, basic PTP functionality only

#### 3. Development Build with Full Debug
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Debug \
  -DDEBUG_LEVEL=all
cmake --build build
```
All debug messages, no optimization

#### 4. Slave-Only Build
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SLAVE_ONLY=ON
cmake --build build
```
Only slave functionality (smaller binary)

#### 5. High-Scale Unicast
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DMAX_UNICAST_DESTINATIONS=2048
cmake --build build
```
Supports up to 2048 unicast destinations

#### 6. Combined Features
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_WITH_SWCLOCK=ON \
  -DENABLE_SLAVE_ONLY=ON \
  -DDEBUG_LEVEL=all \
  -DMAX_UNICAST_DESTINATIONS=512
cmake --build build
```
Multiple features enabled together

#### 7. SNMP-Enabled Build
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SNMP=ON
cmake --build build
```
Note: Requires Net-SNMP development files

## Platform-Specific Notes

### macOS

On macOS, CMake automatically uses Xcode Command Line Tools:
- Compiler: AppleClang
- PCAP: System libpcap
- Net-SNMP: System net-snmp (if enabled)

No special configuration needed for basic builds.

### Linux

#### Kernel Headers

CMake automatically detects kernel headers for SO_TIMESTAMPING support:
- Checks `/usr/src/linux-headers-$(uname -r)/include` (Debian/Ubuntu)
- Checks `/usr/src/kernels/$(uname -r)/include` (RHEL/CentOS)

If headers not found, SO_TIMESTAMPING features may be limited.

#### POSIX Timers

On Linux, POSIX timers are usually supported by default. If you experience issues:
```bash
cmake -B build -DENABLE_POSIX_TIMERS=OFF
```

This falls back to interval timers (setitimer).

### FreeBSD/Solaris

Not extensively tested yet, but should work with:
```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_POSIX_TIMERS=OFF
```

## Advanced Usage

### Out-of-Source Builds (Recommended)

CMake supports multiple build configurations simultaneously:

```bash
# Debug build
cmake -B build-debug -DCMAKE_BUILD_TYPE=Debug

# Release build
cmake -B build-release -DCMAKE_BUILD_TYPE=Release

# Minimal build
cmake -B build-minimal -DENABLE_STATISTICS=OFF -DENABLE_PCAP=OFF

# Build all
cmake --build build-debug
cmake --build build-release
cmake --build build-minimal
```

### Verbose Build Output

To see full compiler commands:
```bash
cmake --build build --verbose
```

Or:
```bash
cmake -B build -DCMAKE_VERBOSE_MAKEFILE=ON
cmake --build build
```

### Clean Build

```bash
# Remove build directory
rm -rf build

# Or clean and rebuild
cmake --build build --clean-first
```

### Specify Compiler

```bash
CC=gcc CXX=g++ cmake -B build
# or
CC=clang CXX=clang++ cmake -B build
```

### Cross-Compilation

CMake supports cross-compilation via toolchain files:
```bash
cmake -B build-arm \
  -DCMAKE_TOOLCHAIN_FILE=/path/to/arm-toolchain.cmake
cmake --build build-arm
```

## IDE Integration

### VS Code (Recommended for active development)

The `.vscode/tasks.json` includes 24 configure/build task pairs plus a Clean task.

**Build:**
1. Press `Cmd+Shift+B` → defaults to "Build macOS Debug"
2. Or: Terminal → Run Task → choose any of the 24 configure/build tasks
3. The "Configure macOS Debug" task auto-copies `compile_commands.json` to the workspace root for clangd/IntelliSense

**Test:**
```bash
# macOS app
./scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf -d 120

# iOS Simulator
./scripts/testing/ptp-ios-run.sh en5 192.168.68.114 -d 120
```
Logs are saved to `scripts/ptpd_logs/<timestamp>/`.

**Clean:** Run Task → "Clean" (removes all 12 `build-cmake/` directories)

### CLion

CLion has native CMake support:
1. Open the ptpd folder as a project
2. CLion automatically detects CMakeLists.txt
3. Configure options in Settings → Build → CMake
4. Use built-in build/run/debug tools

### Xcode

Generate Xcode project:
```bash
cmake -B build-xcode -G Xcode
open build-xcode/ptpd.xcodeproj
```

### Visual Studio

Generate Visual Studio solution:
```bash
cmake -B build-vs -G "Visual Studio 16 2019"
start build-vs/ptpd.sln
```

## Troubleshooting

### "Could not find PCAP"

Install libpcap development files or disable:
```bash
# Install (Ubuntu)
sudo apt-get install libpcap-dev

# Or disable PCAP
cmake -B build -DENABLE_PCAP=OFF
```

### "Could not find NETSNMP"

Net-SNMP is optional. Either install or disable:
```bash
# Install (Ubuntu)
sudo apt-get install libsnmp-dev

# SNMP is OFF by default, so just don't enable it
cmake -B build
```

### "POSIX timers not supported"

Fall back to interval timers:
```bash
cmake -B build -DENABLE_POSIX_TIMERS=OFF
```

### Binary Size Larger Than Expected

Use Release build for optimized size:
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
```

Or for minimum size:
```bash
cmake -B build -DCMAKE_BUILD_TYPE=MinSizeRel
```

### Compilation Errors with Kernel Headers (Linux)

If you see errors about missing Linux kernel headers:
```bash
# Install kernel headers
sudo apt-get install linux-headers-$(uname -r)  # Ubuntu/Debian
sudo yum install kernel-devel                   # RHEL/CentOS

# Or disable SO_TIMESTAMPING
cmake -B build -DENABLE_SO_TIMESTAMPING=OFF
```

### Symbol Count Differs Between Debug and Release

This is expected. Different build types produce different inlined/optimised symbols. As long as the functional interface is the same, this is not a problem.

### "config.h not found" During Build

If you see this error, ensure you ran cmake configuration first:
```bash
cmake -B build        # Must run this first to generate config.h
cmake --build build   # Then build
```

### Older CMake Version

If your system has CMake < 3.25 (required for preset support):
```bash
# macOS via Homebrew
brew install cmake
brew upgrade cmake
```

## Preset vs Manual CMake

Presets are the recommended approach — they encode all the right flags,
sysroot paths, and binaryDir conventions. For custom one-off builds you can
still pass flags directly, but the binaryDir won't match the preset convention.

### Preset workflow (recommended)
```bash
cmake --preset macos-debug
cmake --build --preset macos-debug
```

### Manual workflow (advanced)
```bash
cmake -B my-build \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_FLAGS="-DPTPD_LIBRARY_MODE=1" \
  -DENABLE_PCAP=ON \
  -DBUILD_WITH_SWCLOCK=ON
cmake --build my-build
```

### Key Differences

| Aspect | Preset (recommended) | Manual |
|--------|---------------------|--------|
| Configuration | `cmake --preset macos-debug` | `cmake -B my-build -DCMAKE_BUILD_TYPE=Debug ...` |
| Build | `cmake --build --preset macos-debug` | `cmake --build my-build` |
| Clean | VS Code "Clean" task or `rm -rf build-cmake` | `rm -rf my-build` |
| binaryDir | Fixed convention (`build-cmake/<name>/`) | User-defined |
| Platform settings | Encoded in preset (sysroot, arch) | Must be passed manually |
| IDE integration | Auto-discovered by VS Code / CLion | Requires manual configuration |

## Binary Comparison

```bash
# Build two variants and compare symbols
cmake --preset macos-debug && cmake --build --preset macos-debug
cmake --preset macos-release && cmake --build --preset macos-release

./scripts/tools/compare-binaries.sh \
  build-cmake/macos-debug/src/libptpd2.a \
  build-cmake/macos-release/src/libptpd2.a
```

The script compares:
- Binary size
- Global symbols
- Linked libraries
- Embedded strings
- Version information

## Configuration Files

Root:
- `ptpd.conf` — local dev config (gitignored; not committed)

`resources/`:
- `ptpd-daemon.conf` — unicast slave config (used by test scripts)
- `ptpd2.conf.default-full` — full annotated default config
- `ptpd2.conf.minimal` — minimal slave config
- `templates.conf` — config template reference
- `test/client-e2e-*.conf` — E2E test configurations
- `test/ptpd2-slave-sw-*.conf` — swclock test configs

## swclock Submodule

The software clock backend lives in `libraries/swclock/` as a git submodule.
After cloning, initialise it with:

```bash
git submodule update --init --recursive
```

`BUILD_WITH_SWCLOCK=ON` is the default for all presets and is required for
the iOS and macOS apps. The submodule is automatically built as part of the
library presets (`macos-debug`, `ios-simulator-debug`, etc.).

## Notes for Contributors

1. CMake 3.25+ is required (`CMakePresets.json` uses presets version 6).
2. Always build a library preset before its consumer preset:
   `cmake --preset macos-debug` before `cmake --preset macos-ptpd-app-debug`.
3. `compile_commands.json` at the workspace root is auto-generated by the
   "Configure macOS Debug" VS Code task — needed for clangd/IntelliSense.
4. Test logs in `scripts/ptpd_logs/` can be safely deleted; they are gitignored.

## Recent Changes

- Mar 2026: Added `CMakePresets.json` with 12 presets (6 library + 6 consumer)
- Mar 2026: Added `PTPD_PREBUILT_DIR` consumer mode to `CMakeLists.txt`
- Mar 2026: iOS PTPMonitor app: noAdjust flag, PTPManager/ContentView improvements
- Mar 2026: Added `ptp-ios-run.sh` test runner for iOS Simulator
- Mar 2026: Updated all test scripts for new preset-based build directories
- Mar 2026: Removed obsolete `scripts/build/` scripts (superseded by presets)
- Mar 2026: API anti-windup fix in swclock PI servo
- Mar 2026: clang-format (LLVM) applied to `src/`
- Feb 2026: Completed CMake migration, removed autotools
- Oct 2025: Added SW clock implementation (swclock submodule)

## Getting Help

- Check [CONFIGURATION.md](CONFIGURATION.md) for complete technical reference on all configuration options
- Check [cmake/README.md](cmake/README.md) for CMake module documentation
- Report issues on the project issue tracker

## See Also

- [README.md](README.md) - Project overview and quick start
- [CONFIGURATION.md](CONFIGURATION.md) - Technical reference for all configuration options
- [USAGE.md](USAGE.md) - Library integration guide and API reference

## Version

This documentation applies to:
- **PTPd Version**: 2.3.1 (6.6.6)
- **CMake Preset System**: Added March 2026 (12 presets)
- **CMake Minimum Version**: 3.25
- **Status**: Production-ready

Last Updated: March 2026
