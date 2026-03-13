# PTPd Configuration Reference

Complete technical reference for all PTPd configuration options.

**See also**: [BUILD.md](BUILD.md) for build instructions and examples.

## Overview

PTPd supports 14 major configuration options that control features, debug output, and build characteristics. This document provides detailed technical information about each option.

---

## Configuration Options

### 1. ENABLE_POSIX_TIMERS

**Default**: Auto-detected (ON if platform supports POSIX timers, OFF otherwise)

**CMake**: `-DENABLE_POSIX_TIMERS=ON` / `-DENABLE_POSIX_TIMERS=OFF`

#### Description
Controls which timer implementation is used for PTP event timing.

#### Technical Details

**When ON** (POSIX timers):
- **Define**: `PTP_PTIMERS` is set
- **Source**: Uses `src/dep/eventtimer_posix.c`
- **Functions**: `timer_create()`, `timer_settime()`, `timer_delete()`
- **Requirements**: Platform must support POSIX.1-2001 timers
- **Advantages**: Higher precision, better performance, nanosecond resolution

**When OFF** (Interval timers):
- **Define**: `PTP_PTIMERS` is NOT set
- **Source**: Uses `src/dep/eventtimer_itimer.c`
- **Functions**: `setitimer()`, `getitimer()`
- **Fallback**: Works on systems without POSIX timer support
- **Limitations**: Microsecond resolution only

#### Detection Logic
CMake checks for:
1. `HAVE_TIMER_CREATE` (timer_create function exists)
2. `HAVE_TIMER_SETTIME` (timer_settime function exists)
3. `HAVE_STRUCT_SIGEVENT` (struct sigevent exists)

If all three are present, `POSIX_TIMERS_SUPPORTED` is set to TRUE.

#### When to Use
- **Enable**: On Linux, modern BSD systems for best performance
- **Disable**: On older systems, embedded systems without POSIX timer support

#### Platform Behavior
- **Linux**: Usually ON by default
- **macOS**: **OFF** — detection checks for `POSIX_TIMERS_SUPPORTED` as a symbol in `unistd.h`, which macOS does not define, so auto-detection returns OFF
- **FreeBSD**: Usually ON
- **Embedded**: May need OFF

---

### 2. ENABLE_PCAP

**Default**: Auto-detected (ON if pcap-config found, OFF otherwise)

**CMake**: `-DENABLE_PCAP=ON` / `-DENABLE_PCAP=OFF`

#### Description
Enables packet capture library (libpcap) for low-level network access and timestamping.

#### Technical Details

**When ON**:
- **Define**: `PTPD_PCAP` is set
- **Sources**: PCAP-specific code in various files enabled
- **Libraries**: Links with libpcap (via pcap-config)
- **Capabilities**:
  - Raw socket access for 802.3 Ethernet frames
  - Hardware timestamping (if NIC supports it)
  - More precise packet transmission timing
  - BPF (Berkeley Packet Filter) support

**When OFF**:
- **Define**: `PTPD_PCAP` is NOT set
- **Fallback**: Uses standard BSD sockets (AF_INET/SOCK_DGRAM)
- **Limitations**:
  - No hardware timestamping
  - No raw Ethernet frame access
  - Higher latency
  - Software timestamping only

#### Code Paths Affected
Files with `#ifdef PTPD_PCAP`:
- `src/dep/net.c` - Network initialization
- `src/dep/startup.c` - Interface setup
- Various protocol handlers

#### When to Use
- **Enable**:
  - Need hardware timestamping
  - Precision-critical applications
  - 802.3 Ethernet transport
  - PTP over Layer 2
- **Disable**:
  - Minimal builds
  - Systems without libpcap
  - UDP-only deployments

#### Dependencies
- **Header**: `pcap/pcap.h` or `pcap.h`
- **Tool**: `pcap-config` (preferred) or libpcap directly
- **Libraries**: libpcap

---

### 3. ENABLE_SNMP

**Default**: OFF (must be explicitly enabled)

