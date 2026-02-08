# PTPd Configuration Reference

Complete technical reference for all PTPd configuration options in both autotools and CMake build systems.

## Overview

PTPd supports 12 major configuration options that control features, debug output, and build characteristics. This document provides detailed technical information about each option.

---

## Configuration Options

### 1. ENABLE_POSIX_TIMERS

**Default**: Auto-detected (ON if platform supports POSIX timers, OFF otherwise)

**Autotools**: `--enable-posix-timers` / `--disable-posix-timers`  
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
- **macOS**: Usually ON (POSIX timers supported)
- **FreeBSD**: Usually ON
- **Embedded**: May need OFF

---

### 2. ENABLE_PCAP

**Default**: Auto-detected (ON if pcap-config found, OFF otherwise)

**Autotools**: `--enable-pcap` / `--disable-pcap`  
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

**Autotools**: `--enable-snmp`  
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

**Autotools**: `--enable-statistics` / `--disable-statistics`  
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

**Default**: none

**Autotools**: `--enable-debug-level=basic|medium|all`  
**CMake**: `-DDEBUG_LEVEL=basic|medium|all`

#### Description
Compile-time debug output level. Mutually exclusive with ENABLE_RUNTIME_DEBUG.

#### Technical Details

**Level: none** (default):
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

**Default**: OFF

**Autotools**: `--enable-runtime-debug`  
**CMake**: `-DENABLE_RUNTIME_DEBUG=ON`

#### Description
Enables runtime control of debug output levels. Mutually exclusive with DEBUG_LEVEL.

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
  - Development environments
  - Test environments
  - Flexible debugging needs
  - Single binary for multiple scenarios
- **Disable**:
  - Production (fixed debug level)
  - Minimal overhead
  - Fixed configuration deployments

#### Trade-offs
- **Advantage**: Flexibility without recompiling
- **Disadvantage**: All debug code included (larger binary)

---

### 7. ENABLE_DAEMON

**Default**: ON

**Autotools**: `--disable-daemon`  
**CMake**: `-DENABLE_DAEMON=OFF`

#### Description
Controls whether PTPd can run as a Unix daemon (background process).

#### Technical Details

**When ON** (default):
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
- **Enable** (keep default ON):
  - Traditional Unix/Linux deployments
  - System service integration
  - Init scripts, systemd units
  - Production servers
- **Disable**:
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

### 8. ENABLE_SLAVE_ONLY

**Default**: OFF

**Autotools**: `--enable-slave-only`  
**CMake**: `-DENABLE_SLAVE_ONLY=ON`

#### Description
Builds a slave-only version that can never become a PTP master.

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

### 9. ENABLE_SW_CLOCK

**Default**: OFF

**Autotools**: `--enable-sw-clock`  
**CMake**: `-DENABLE_SW_CLOCK=ON`

#### Description
Enables software clock simulation for testing without real hardware clock.

#### Technical Details

**When ON**:
- **Define**: `SW_CLOCK_ENABLED` is set
- **Sources**: All files in `src/dep/sw_clock/` are compiled:
  - `sw_clock.c` - Core software clock
  - `sw_clock_adj.c` - Clock adjustment simulation
  - `sw_clock_freq.c` - Frequency adjustment
  - `sw_clock_phase.c` - Phase adjustment
  - `sw_clock_sync.c` - Synchronization logic
  - `sw_clock_utils.c` - Utilities
- **Behavior**: Uses simulated clock instead of system clock
- **Purpose**: Testing, development, simulation

