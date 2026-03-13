# Using ptpd as a Library in Third-Party Projects

This document describes how to integrate ptpd into a third-party project as a
library, how to configure the build, and how to tune PTP protocol settings for
common deployment scenarios.

---

## Table of Contents

1. [Overview](#overview)
2. [Build Integration](#build-integration)
   - [CMake Build Options](#cmake-build-options)
   - [Embedding with add_subdirectory](#embedding-with-add_subdirectory)
   - [Linking a Pre-Built Library](#linking-a-pre-built-library)
3. [Library API](#library-api)
   - [Initialisation](#initialisation)
   - [Starting and Stopping](#starting-and-stopping)
   - [Reading Time](#reading-time)
   - [iOS Log Callback](#ios-log-callback)
4. [Minimal Integration Example](#minimal-integration-example)
5. [PTP Configuration](#ptp-configuration)
   - [Passing Configuration to the Library](#passing-configuration-to-the-library)
   - [Configuration File Format](#configuration-file-format)
   - [Essential Settings (ptpengine)](#essential-settings-ptpengine)
   - [Clock Settings (clock)](#clock-settings-clock)
   - [Servo Settings (servo)](#servo-settings-servo)
   - [Global / Logging Settings (global)](#global--logging-settings-global)
   - [NTP Engine Settings (ntpengine)](#ntp-engine-settings-ntpengine)
6. [Common Configuration Presets](#common-configuration-presets)
   - [Slave-Only (most common)](#slave-only-most-common)
   - [Master-Only](#master-only)
   - [Full IEEE 1588 (Master/Slave)](#full-ieee-1588-masterslave)
7. [Lock File Behaviour](#lock-file-behaviour)
8. [Software Clock Backend (swclock)](#software-clock-backend-swclock)

---

## Overview

ptpd can be built either as a standalone daemon (`ptpd2`) or as a static/shared
library that is embedded inside another application.  In library mode the entire
PTP protocol engine runs in a background thread so it never blocks the calling
thread.  The public API is declared in [`src/ptpdlib.h`](src/ptpdlib.h).

---

## Build Integration

### CMake Build Options

The table below lists all CMake options that affect the build output.  All are
passed with `-D<OPTION>=<VALUE>` on the `cmake` command line.

| Option | Default | Description |
|--------|---------|-------------|
| `BUILD_PTPD_LIBRARY` | `OFF` | Build ptpd as a static/shared library in addition to the executable |
| `BUILD_WITH_SWCLOCK` | `ON` | Link against the swclock software-clock backend |
| `ENABLE_STATISTICS` | `ON` | Include realtime statistics and outlier-filter code |
| `ENABLE_SLAVE_ONLY` | `ON` | Compile slave-only build (no master capability) |
| `ENABLE_PCAP` | auto | Enable libpcap for raw-socket packet capture |
| `ENABLE_SNMP` | `OFF` | Enable Net-SNMP management interface |
| `ENABLE_POSIX_TIMERS` | auto | Use POSIX timers instead of `setitimer` |
| `ENABLE_DAEMON` | `OFF` | Support `fork()`-based daemonisation |
| `ENABLE_ROOT_CHECK` | `OFF` | Abort at startup if not running as root |
| `ENABLE_EXPERIMENTAL` | `OFF` | Expose experimental configuration options |
| `ENABLE_RUNTIME_DEBUG` | auto | Enable runtime-selectable debug messages |
| `DEBUG_LEVEL` | auto | Compile-time debug verbosity: `none`, `basic`, `medium`, `all` |
| `ENABLE_SO_TIMESTAMPING` | `ON` (Linux) | Use `SO_TIMESTAMPING` for hardware timestamps |
| `MAX_UNICAST_DESTINATIONS` | `128` | Maximum unicast destination table size (16–2048) |

To activate library mode, define `PTPD_LIBRARY_MODE` as a C preprocessor flag.
The `src/CMakeLists.txt` detects this and builds a static library target named
`ptpd2` instead of an executable:

```cmake
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DPTPD_LIBRARY_MODE")
```

Alternatively, enable `BUILD_PTPD_LIBRARY` at the top-level which builds both
the daemon and the library targets:

```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_PTPD_LIBRARY=ON \
  -DBUILD_WITH_SWCLOCK=ON
cmake --build build
```

This produces:
- `build-cmake/macos-ptpd-app-debug/src-app/ptpd-app` — example application using the library API

> Note: In library mode (`BUILD_PTPD_LIBRARY=ON`) there is no standalone `ptpd2` daemon.
> The `ptpd-app` binary exercises the full public API (`ptpd_init` / `ptpd_start` / `ptpd_shutdown`).

### Embedding with add_subdirectory

Place (or clone) this repository alongside your project and add it as a
subdirectory:

```cmake
# In your top-level CMakeLists.txt
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DPTPD_LIBRARY_MODE")
set(BUILD_WITH_SWCLOCK ON CACHE BOOL "" FORCE)

add_subdirectory(ptpd)

target_link_libraries(your_app PRIVATE ptpd2)
target_include_directories(your_app PRIVATE
    ptpd/src
    ${CMAKE_BINARY_DIR}/ptpd   # for generated config.h
)
```

### Linking a Pre-Built Library

If you build the library separately:

```bash
cmake -B ptpd/build \
  -DCMAKE_C_FLAGS="-DPTPD_LIBRARY_MODE=1" \
  -DBUILD_WITH_SWCLOCK=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build ptpd/build
```

Then in your project:

```cmake
target_include_directories(your_app PRIVATE ptpd/src ptpd/build)
target_link_libraries(your_app PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/ptpd/build/src/libptpd2.a
    m       # math
    pthread
)
```

---

## Library API

Include the public header:

```c
#include "ptpdlib.h"
```

All types and functions are declared in [`src/ptpdlib.h`](src/ptpdlib.h).

### Initialisation

```c
PtpClock *ptpd_init(int argc, char **argv, Integer16 *ret);
```

Parses command-line arguments (or a config file passed via `-c`), allocates and
initialises all internal state, and returns a `PtpClock` handle.  The protocol
does **not** start yet.  Returns `NULL` on failure; `*ret` is set to a non-zero
error code.

### Starting and Stopping

```c
int  ptpd_start(PtpClock *ptpClock);   // 0 = OK, -1 = error
int  ptpd_is_running(PtpClock *ptpClock); // 1 = running, 0 = stopped
void ptpd_shutdown(PtpClock *ptpClock);
```

`ptpd_start()` launches the PTP protocol engine in a new background thread and
returns immediately.  `ptpd_shutdown()` signals the thread to stop, waits for
it to terminate, and frees all resources.  After `ptpd_shutdown()` the
`PtpClock` pointer is invalid.

### Reading Time

```c
int ptpd_gettime(PtpClock *ptpClock, clockid_t clk_id, struct timespec *tp);
```

Returns the time from the clock backend that ptpd is disciplining.  When built
with `BUILD_WITH_SWCLOCK=ON` this queries the software clock servo directly;
otherwise it falls through to `clock_gettime()`.  Use this instead of
`clock_gettime()` so your application always reads the PTP-corrected time.

Supported `clk_id` values: `CLOCK_REALTIME`, `CLOCK_MONOTONIC`,
`CLOCK_MONOTONIC_RAW`.

### iOS Log Callback

When built with `PTPD_IOS` defined, register a C callback to receive log
messages:

```c
void ptpd_set_log_callback(void (*callback)(const char *message, int priority));
```

The callback is invoked from the PTP daemon thread; copy the message and
dispatch to the main thread for any UI updates.

---

## Minimal Integration Example

The reference application in [`src-app/macos/ptpd-app.c`](src-app/macos/ptpd-app.c)
demonstrates the full lifecycle:

```c
#ifdef HAVE_CONFIG_H
# include <config.h>
#endif
#include "ptpdlib.h"
#include <signal.h>
#include <unistd.h>

static PtpClock *g_ptp = NULL;

void signal_handler(int sig) {
    if (g_ptp) { ptpd_shutdown(g_ptp); g_ptp = NULL; }
    exit(0);
}

int main(int argc, char **argv) {
    Integer16 ret;

    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);

    /* Initialise — same args as ptpd2 command line */
    g_ptp = ptpd_init(argc, argv, &ret);
    if (!g_ptp) return ret;

    /* Start protocol in background thread */
    if (ptpd_start(g_ptp) != 0) return -1;

    /* Wait; optionally poll ptpd_gettime() here */
    while (ptpd_is_running(g_ptp)) {
        struct timespec ts;
        ptpd_gettime(g_ptp, CLOCK_REALTIME, &ts);
        sleep(1);
    }

    ptpd_shutdown(g_ptp);
    return 0;
}
```

Compile and run:

```bash
# Pass config file just like the standalone daemon
./ptpd-app -c /etc/ptpd2.conf
# Or pass individual settings inline
./ptpd-app --ptpengine:interface=eth0 --ptpengine:preset=slaveonly \
           --global:ignore_lock=y
```

---

## PTP Configuration

### Passing Configuration to the Library

Configuration is passed through `argc`/`argv` exactly as it would be on the
`ptpd2` command line.  Two main approaches:

**1. Config file** (recommended):

```c
char *args[] = { "ptpd", "-c", "/path/to/ptpd.conf", NULL };
PtpClock *ptp = ptpd_init(3, args, &ret);
```

**2. Inline key=value arguments**:

```c
char *args[] = {
    "ptpd",
    "--ptpengine:interface=eth0",
    "--ptpengine:preset=slaveonly",
    "--global:ignore_lock=y",
    NULL
};
PtpClock *ptp = ptpd_init(4, args, &ret);
```

Both can be combined; inline arguments always take priority over the file.

### Configuration File Format

Settings follow the pattern `section:key = value`.  The file must end with a
newline.  Comments start with `;`.  Alternatively, `.ini`-style `[section]`
headers with `key = value` lines are also accepted.

```ini
; Minimal slave-only configuration
ptpengine:interface     = eth0
ptpengine:preset        = slaveonly
ptpengine:ip_mode       = multicast
ptpengine:domain        = 0

global:log_file         = /var/log/ptpd2.log
global:ignore_lock      = y
```

### Essential Settings (ptpengine)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ptpengine:interface` | string | _(required)_ | Network interface (e.g. `eth0`) |
| `ptpengine:preset` | enum | `slaveonly` | Operating mode: `slaveonly`, `masteronly`, `masterslave`, `none` |
| `ptpengine:transport` | enum | `ipv4` | `ipv4` or `ethernet` (ethernet requires libpcap) |
| `ptpengine:ip_mode` | enum | `multicast` | `multicast`, `unicast`, or `hybrid` |
| `ptpengine:domain` | int | `0` | PTP domain number (0–127) |
| `ptpengine:delay_mechanism` | enum | `E2E` | `E2E`, `P2P`, or `DELAY_DISABLED` |
| `ptpengine:slave_only` | bool | `Y` | Lock to slave state (clock class 255) |
| `ptpengine:use_libpcap` | bool | `N` | Use libpcap instead of UDP sockets |
| `ptpengine:unicast_destinations` | string | — | Comma-separated IPs for unicast mode |
| `ptpengine:log_sync_interval` | int | `0` | Sync rate as log₂ seconds (−1=2/s, 0=1/s, 1=0.5/s) |
| `ptpengine:log_delayreq_interval` | int | `0` | Delay-request rate (same log₂ encoding) |
| `ptpengine:log_announce_interval` | int | `1` | Announce rate (log₂ seconds) |
| `ptpengine:announce_receipt_timeout` | int | `6` | Announce timeouts before GM change |
| `ptpengine:inbound_latency` | int | `0` | Fixed ingress latency correction (ns) |
| `ptpengine:outbound_latency` | int | `0` | Fixed egress latency correction (ns) |
| `ptpengine:offset_shift` | int | `0` | Arbitrary offset correction applied to slave (ns) |
| `ptpengine:backup_interface` | string | — | Secondary network interface for GM failover |
| `ptpengine:always_respect_utc_offset` | bool | `Y` | Accept UTC offset even when `currentUtcOffsetValid=FALSE` |
| `ptpengine:disable_udp_checksums` | bool | `Y` | Disable UDP checksum on Linux (for transparent-clock workarounds) |
| `ptpengine:port_number` | int | `1` | PTP port number in clock identity |

### Clock Settings (clock)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `clock:no_adjust` | bool | `N` | Disable all clock adjustments (monitor-only) |
| `clock:no_reset` | bool | `N` | Disallow hard clock steps; only allow slewing |
| `clock:step_limit` | int | `1000000000` | Maximum single-step correction in nanoseconds |
| `clock:panic_mode` | bool | `N` | Enter panic mode on large offset |
| `clock:panic_mode_duration` | int | `30` | Seconds to stay in panic mode |
| `clock:leap_second_handling` | enum | `accept` | `accept`, `ignore`, `smear`, `step` |

### Servo Settings (servo)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `servo:kp` | float | `0.1` | Proportional gain of the PI servo |
| `servo:ki` | float | `0.001` | Integral gain of the PI servo |
| `servo:max_delay` | int | `0` | Discard sync if one-way delay exceeds this (ns, 0=disabled) |
| `servo:max_offset` | int | `0` | Discard sync if offset exceeds this (ns, 0=disabled) |
| `servo:adev_locked_threshold` | float | — | Allan deviation threshold to declare clock locked |

### Global / Logging Settings (global)

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `global:ignore_lock` | bool | `N` | **Skip lock file checking and locking entirely** |
| `global:lock_file` | string | auto | Explicit path to lock file |
| `global:auto_lockfile` | bool | `N` | Use mode- and interface-specific lock file name |
| `global:lock_directory` | string | `/var/run` | Directory for lock files |
| `global:log_file` | string | — | Path to event log file |
| `global:statistics_file` | string | — | Path to timing statistics log |
| `global:status_file` | string | — | Path to runtime status file |
| `global:log_status` | bool | `N` | Write a status file |
| `global:use_syslog` | bool | `N` | Send log messages to syslog |
| `global:verbose_foreground` | bool | `N` | Log to stdout when running in the foreground |
| `global:log_level` | enum | `info` | `err`, `warning`, `notice`, `info`, `debug` |
| `global:cpuaffinity` | int | `-1` | Pin daemon thread to a CPU core (−1=disabled) |
| `global:config_templates` | string | — | Comma-separated list of named built-in templates to apply |

### NTP Engine Settings (ntpengine)

ptpd can optionally communicate with a local `ntpd` instance to query its
state or switch it off when PTP is available.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ntpengine:enable` | bool | `N` | Enable NTP engine |
| `ntpengine:control_enabled` | bool | `N` | Allow ptpd to control ntpd (stop/start) |
| `ntpengine:check_interval` | int | `15` | Seconds between NTP status checks |
| `ntpengine:key_id` | int | `0` | NTP control key ID |
| `ntpengine:key_value` | string | — | NTP control key value |

---

## Common Configuration Presets

### Slave-Only (most common)

```ini
ptpengine:interface         = eth0
ptpengine:preset            = slaveonly
ptpengine:ip_mode           = multicast
ptpengine:domain            = 0
ptpengine:delay_mechanism   = E2E

global:ignore_lock          = y
global:log_file             = /var/log/ptpd2.log
global:log_status           = y
```

For unicast-only networks replace `ip_mode` and add destinations:

```ini
ptpengine:ip_mode               = unicast
ptpengine:unicast_destinations  = 192.168.1.1
```

### Master-Only

```ini
ptpengine:interface         = eth0
ptpengine:preset            = masteronly
ptpengine:ip_mode           = multicast
ptpengine:domain            = 0

global:ignore_lock          = y
```

### Full IEEE 1588 (Master/Slave)

```ini
ptpengine:interface         = eth0
ptpengine:preset            = masterslave
ptpengine:ip_mode           = multicast
ptpengine:domain            = 0
ptpengine:delay_mechanism   = E2E

global:ignore_lock          = y
global:log_file             = /var/log/ptpd2.log
```

---

## Lock File Behaviour

By default ptpd writes a lock file (`/var/run/ptpd.lock`) and refuses to start
if one already exists.  In embedded or multi-instance deployments this is often
undesirable.  The three options available are:

| Option | Effect |
|--------|--------|
| `global:ignore_lock = y` | Skip all lock-file checks and creation |
| `global:lock_file = /tmp/my.lock` | Use a custom path for the lock file |
| `global:auto_lockfile = y` | Generate a mode- and interface-specific name, overriding `lock_file` |

For library use, the simplest approach is always:

```ini
global:ignore_lock = y
```

or on the command line:

```
--global:ignore_lock=y
```

---

## Software Clock Backend (swclock)

When `BUILD_WITH_SWCLOCK=ON` (the default), ptpd disciplines a software clock
implemented in [`libraries/swclock`](libraries/swclock/) rather than adjusting
the system clock directly.  This is the preferred mode for embedded and
application-level integration because:

- The host system clock is never modified.
- The disciplined time is accessible only through `ptpd_gettime()`.
- Multiple PTP instances can run concurrently with independent clocks.

To disable this and have ptpd adjust the system clock directly:

```bash
cmake -B build -DBUILD_WITH_SWCLOCK=OFF
```

See [`libraries/swclock/README.md`](libraries/swclock/README.md) and
[`libraries/swclock/INTEGRATION.txt`](libraries/swclock/INTEGRATION.txt) for
further details on the software clock internals.

---

## Test Runner: ptp-app-run.sh

[`scripts/testing/ptp-app-run.sh`](scripts/testing/ptp-app-run.sh) is a
self-contained test runner that launches either `ptpd2` or `ptpd-app`, captures
PTP traffic, monitors synchronisation in real time, and produces an analysis
report when the run finishes.

### Usage

```bash
bash scripts/testing/ptp-app-run.sh <interface> <config_file> [options]
```

| Argument / Option | Description |
|---|---|
| `interface` | Network interface to use (e.g. `en0`, `en5`) — **required** |
| `config_file` | Path to a ptpd `.conf` file — **required** |
| `-b`, `--binary` | Binary to run: `ptpd2` (default) or `ptpd-app` |
| `-d`, `--duration` | Run duration in seconds (default: 60) |
| `-v`, `--verbose` | Enable verbose output |
| `-h`, `--help` | Show usage |

**Examples:**

```bash
# Run the standalone daemon for 60 s on en5
bash scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf

# Run the library-based app for 30 s
bash scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf -b ptpd-app -d 30

# Run on a different interface
bash scripts/testing/ptp-app-run.sh en0 resources/ptpd-daemon.conf -b ptpd-app -d 120
```

### What the Script Does (Step by Step)

#### 1. Argument Parsing
Validates the interface name and config file path, resolves the binary path
under `build-cmake/macos-ptpd-app-debug/src-app/` (for `ptpd-app`),
and rejects unknown options early.

#### 2. Stopping Stale Instances (`stop_ptpd_processes`)
Before starting, the script performs a thorough cleanup:
- Stops any Homebrew-managed ptpd services via `brew services stop`.
- Unloads any launchd jobs whose label matches `ptpd` in both the `system` and
  `gui/$UID` domains using `launchctl bootout`.
- Removes on-disk LaunchDaemon / LaunchAgent plist registrations.
- Sends `SIGTERM` (then `SIGKILL`) to any remaining processes matching
  `ptpd2`, `ptpd`, or `ptpd-app` by pattern.
- Removes stale lock/pid files from `/var/run`, `/tmp`, and Homebrew prefix
  directories.
- Force-kills any process still holding ports 319 or 320 via `lsof`.

#### 3. Output Setup (`setup_output`)
Creates a timestamped directory under `scripts/ptpd_logs/YYYYMMDD_HHMMSS/`
and sets paths for:
- `ptpd_daemon_<iface>.log` — daemon event log
- `ptpd_daemon_<iface>.csv` — timing statistics (one row per second)
- `ptp_<iface>.pcap` — raw packet capture

#### 4. Configuration Preparation (`setup_configuration`)
Resolves the config file path (absolute, `$PWD`-relative, or project-relative),
then:
1. Runs basic line-by-line syntax validation (checks `section:key = value`
   format, counts critical settings, warns on malformed lines).
2. Validates the config by running `sudo <binary> -c <file> -k` — ptpd's
   built-in check-and-exit mode — and fails if ptpd reports errors.
3. Copies the file to the output directory and appends runtime overrides:
   ```ini
   ptpengine:interface = <interface>
   global:log_file     = <output_dir>/ptpd_daemon_<iface>.log
   global:statistics_file = <output_dir>/ptpd_daemon_<iface>.csv
   global:statistics_update_interval = 1
   global:lock_directory = <output_dir>/locks
   ```

#### 5. Binary Launch (`run_binary`)
Runs the binary as root via `sudo` with the following fixed arguments:
```
-C                          # Foreground / no-fork mode
-c <prepared_config>        # Config file
-i <interface>              # Interface override
-D -D -D                    # Maximum debug verbosity (debug3)
```
Output is redirected to the log file. The script waits 2 seconds and checks
the process is still alive before continuing.

#### 6. Packet Capture
Starts `tcpdump` in the background capturing UDP ports 319 and 320 on the
selected interface, writing to the `.pcap` file.

#### 7. Live Monitoring (`monitor_sw_clock`)
Polls for the configured duration (1-second loop):
- Watches the statistics CSV for rows in slave state (`slv`) and extracts
  offset and path delay in microseconds.
- Scans the log file for master-detection and servo-activity keywords.
- Displays a single overwriting status line:
  ```
  [28s] State: slv | Offset: -575 μs | Delay: 139 μs | Master: ✅ | Sync: ✅
  ```

#### 8. Analysis (`analyze_results`)
After the run:
- **Traffic**: counts UDP 319/320 packets in the pcap.
- **Log summary**: counts sync, master, and servo-related log entries and shows
  the first matching lines.
- **Statistics summary**: reads the final CSV row in slave state, computes the
  offset in µs, and rates synchronisation quality:

  | Quality | Offset |
  |---|---|
  | Excellent | < 1 ms |
  | Good | < 10 ms |
  | Acceptable | < 100 ms |
  | Poor | > 100 ms |

- Runs `scripts/analysis/analyze_ptp.py` (if present) for detailed statistical
  analysis of the CSV.
- Runs `scripts/analysis/analyze_pcap.sh` (if present) for protocol-level
  packet analysis.

#### 9. Signal Handling / Cleanup
`SIGINT` and `SIGTERM` are trapped. On exit the script sends `SIGTERM` (then
`SIGKILL`) to the daemon and tcpdump, runs `stop_ptpd_processes` again, and
calls `analyze_results` before exiting — so Ctrl-C still produces a full
report.

### Binary Selection: `ptpd2` vs `ptpd-app`

| Binary | Source | Build preset |
|---|---|---|
| `ptpd-app` | `build-cmake/macos-ptpd-app-debug/src-app/ptpd-app` | `macos-ptpd-app-debug` |

`ptpd-app` exercises the public library API (`ptpd_init` / `ptpd_start` /
`ptpd_shutdown`) and is the correct target to test when validating library
integration. It produces identical protocol behaviour to `ptpd2`.