**CMake**: `-DENABLE_SNMP=ON`

#### Description
Enables SNMP (Simple Network Management Protocol) support for remote monitoring and management via MIB (Management Information Base).

#### Technical Details

**When ON**:
- **Define**: `PTPD_SNMP` is set
- **Source**: `src/dep/snmp.c` is compiled and linked
- **Libraries**: Links with Net-SNMP libraries:
  - libnetsnmpagent
  - libnetsnmpmibs
  - libnetsnmp
  - Plus dependencies (crypto, ssl, etc.)
- **MIB**: Implements PTPBASE-MIB (see doc/PTPBASE-MIB.txt)
- **Capabilities**:
  - Remote monitoring of PTP state
  - Statistics retrieval via SNMP
  - Integration with NMS (Network Management Systems)
  - SNMP traps for state changes

**When OFF**:
- **Define**: `PTPD_SNMP` is NOT set
- **Source**: `src/dep/snmp.c` is NOT compiled
- **No SNMP agent**: Cannot be monitored via SNMP

#### SNMP Objects Exposed
When enabled, exposes:
- PTP clock state
- Port state
- Parent clock information
- Time properties
- Performance statistics
- Port configuration

#### When to Use
- **Enable**:
  - Enterprise deployments
  - Need centralized monitoring
  - Integration with existing NMS
  - SNMP-based automation
- **Disable**:
  - Standalone deployments
  - Minimal builds
  - No SNMP infrastructure
  - Reduced binary size needed

#### Dependencies
- **Header**: `net-snmp/net-snmp-config.h`
- **Tool**: `net-snmp-config` (required)
- **Libraries**: Net-SNMP agent libraries

#### Notes
- Default is OFF because:
  - Adds significant binary size (~100K+)
  - Not needed in most deployments
  - Increases attack surface
  - Requires Net-SNMP runtime

---

### 4. ENABLE_STATISTICS

**Default**: ON

**CMake**: `-DENABLE_STATISTICS=ON` / `-DENABLE_STATISTICS=OFF`

#### Description
Enables statistical data collection and outlier filtering for PTP timing data.

#### Technical Details

**When ON**:
- **Define**: `PTPD_STATISTICS` is set
- **Sources**:
  - `src/dep/statistics.c` - Statistical calculations
  - `src/dep/outlierfilter.c` - Outlier detection and filtering
- **Capabilities**:
  - Mean, median, standard deviation calculation
  - Min/max tracking
  - Outlier filtering (removes anomalous samples)
  - Sliding window statistics
  - Export to statistics file

**When OFF**:
- **Define**: `PTPD_STATISTICS` is NOT set
- **Sources**: statistics.c and outlierfilter.c are NOT compiled
- **Behavior**: No statistical analysis, uses raw measurements
- **Binary Size**: Reduces binary by ~40K

#### Statistics Collected
When enabled:
- Offset from master statistics
- One-way delay statistics
- Path delay statistics
- Frequency adjustment statistics
- Packet timing statistics

#### Output Files
- Default: `/tmp/ptpd2.stats`
- Format: CSV-compatible
- Fields: timestamp, offset, delay, drift, etc.

#### When to Use
- **Enable**:
  - Performance analysis needed
  - Troubleshooting timing issues
  - Quality monitoring
  - Research/development
  - Production monitoring
- **Disable**:
  - Minimal memory footprint
  - No statistics file I/O
  - Embedded systems with limited storage
  - Reduced binary size

#### Performance Impact
- Minimal CPU overhead (~1-2%)
- Memory: ~10KB for statistics buffers
- I/O: Periodic writes to statistics file

---

### 5. DEBUG_LEVEL

**Default**: Auto-detected (all for Debug builds, none for Release)

**CMake**: `-DDEBUG_LEVEL=none|basic|medium|all`

#### Description
Compile-time debug output level. Mutually exclusive with ENABLE_RUNTIME_DEBUG.

