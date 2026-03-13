PTPd
===

PTP daemon (PTPd) is an implementation the Precision Time Protocol (PTP) version
2 as defined by 'IEEE Std 1588-2008'. PTP provides precise time coordination of
Ethernet LAN connected computers. It was designed primarily for instrumentation
and control systems.

Use
---

PTPd can coordinate the clocks of a group of LAN connected computers with each
other. It has been shown to achieve microsecond level coordination, even on
limited platforms.

The 'ptpd' program can be built from the included source code.  To use the
program, run 'ptpd' on a group of LAN connected computers. Compile with
'PTPD_DBG' defined and run with the '-C' or -V argument to watch what's going on.

If you are just looking for software to update the time on your desktop, you
probably want something that implements the Network Time Protocol. It can
coordinate computer clocks with an absolute time reference such as UTC.

Requirements
---

- **CMake** 3.25 or later (required for preset support)
- **C Compiler** (GCC, Clang)
- **libpcap** development files (macOS: bundled with Xcode CLI tools)
- **Net-SNMP** development files (optional, for SNMP support)

Build Instructions
---

This project uses **CMake Presets** (`CMakePresets.json`). All builds go through
a named preset rather than raw `-B`/`-D` flags.

### Quick Start (macOS)

```bash
# Library build (produces libptpd2.a + libswclock.a)
cmake --preset macos-debug
cmake --build --preset macos-debug

# Example application (links against the pre-built library)
cmake --preset macos-ptpd-app-debug
cmake --build --preset macos-ptpd-app-debug
# Binary: build-cmake/macos-ptpd-app-debug/src-app/ptpd-app

# Release
cmake --preset macos-release
cmake --build --preset macos-release
```

### Available Presets

| Preset | Output | Description |
|--------|--------|-------------|
| `macos-debug` | `build-cmake/macos-debug` | Library (debug) |
| `macos-release` | `build-cmake/macos-release` | Library (release) |
| `ios-simulator-debug` | `build-cmake/ios-simulator-debug` | iOS sim library (debug) |
| `ios-simulator-release` | `build-cmake/ios-simulator-release` | iOS sim library (release) |
| `ios-debug` | `build-cmake/ios-debug` | iOS device library (debug) |
| `ios-release` | `build-cmake/ios-release` | iOS device library (release) |
| `macos-ptpd-app-debug` | `build-cmake/macos-ptpd-app-debug` | macOS app (debug) |
| `macos-ptpd-app-release` | `build-cmake/macos-ptpd-app-release` | macOS app (release) |
| `macos-gtest-debug` | `build-cmake/macos-gtest-debug` | GTest suite (debug) |
| `macos-gtest-release` | `build-cmake/macos-gtest-release` | GTest suite (release) |
| `iossim-ptpd-app-debug` | `build-cmake/iossim-ptpd-app-debug` | iOS sim app (debug) |
| `iossim-ptpd-app-release` | `build-cmake/iossim-ptpd-app-release` | iOS sim app (release) |

### Testing

```bash
# Run the macOS library-based app
./scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf -d 120

# Run tests against iOS Simulator
./scripts/testing/ptp-ios-run.sh en5 192.168.68.114 -d 120

# Run GTest suite
cmake --preset macos-gtest-debug && cmake --build --preset macos-gtest-debug
```

Documentation
---

- **[BUILD.md](BUILD.md)** - Comprehensive build guide with all options
- **[CONFIGURATION.md](CONFIGURATION.md)** - Technical reference for all configuration options
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Developer workflows and project structure
- **[USAGE.md](USAGE.md)** - Library integration guide and API reference

Legal notice
---

PTPd was written by using only information contained within 'IEEE Std
1588-2008'. IEEE 1588 may contain patented technology, the use of which is not
under the control of the authors of PTPd. Users of IEEE 1588 may need to obtain
a license for the patented technology in the protocol. Contact the IEEE for
licensing information.

PTPd is licensed under a 2 Clause BSD Open Source License. Please refer to the
[COPYRIGHT](COPYRIGHT) file for additional information.

PTPd comes with absolutely no warranty.

About This Fork
---

This is a macOS/iOS-focused fork of PTPd v2.3.x. The project has been migrated
from GNU Autotools to CMake with preset-based builds, and extended with:
- A software clock backend (`swclock`) as a git submodule
- iOS app integration via the `ptpdlib` public API
- An example macOS application (`ptpd-app`)
- Full GTest suite

**Upstream PTPd:** https://github.com/ptpd/ptpd