**When OFF**:
- **Define**: `SW_CLOCK_ENABLED` is NOT set
- **Sources**: sw_clock/* files are NOT compiled
- **Behavior**: Uses real system clock (clock_gettime, etc.)

#### Software Clock Features
- Independent time base
- Controllable drift
- Simulated adjustments
- No system clock impact
- Repeatable testing

#### When to Use
- **Enable**:
  - Testing PTP without hardware
  - Development and debugging
  - Simulation environments
  - CI/CD testing
  - Algorithm validation
  - Education/training
- **Disable**:
  - Production deployments
  - Real time synchronization
  - Hardware testing
  - All normal use cases

#### Warnings
- **NOT for production**: Software clock is for testing only
- **No real sync**: Does not actually synchronize system time
- **Testing only**: Results are simulated, not real-world

---

### 10. ENABLE_SO_TIMESTAMPING

**Default**: ON (Linux only), N/A (other platforms)

**Autotools**: `--disable-sotimestamping`  
**CMake**: `-DENABLE_SO_TIMESTAMPING=OFF`

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

### 11. MAX_UNICAST_DESTINATIONS

**Default**: 128

**Autotools**: `--with-max-unicast-destinations=N`  
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

### 12. ENABLE_EXPERIMENTAL

**Default**: OFF

**Autotools**: `--enable-experimental-options`  
**CMake**: `-DENABLE_EXPERIMENTAL=ON`

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
# Autotools
./configure --enable-statistics

# CMake
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
# CMake
cmake -B build -DCMAKE_BUILD_TYPE=Debug \
  -DENABLE_RUNTIME_DEBUG=ON \
  -DENABLE_STATISTICS=ON
```
Features: Runtime debug control, full symbols, statistics

#### Dedicated Slave Device
```bash
# CMake
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SLAVE_ONLY=ON \
  -DENABLE_STATISTICS=ON
```
Features: Slave-only, optimized, statistics for monitoring

#### Enterprise with SNMP
```bash
# CMake  
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SNMP=ON \
  -DENABLE_STATISTICS=ON \
  -DMAX_UNICAST_DESTINATIONS=512
```
Features: SNMP monitoring, statistics, medium scale

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
All configurations tested for binary equivalence between autotools and CMake builds. See [PLAN.txt](PLAN.txt) Phase 9 for detailed test results.

---

## Quick Reference

### Option Summary Table

| Option | Default | Autotools | CMake | Define | Impact |
|--------|---------|-----------|-------|--------|--------|
| POSIX Timers | Auto | `--enable-posix-timers` | `-DENABLE_POSIX_TIMERS=ON` | `PTP_PTIMERS` | Timer precision |
| PCAP | Auto | `--enable-pcap` | `-DENABLE_PCAP=ON` | `PTPD_PCAP` | HW timestamps |
| SNMP | OFF | `--enable-snmp` | `-DENABLE_SNMP=ON` | `PTPD_SNMP` | +100KB, monitoring |
| Statistics | ON | `--enable-statistics` | `-DENABLE_STATISTICS=ON` | `PTPD_STATISTICS` | Stats file |
| Debug Level | none | `--enable-debug-level=X` | `-DDEBUG_LEVEL=X` | `PTPD_DBG*` | Log volume |
| Runtime Debug | OFF | `--enable-runtime-debug` | `-DENABLE_RUNTIME_DEBUG=ON` | `RUNTIME_DEBUG` | Debug flexibility |
| Daemon | ON | `--disable-daemon` | `-DENABLE_DAEMON=OFF` | `PTPD_NO_DAEMON` | Background mode |
| Slave Only | OFF | `--enable-slave-only` | `-DENABLE_SLAVE_ONLY=ON` | `PTPD_SLAVE_ONLY` | Role restriction |
| SW Clock | OFF | `--enable-sw-clock` | `-DENABLE_SW_CLOCK=ON` | `SW_CLOCK_ENABLED` | Testing only |
| SO_TIMESTAMPING | ON | `--disable-sotimestamping` | `-DENABLE_SO_TIMESTAMPING=OFF` | `PTPD_DISABLE_*` | HW timestamps |
| Max Unicast | 128 | `--with-max-unicast-destinations=N` | `-DMAX_UNICAST_DESTINATIONS=N` | `PTPD_UNICAST_MAX` | Scale limit |
| Experimental | OFF | `--enable-experimental-options` | `-DENABLE_EXPERIMENTAL=ON` | `PTPD_EXPERIMENTAL` | Unstable |

---

## See Also

- [README.cmake.md](README.cmake.md) - CMake build instructions
- [cmake/README.md](cmake/README.md) - CMake module documentation  
- [CONFIGURATION-MATRIX.txt](CONFIGURATION-MATRIX.txt) - Test configuration matrix
- [PLAN.txt](PLAN.txt) - Migration plan and verification results
- Configuration file format: `man ptpd2.conf` or see `src/ptpd2.conf.default-full`

---

**Last Updated**: February 8, 2026  
**Applies To**: PTPd 2.3.1, CMake 3.15+, Autotools