**Build-Type Defaults**:
- Debug builds (`CMAKE_BUILD_TYPE=Debug`): `all` (all debug compiled in) — **unless `ENABLE_RUNTIME_DEBUG=ON` is also set, in which case it is silently forced to `none`**
- Release builds (`CMAKE_BUILD_TYPE=Release`): `none` (no debug overhead)

> **Warning**: The project's `scripts/build/config-cmake-debug.sh` explicitly sets both `-DENABLE_RUNTIME_DEBUG=ON` and `-DDEBUG_LEVEL=all`. The mutual exclusivity rule in `Options.cmake` means `ENABLE_RUNTIME_DEBUG` wins and `DEBUG_LEVEL` is silently reset to `none`. The effective debug build configuration therefore has `ENABLE_RUNTIME_DEBUG=ON` and `DEBUG_LEVEL=none`.

#### Technical Details

**Level: none**:
- No debug defines set
- Only ERROR and WARNING messages
- Minimal output
- Best for production

**Level: basic**:
- **Define**: `PTPD_DBG` is set
- **Output**: Basic debug messages
- **Functions**: `DBG()` macro active
- **Coverage**: Major events, state changes

**Level: medium**:
- **Defines**: `PTPD_DBG` and `PTPD_DBG2` are set
- **Output**: Detailed debug messages
- **Functions**: `DBG()` and `DBG2()` macros active
- **Coverage**: Packet processing, timing calculations

**Level: all**:
- **Defines**: `PTPD_DBG`, `PTPD_DBG2`, and `PTPD_DBGV` are set
- **Output**: Verbose debug messages
- **Functions**: All debug macros active
- **Coverage**: Everything including low-level details

#### Code Macros
```c
#ifdef PTPD_DBG
    DBG("Basic debug message\n");
#endif

#ifdef PTPD_DBG2
    DBG2("Detailed debug message\n");
#endif

#ifdef PTPD_DBGV
    DBGV("Verbose debug message\n");
#endif
```

#### Output Control
- Compile-time only (cannot be changed at runtime)
- Output goes to syslog and/or console
- Can be filtered by changing compile-time level

#### When to Use
- **none**: Production deployments
- **basic**: Initial troubleshooting, moderate detail
- **medium**: Deep troubleshooting, packet-level analysis
- **all**: Developer debugging, finding obscure bugs

#### Performance Impact
- **none**: No impact
- **basic**: ~1-2% CPU, moderate log volume
- **medium**: ~3-5% CPU, high log volume
- **all**: ~5-10% CPU, very high log volume (GB/day possible)

---

### 6. ENABLE_RUNTIME_DEBUG

**Default**: Auto-detected (OFF for Debug builds, ON for Release)

**CMake**: `-DENABLE_RUNTIME_DEBUG=ON` / `-DENABLE_RUNTIME_DEBUG=OFF`

#### Description
Enables runtime control of debug output levels. Mutually exclusive with DEBUG_LEVEL.

**Build-Type Defaults** (CMake logic):
- Debug builds (`CMAKE_BUILD_TYPE=Debug`): `OFF` (use compile-time DEBUG_LEVEL=all)
- Release builds (`CMAKE_BUILD_TYPE=Release`): `ON` (enable runtime control)

> **Note**: `scripts/build/config-cmake-debug.sh` explicitly overrides this to `ON` for the project's Debug build, which also overrides `DEBUG_LEVEL` to `none` via the mutual exclusivity rule. The actual macOS debug build runs with `ENABLE_RUNTIME_DEBUG=ON`.

#### Technical Details

**When ON**:
- **Define**: `RUNTIME_DEBUG` is set
- **All debug defines**: `PTPD_DBG`, `PTPD_DBG2`, `PTPD_DBGV` are set
- **Runtime control**: Can enable/disable debug levels via configuration file
- **Config options**:
  - `debug_level` parameter in config file
  - Can change without recompiling

**When OFF**:
- Debug level fixed at compile time (via DEBUG_LEVEL)
- No runtime control
- Slightly smaller binary
- Slightly better performance

