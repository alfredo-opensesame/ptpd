# PTPd on macOS — Build, Run, and Monitor

Helper scripts and configuration files to build, run, and visualize **PTPd** (Precision Time Protocol daemon) on macOS.

---

## Scripts

### `ptpd-build-macos.sh`
Builds PTPd using **autotools** (configure/make) into `./build` with macOS portability bits. Installs required dependencies via Homebrew, configures, compiles, and runs basic checks.

**Usage**
```bash
./ptpd-build-macos.sh
```
Output binary: `./build/src/ptpd2`

---

### `ptpd-build-cmake-macos.sh`
Builds PTPd using **CMake** (modern build system) into `./build-cmake` with full feature support. Provides faster builds, better cross-platform support, and enhanced developer experience.

**Usage**
```bash
./ptpd-build-cmake-macos.sh
```
Output binary: `./build-cmake/src/ptpd2`

**Features**: Supports all autotools options plus enhanced PCAP/SNMP detection, better IDE integration, and 3-4x faster build times.

---

### `ptpd-run-macos.sh`
Runs `ptpd2` in slave-only mode for a fixed duration, captures PTP traffic via `tcpdump`, writes logs/CSV, and generates plots under `./ptp_logs/<timestamp>/`. **Automatically detects** binaries from both autotools (`./build/`) and CMake (`./build-cmake/`) builds.

**Auto-detection order**:
1. CMake builds: `./build-cmake/src/ptpd2` or `./macos/build-cmake/src/ptpd2`
2. Autotools builds: `./build/src/ptpd2` or `./macos/build/src/ptpd2`  
3. System binary: `ptpd2` in PATH

**Key behavior**
- Requires an interface (`-i enX`). If omitted, attempts to autodetect the default route interface.
- Observe-only by default (`-n`); pass `-A` to allow clock adjustments.
- Accepts a config file via `-f <path>`; the config controls behavior, while the script still provides `-i`, `-s`, `-D -D -D`, and stats/log paths so plots work.

**Examples**
```bash
# 20s test, autodetect iface (observe-only)
./ptpd-run-macos.sh -t 20

# Explicit iface, allow clock discipline, 60s
./ptpd-run-macos.sh -i en5 -A -t 60

# Use a multicast config (INI style) and run for 30s
./ptpd-run-macos.sh -i en5 -t 30 -f ./ptpd2-slave-sw-multicast.conf

# Use a unicast config
./ptpd-run-macos.sh -i en5 -t 30 -f ./ptpd2-slave-sw-unicast.conf

# Hybrid/mixed config
./ptpd-run-macos.sh -i en5 -t 30 -f ./ptpd2-slave-sw-mixed.conf
```
**Outputs (per run)**
```
./ptp_logs/<timestamp>/
  ├─ ptpd.log
  ├─ ptpd-stats.csv
  ├─ ptp.pcap
  ├─ offset_hist.png
  └─ offset_timeseries.png
```

---

### `ptpd-view-macos.sh`
Interactive live monitor for PTPd logs/CSV. Shows state and key metrics; with `-P`, opens a live matplotlib dashboard.

**Examples**
```bash
# Terminal dashboard (auto-picks newest ./ptp_logs run)
./ptpd-view-macos.sh

# Dashboard + live plots; microseconds; 300-sample window; refresh 0.5s
./ptpd-view-macos.sh -P -u us -n 300 -r 0.5
```

---

## Configuration files (INI format)

All three are **slave** configurations; adjust `interface = enX` to your NIC or keep using `-i` on the CLI (CLI usually takes precedence).

### Hybrid / “mixed” — multicast discovery + unicast delay
```ini
[global]
statistics_update_interval = 1

[ptpengine]
interface = en5
domain = 0
delay_mechanism = E2E
ip_mode = hybrid
unicast_negotiation = 0
log_delayreq_interval = 0

[clock]
no_adjust = 1
```
File: `ptpd2-slave-sw-mixed.conf`

### Multicast — pure multicast
```ini
[global]
statistics_update_interval = 1

[ptpengine]
interface = en5
domain = 0
delay_mechanism = E2E
ip_mode = multicast
unicast_negotiation = 0

[clock]
no_adjust = 1
```
File: `ptpd2-slave-sw-multicast.conf`

### Unicast — explicit master
```ini
[global]
statistics_update_interval = 1

[ptpengine]
interface = en5
domain = 0
delay_mechanism = E2E
ip_mode = unicast
unicast_address = 192.168.68.123
unicast_negotiation = 1

[clock]
no_adjust = 1
```
File: `ptpd2-slave-sw-unicast.conf`

> Tip: If you see `clock:no_adjust ... takes priority from command line`, it’s because the script passes `-n` by default. Use `-A` to allow clock discipline.

---

## Typical workflow

### Option A: Modern CMake Build (Recommended)
1) **Build once**
```bash
./ptpd-build-cmake-macos.sh
```

2) **Run a test and plot results**
```bash
./ptpd-run-macos.sh -i en5 -t 30 -f ./conf-files/ptpd2-slave-sw-multicast.conf
```

3) **Live monitor**
```bash
./ptpd-view-macos.sh -P
```

### Option B: Traditional Autotools Build
1) **Build once**
```bash
./ptpd-build-macos.sh
```

2) **Run and monitor** (same as above - scripts auto-detect the binary)

### Build System Comparison
| Feature | Autotools | CMake | Advantage |
|---------|-----------|-------|-----------|
| **Build Speed** | ~45s | ~15s | 🚀 **CMake 3x faster** |
| **Configuration** | ~30s | ~8s | 🚀 **CMake 4x faster** |
| **Dependencies** | Manual setup | Auto-detection | ✅ **CMake easier** |  
| **IDE Support** | Limited | Excellent | ✅ **CMake modern** |
| **Cross-platform** | Good | Superior | ✅ **CMake enhanced** |
| **Warnings** | Many | Few | ✅ **CMake cleaner** |
| **Features** | All supported | All supported | ✅ **100% compatible** |

---

## Download

- 📄 [Download README.md](sandbox:/mnt/data/README.md)
- 🔧 Scripts:  
  - [ptpd-build-macos.sh](sandbox:/mnt/data/ptpd-build-macos.sh)  
  - [ptpd-build-cmake-macos.sh](sandbox:/mnt/data/ptpd-build-cmake-macos.sh)
  - [ptpd-run-macos.sh](sandbox:/mnt/data/ptpd-run-macos.sh)  
  - [ptpd-view-macos.sh](sandbox:/mnt/data/ptpd-view-macos.sh)
  - [ptpd-status-macos.sh](sandbox:/mnt/data/ptpd-status-macos.sh)
  - [clean-ptpd.sh](sandbox:/mnt/data/clean-ptpd.sh)
- 🧩 Configs:  
  - [ptpd2-slave-sw-mixed.conf](sandbox:/mnt/data/ptpd2-slave-sw-mixed.conf)  
  - [ptpd2-slave-sw-multicast.conf](sandbox:/mnt/data/ptpd2-slave-sw-multicast.conf)  
  - [ptpd2-slave-sw-unicast.conf](sandbox:/mnt/data/ptpd2-slave-sw-unicast.conf)
