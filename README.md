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

- **CMake** 3.15 or later
- **C Compiler** (GCC, Clang, MSVC)
- **libpcap** development files (optional but recommended)
- **Net-SNMP** development files (optional, for SNMP support)

Build Instructions
---

### Quick Start

```bash
# Configure and build (Release)
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Binary will be in: build/src/ptpd2

# Install (optional)
sudo cmake --install build --prefix /usr/local
```

### Configuration Options

Common configuration examples:

```bash
# Disable statistics (lower CPU/RAM usage)
cmake -B build -DENABLE_STATISTICS=OFF

# Build slave-only version
cmake -B build -DENABLE_SLAVE_ONLY=ON

# Enable runtime debug messages
cmake -B build -DENABLE_RUNTIME_DEBUG=ON

# Set debug level
cmake -B build -DDEBUG_LEVEL=all

# Multiple options
cmake -B build -DENABLE_SLAVE_ONLY=ON -DDEBUG_LEVEL=all
```

### Testing

```bash
# Run ptpd2 with test configuration
./build/src/ptpd2 -c resources/test/client-e2e-socket.conf

# Get help
./build/src/ptpd2 --help
./build/src/ptpd2 --long-help
```

Documentation
---

- **[BUILD.md](BUILD.md)** - Comprehensive build guide with all options
- **[CONFIGURATION.md](CONFIGURATION.md)** - Technical reference for all 12 configuration options
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Developer workflows and project structure
- **[PLAN.txt](PLAN.txt)** - CMake migration history and status

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

This is a macOS-focused fork of PTPd v2.3.x that has been migrated from GNU
Autotools to CMake. The migration includes comprehensive testing (16/16
configurations verified) and maintains binary equivalence with the original
autotools build system.

**Upstream PTPd:** https://github.com/ptpd/ptpd