#### Configuration File Control
When enabled, config file can set:
```
debug_level = 0    # No debug
debug_level = 1    # Basic (DBG)
debug_level = 2    # Medium (DBG + DBG2)
debug_level = 3    # Verbose (DBG + DBG2 + DBGV)
```

#### When to Use
- **Enable**:
  - Production/release builds (allows runtime troubleshooting)
  - Single binary for multiple scenarios
  - Field debugging without recompilation
- **Disable**:
  - Development builds (compile-time DEBUG_LEVEL=all preferred)
  - Fixed debug level sufficient
  - Minimal overhead needed

#### Trade-offs
- **Advantage**: Flexibility without recompiling
- **Disadvantage**: All debug code included (larger binary)

---

### 7. ENABLE_DAEMON

**Default**: OFF

**CMake**: `-DENABLE_DAEMON=ON` / `-DENABLE_DAEMON=OFF`

#### Description
Controls whether PTPd can run as a Unix daemon (background process).

#### Technical Details

**When ON**:
- **Define**: `PTPD_NO_DAEMON` is NOT set
- **Capabilities**:
  - `-b` flag allows background mode
  - Can fork() and detach from terminal
  - Can create PID file
  - Proper signal handling
  - Session leader creation

**When OFF**:
- **Define**: `PTPD_NO_DAEMON` is set
- **Behavior**: Always runs in foreground
- **Restrictions**:
  - `-b` flag has no effect
  - Cannot daemonize
  - Must run attached to terminal or supervisor

#### Daemon Features (when enabled)
- Fork to background
- Close stdin/stdout/stderr
- Create PID file (`/var/run/ptpd2.pid`)
- Signal handling (SIGTERM, SIGHUP, etc.)
- Session management

#### When to Use
- **Enable**:
  - Traditional Unix/Linux deployments
  - System service integration
  - Init scripts, systemd units
  - Production servers
- **Disable** (default):
  - Docker containers (foreground preferred)
  - Systemd with Type=simple
  - Debugging (easier in foreground)
  - Embedded systems with supervisors

#### SystemD Considerations
Modern systemd prefers foreground processes:
```ini
[Service]
Type=simple
ExecStart=/usr/sbin/ptpd2 -c /etc/ptpd2.conf
# No -b flag, runs in foreground
```

---

### 8. ENABLE_ROOT_CHECK

**Default**: OFF

**CMake**: `-DENABLE_ROOT_CHECK=ON` / `-DENABLE_ROOT_CHECK=OFF`

#### Description
Controls whether startup enforces root privileges.

#### Technical Details

**When ON**:
- **Define**: `PTPD_NO_ROOT_CHECK` is NOT set
- **Behavior**: Startup enforces root-only daemon startup checks

**When OFF** (default):
- **Define**: `PTPD_NO_ROOT_CHECK` is set
- **Behavior**: Root-check gate is disabled (useful for development and non-privileged runs)

#### When to Use
- **Enable**:
  - Locked-down production environments
  - Traditional root-managed deployments
- **Disable** (default):
  - Local development
  - Non-privileged test runs
  - Supervisor-managed foreground processes

---

### 9. ENABLE_SLAVE_ONLY

**Default**: ON (slave-only mode by default)

**CMake**: `-DENABLE_SLAVE_ONLY=ON` / `-DENABLE_SLAVE_ONLY=OFF`

#### Description
Builds a slave-only version that can never become a PTP master.

**Note**: As of this version, slave-only mode is the **default**. To enable master capability,
explicitly set `-DENABLE_SLAVE_ONLY=OFF`.

#### Technical Details

**When ON**:
- **Define**: `PTPD_SLAVE_ONLY` is set
- **Removed code**:
  - Master state machine
  - BMC (Best Master Clock) master path
  - Announce message generation
  - Master-only data structures
- **Forced behavior**: Always operates as slave
- **Binary size**: ~3-5K smaller
- **Version string**: Shows "ptpd2 version X.X.X-slaveonly"

**When OFF**:
- **Define**: `PTPD_SLAVE_ONLY` is NOT set
- **Full functionality**: Can be master or slave
- **BMC**: Participates in Best Master Clock algorithm
- **State machine**: Full PTP state machine

#### Code Exclusions
When slave-only, these are disabled:
- Master state transitions
- Announce message transmission
- Master clock quality announcements
- Grandmaster clock selection

#### When to Use
- **Enable**:
  - Dedicated slave devices (always synchronize to others)
  - Edge devices that should never be time source
  - Simplified deployment (no accidental master)
  - Regulatory/policy: device must not provide time
  - Slightly smaller binary
- **Disable**:
  - Need full PTP functionality
  - Device might need to be master
  - Redundant master scenarios
  - Testing both roles

#### Notes
- Common in end devices (sensors, cameras, etc.)
- Prevents accidental promotion to master
- Simpler configuration (no master-related settings)

---

### 10. BUILD_WITH_SWCLOCK

**Default**: ON

**CMake**: `-DBUILD_WITH_SWCLOCK=ON` / `-DBUILD_WITH_SWCLOCK=OFF`

#### Description
Builds ptpd with the swclock software clock backend. The swclock library lives in `libraries/swclock/` as a git submodule. When enabled, ptpd uses swclock for clock management instead of calling system clock APIs directly.

> **Note**: `ENABLE_SW_CLOCK` is referenced in `cmake/README.md` examples but is **not** a real CMake option. The actual option is `BUILD_WITH_SWCLOCK`.

#### Technical Details

**When ON** (default):
- **Define**: `PTPD_USE_SWCLOCK` is set
- **Sources**: `libraries/swclock/` submodule is compiled and linked
- **Behavior**: Clock get/set/adj operations routed through swclock
- **Requirement**: `libraries/swclock/` git submodule must be initialized

**When OFF**:
- **Define**: `PTPD_USE_SWCLOCK` is NOT set
- **Sources**: swclock library is NOT compiled
- **Behavior**: Uses system clock APIs directly (clock_gettime, adjtime, etc.)

#### When to Use
- **Enable** (default): Normal builds — swclock provides a portable clock abstraction layer
- **Disable**: If the swclock submodule is not available or not desired

#### Submodule Requirement
```bash
git submodule update --init libraries/swclock
```
If `BUILD_WITH_SWCLOCK=ON` and the submodule is missing, CMake will halt with a fatal error.

---

### 11. ENABLE_SO_TIMESTAMPING

**Default**: ON (Linux only), N/A (other platforms)

**CMake**: `-DENABLE_SO_TIMESTAMPING=ON` / `-DENABLE_SO_TIMESTAMPING=OFF`

#### Description
Enables SO_TIMESTAMPING socket option on Linux for hardware/kernel timestamping.

#### Technical Details

**When ON** (Linux):
- **Define**: `PTPD_DISABLE_SOTIMESTAMPING` is NOT set
- **Enables**: SO_TIMESTAMPING socket option
- **Capabilities**:
  - Hardware TX/RX timestamps (if NIC supports)
  - Kernel software timestamps
  - Multiple timestamp types
  - Sub-microsecond precision
- **Requirements**:
  - Linux kernel 2.6.30+
  - `linux/net_tstamp.h` header
  - NIC with timestamping support (for HW timestamps)

**When OFF**:
- **Define**: `PTPD_DISABLE_SOTIMESTAMPING` is set
- **Fallback**: Uses regular socket timestamps (SO_TIMESTAMP)
- **Precision**: Limited to software timestamps

#### Hardware Timestamping
When NIC supports it:
- Timestamps taken at PHY layer
- Eliminates kernel/driver latency
- Nanosecond or better precision
- Both TX and RX timestamps
- Dramatically improves accuracy

#### Platform Support
- **Linux**: Full support (if kernel 2.6.30+)
- **macOS**: Not supported (ignored)
- **FreeBSD**: Limited support
- **Windows**: Not applicable

#### When to Use
- **Enable** (keep default ON):
  - Linux systems
  - Precision timing applications
  - Hardware with timestamping NICs
  - Sub-microsecond accuracy needed
- **Disable**:
  - Older kernels (<2.6.30)
  - Troubleshooting timestamp issues
  - Systems without proper kernel headers
  - Compatibility fallback

#### Checking NIC Support
```bash
# Check if NIC supports hardware timestamping
ethtool -T eth0
```

---

### 12. MAX_UNICAST_DESTINATIONS

**Default**: 128

**CMake**: `-DMAX_UNICAST_DESTINATIONS=N`

**Valid Range**: 16 to 2048

#### Description
Sets the maximum number of simultaneous unicast PTP clients (master → slave unicast).

#### Technical Details

- **Define**: `PTPD_UNICAST_MAX=N`
- **Usage**: Array size for unicast destination table
- **Memory**: ~200 bytes per destination
- **Total memory impact**: N × 200 bytes

#### Memory Calculations
```
N=128  (default): ~25 KB
N=512          : ~100 KB
N=2048         : ~400 KB
```

#### When to Use

**Default (128)**:
- Most deployments
- Small to medium scale
- Typical enterprise use

**Higher (512-2048)**:
- Large scale deployments
- Central time servers
- Many clients
- Service provider scenarios

**Lower (16-64)**:
- Embedded systems
- Memory-constrained devices
- Small deployments
- Edge devices

#### Validation
CMake validates range at configure time:
```cmake
if(MAX_UNICAST_DESTINATIONS LESS 16 OR
   MAX_UNICAST_DESTINATIONS GREATER 2048)
  message(FATAL_ERROR "Value must be between 16 and 2048")
endif()
```

#### Notes
- Only affects unicast mode (not multicast)
- Multicast has no such limit
- Each active destination consumes table entry
- Unused entries have negligible impact

---

### 13. BUILD_PTPD_LIBRARY

**Default**: OFF

**CMake**: `-DBUILD_PTPD_LIBRARY=ON` / `-DBUILD_PTPD_LIBRARY=OFF`

#### Description
Builds ptpd as a library (in addition to the executable), exposing a C API (`ptpd_init`, `ptpd_start`, `ptpd_shutdown`, etc.) for embedding ptpd into host applications. Required for running the GTest suite and for iOS/macOS app integration.

#### Technical Details

**When ON**:
- **Define**: `PTPD_LIBRARY_MODE` is set (via `CMAKE_C_FLAGS`)
- **Output**: `libptpd2.a` (static) alongside the `ptpd2` executable
- **API**: `ptpd_init()`, `ptpd_start()`, `ptpd_shutdown()`, `ptpd_gettime()` are compiled in
- **`main()`**: Excluded from the library via `#ifndef PTPD_LIBRARY_MODE`
- **Threading**: Library starts the protocol loop in a background pthread
- **Required for**: `BUILD_PTPD_TESTS=ON` (GTest suite)

**When OFF** (default):
- **Define**: `PTPD_LIBRARY_MODE` is NOT set
- **Output**: `ptpd2` executable only
- **API**: Library entry points not compiled in

#### When to Use
- **Enable**:
  - Embedding ptpd in another application (iOS app, macOS app, daemon wrapper)
  - Running the GTest integration tests
  - Any use of the C library API
- **Disable** (default):
  - Standalone daemon deployments
  - Minimal builds

#### Notes
- `PTPD_LIBRARY_MODE` must be set for **both** iOS and macOS builds that use the library API. It is not iOS-specific.
- The iOS simulator build passes this via `CMAKE_C_FLAGS=-DPTPD_IOS=1 -DPTPD_LIBRARY_MODE=1`.
- The macOS debug build enables it via `BUILD_PTPD_LIBRARY=ON` in CMakeCache.

---

### 14. ENABLE_EXPERIMENTAL

**Default**: OFF

**CMake**: `-DENABLE_EXPERIMENTAL=ON` / `-DENABLE_EXPERIMENTAL=OFF`

#### Description
Enables experimental and unstable features under development.

#### Technical Details

**When ON**:
- **Define**: `PTPD_EXPERIMENTAL` is set
- **Features**: Enables experimental code paths
- **Stability**: May be unstable or incomplete
- **Changes**: Features may change or be removed

**When OFF**:
- **Define**: `PTPD_EXPERIMENTAL` is NOT set
- **Stable**: Only production-ready features
- **Recommended**: For all production use

#### Current Experimental Features
(Check source code for current list)
- Experimental protocol extensions
- New algorithms under testing
- Performance optimizations being validated
- Features not yet standardized

#### When to Use
- **Enable**:
  - Development only
  - Testing new features
  - Contributing to development
  - Research purposes
- **Disable**:
  - Production systems
  - Stable deployments
  - All normal use

#### Warnings
- **NOT for production**
- **No stability guarantees**
- **May change without notice**
- **Could break compatibility**
- **Use at own risk**

---

## Configuration Combinations

### Common Scenarios

#### Production Server (Standard)
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_STATISTICS=ON
```
Features: All defaults, statistics enabled, optimized binary

#### Production Server (High Scale)
```bash
# CMake
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_STATISTICS=ON \
  -DMAX_UNICAST_DESTINATIONS=2048
```
Features: Support up to 2048 unicast clients

#### Minimal Embedded System
```bash
# CMake
cmake -B build -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DENABLE_PCAP=OFF \
  -DENABLE_STATISTICS=OFF \
  -DENABLE_SNMP=OFF \
  -DMAX_UNICAST_DESTINATIONS=16
```
Features: Smallest binary, basic functionality only

#### Development with Debug
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug \
  -DENABLE_STATISTICS=ON
```
Features: `DEBUG_LEVEL=all` by default (all debug macros compiled in), full symbols, statistics.

> **Note**: The project's `scripts/build/config-cmake-debug.sh` also passes `-DENABLE_RUNTIME_DEBUG=ON`, which silently overrides `DEBUG_LEVEL` to `none`. If you want compile-time `DEBUG_LEVEL=all`, do not pass `-DENABLE_RUNTIME_DEBUG=ON` alongside it.

#### Dedicated Slave Device
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_STATISTICS=ON
```
Features: Slave-only (default), optimized, statistics for monitoring

Note: ENABLE_SLAVE_ONLY is ON by default. To enable master capability:
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SLAVE_ONLY=OFF \
  -DENABLE_STATISTICS=ON
```

#### Enterprise with SNMP and Master Capability
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SNMP=ON \
  -DENABLE_SLAVE_ONLY=OFF \
  -DENABLE_STATISTICS=ON \
  -DMAX_UNICAST_DESTINATIONS=512
```
Features: SNMP monitoring, statistics, medium scale, master/slave modes

---

## Configuration File vs Build-Time Options

### Build-Time Options (This Document)
- Compiled into binary
- Cannot be changed without recompiling
- Affect code paths and binary size
- Examples: ENABLE_PCAP, ENABLE_SNMP, ENABLE_SLAVE_ONLY

### Runtime Configuration File
- `/etc/ptpd2.conf` or specified with `-c`
- Can be changed without recompiling
- Does not affect binary size
- Examples: interface, domain, priority1

### Relationship
Some options interact:
- **ENABLE_RUNTIME_DEBUG** allows `debug_level` in config file
- **ENABLE_DAEMON** enables `-b` flag and daemon config options
- **ENABLE_STATISTICS** enables statistics file configuration
- **MAX_UNICAST_DESTINATIONS** sets limit, config file specifies addresses

---

## Binary Size Impact

Approximate binary size impact of each option (on x86_64 Linux):

| Option | Enabled | Disabled | Delta |
|--------|---------|----------|-------|
| Base (minimal) | - | 280 KB | - |
| ENABLE_PCAP | 320 KB | 280 KB | +40 KB |
| ENABLE_SNMP | 420 KB | 320 KB | +100 KB |
| ENABLE_STATISTICS | 320 KB | 280 KB | +40 KB |
| DEBUG_LEVEL=all | 340 KB | 320 KB | +20 KB |
| ENABLE_RUNTIME_DEBUG | 340 KB | 320 KB | +20 KB |
| ENABLE_SW_CLOCK | 360 KB | 320 KB | +40 KB |
| Full featured | 460 KB | - | - |

Note: Sizes are approximate and vary by platform and compiler optimization.

---

## Testing Configurations

### Test Matrix
See [CONFIGURATION-MATRIX.txt](CONFIGURATION-MATRIX.txt) for the complete test matrix of 16 critical configurations.

### Automated Testing
```bash
# Test specific configuration
./scripts/test-config.sh 1   # Default
./scripts/test-config.sh 2   # Minimal
./scripts/test-config.sh 16  # Combined

# Test all configurations
./scripts/test-all-configs.sh
```

### Verification
All configurations tested and validated with CMake build system. See [PLAN.txt](PLAN.txt) for migration testing details.

---

## Quick Reference

### Option Summary Table

| Option | Default | CMake | Define | Impact |
|--------|---------|-------|--------|--------|
| POSIX Timers | Auto | `-DENABLE_POSIX_TIMERS=ON/OFF` | `PTP_PTIMERS` | Timer precision |
| PCAP | Auto | `-DENABLE_PCAP=ON/OFF` | `PTPD_PCAP` | HW timestamps |
| SNMP | OFF | `-DENABLE_SNMP=ON` | `PTPD_SNMP` | +100KB, monitoring |
| Statistics | ON | `-DENABLE_STATISTICS=ON/OFF` | `PTPD_STATISTICS` | Stats file |
| Debug Level | Debug:all<br>Release:none | `-DDEBUG_LEVEL=none/basic/medium/all` | `PTPD_DBG*` | Log volume |
| Runtime Debug | Debug:OFF<br>Release:ON | `-DENABLE_RUNTIME_DEBUG=ON/OFF` | `RUNTIME_DEBUG` | Debug flexibility |
| Daemon | OFF | `-DENABLE_DAEMON=ON/OFF` | `PTPD_NO_DAEMON` | Background mode |
| Root Check | OFF | `-DENABLE_ROOT_CHECK=ON/OFF` | `PTPD_NO_ROOT_CHECK` | Startup privilege gate |
| Slave Only | ON | `-DENABLE_SLAVE_ONLY=ON/OFF` | `PTPD_SLAVE_ONLY` | Role restriction |
| SW Clock | ON | `-DBUILD_WITH_SWCLOCK=ON/OFF` | `PTPD_USE_SWCLOCK` | swclock backend |
| SO_TIMESTAMPING | ON (Linux) | `-DENABLE_SO_TIMESTAMPING=ON/OFF` | `PTPD_DISABLE_*` | HW timestamps |
| Max Unicast | 128 | `-DMAX_UNICAST_DESTINATIONS=N` | `PTPD_UNICAST_MAX` | Scale limit |
| PTPD Library | OFF | `-DBUILD_PTPD_LIBRARY=ON/OFF` | `PTPD_LIBRARY_MODE` | Library API / embed |
| Experimental | OFF | `-DENABLE_EXPERIMENTAL=ON` | `PTPD_EXPERIMENTAL` | Unstable |

---

## See Also

- [BUILD.md](BUILD.md) - CMake build instructions
- [cmake/README.md](cmake/README.md) - CMake module documentation
- [DEVELOPMENT.md](DEVELOPMENT.md) - Development workflows
- [PLAN.txt](PLAN.txt) - CMake migration history
- Configuration file format: `man ptpd2.conf` or see `src/ptpd2.conf.default-full`

---

**Last Updated**: March 13, 2026
**Applies To**: PTPd 2.3.1, CMake 3.15+
