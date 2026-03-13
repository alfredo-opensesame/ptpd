================================================================================
                            PTPd Scripts Directory
================================================================================

This directory contains testing, analysis, and utility scripts for the PTPd
project. All scripts support the CMake preset-based build system.

================================================================================
                         RUNTIME TESTING SCRIPTS
================================================================================

All runtime testing scripts are located in scripts/testing/

ptp-app-run.sh
  Purpose:  Test runner for the macOS ptpd-app binary with full logging,
            packet capture, and post-run analysis
  Usage:    sudo ./scripts/testing/ptp-app-run.sh <interface> <config_file> [options]
  Options:  -b, --binary NAME   Binary name to use (default: ptpd-app)
            -d, --duration N    Run duration in seconds (default: 60)
            -v, --verbose       Enable verbose output
  Features: - Pre-flight config validation (-k check mode)
            - Kills any competing ptpd process before starting
            - Copies config file and appends runtime overrides
              (interface, log_file, statistics_file, lock_directory)
            - tcpdump packet capture on the specified interface
            - Timestamped output directory under scripts/ptpd_logs/
            - Post-run offset/drift statistics summary
  Example:  sudo ./scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf
            sudo ./scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf -d 120
  Notes:    - Default binary resolved from build-cmake/macos-ptpd-app-debug/
            - Requires root privileges (network timestamping, PCAP)

ptp-ios-run.sh
  Purpose:  Test runner for PTPMonitor on the iOS simulator — installs the
            app, launches it with auto-start launch arguments, collects logs
            and a host-side packet capture, and monitors PTP state live
  Usage:    ./scripts/testing/ptp-ios-run.sh <interface> <master_ip> [options]
  Options:  -u, --udid UDID     Simulator device UDID
                                (default: C3F3DBCE-2497-4117-94C7-5A2BCB89F1A9)
            -d, --duration N    Run duration in seconds (default: 60)
            -b, --build         Rebuild PTPMonitor.app before launching
            -v, --verbose       Verbose output
  Features: - Boots simulator if not already running
            - Installs PTPMonitor.app from iossim-ptpd-app-debug preset dir
            - Launches with -PTPAutoStart -PTPMasterIP -PTPInterface args
            - Tails simulator log for PTP state machine events
            - tcpdump capture on the host interface
            - Prints PTP_SLAVE lock time and offset summary
  Example:  ./scripts/testing/ptp-ios-run.sh en5 192.168.68.114
            ./scripts/testing/ptp-ios-run.sh en5 192.168.68.114 -d 120 --build
  Notes:    - Requires Xcode + Simulator runtime installed
            - App must be built first (cmake --build --preset iossim-ptpd-app-debug)

ptpd-run.sh
  Purpose:  General-purpose ptpd2 daemon test runner with logging and analysis
  Usage:    sudo ./scripts/testing/ptpd-run.sh <interface> <config_file> [options]
  Options:  -d, --duration N    Run duration in seconds (default: 60)
            -v, --verbose       Enable verbose output
  Features: - Configuration validation, packet capture, statistical analysis
            - Timestamped log directories in scripts/ptpd_logs/
  Example:  sudo ./scripts/testing/ptpd-run.sh en5 resources/ptpd-daemon.conf -d 120
  Notes:    - Searches build-cmake/macos-debug/ and build-cmake/macos-release/
              for the ptpd2 binary

run_sanitizers.sh
  Purpose:  Build and run ptpd under ASAN, TSAN, UBSAN, clang-tidy static
            analysis, and clang-format style check
  Usage:    ./scripts/testing/run_sanitizers.sh [options]
  Options:  -c, --config FILE   Config file for a live run (-k check if omitted)
            -i, --iface IFACE   Network interface (required for live run)
            -d, --duration N    Run duration in seconds (default: 10)
            -s, --sanitizer S   Run only one check:
                                  asan | tsan | ubsan | clang-tidy | clang-format
                                (default: all)
            -B, --no-build      Skip configure/build step
  Features: - macOS-aware (sets detect_leaks=0, passes SDK sysroot to clang-tidy)
            - Scoped to src/ only (excludes third-party dep/iniparser)
            - clang-format runs in check-only mode (does not modify files)
            - Reports written to logs/sanitizers/
  Example:  ./scripts/testing/run_sanitizers.sh
            ./scripts/testing/run_sanitizers.sh -s asan -c resources/ptpd-daemon.conf -i en5
  Notes:    - ASAN / TSAN / UBSAN must each be built in a separate binary
            - Live runs require root; config-check mode does not

compare-servo-options.sh
  Purpose:  Run ptpd-app three times back-to-back with different PI servo
            gains and collect timestamped CSV output for offline comparison
  Usage:    sudo ./scripts/testing/compare-servo-options.sh [duration_seconds]
  Configs:  current  : kp=0.01,  ki=0.0001   (baseline)
            option-a : kp=0.1,   ki=0.000001 (10x proportional, near-zero integral)
            option-b : kp=0.1,   ki=0.001    (10x proportional, 10x integral)
  Output:   scripts/ptpd_logs/comparison_<timestamp>/
  Example:  sudo ./scripts/testing/compare-servo-options.sh 300
  Notes:    - Uses caffeinate to prevent Mac sleep during the run
            - Binary: build-cmake/debug/src-app/ptpd-app

summarize-comparison.py
  Purpose:  Parse per-run servo CSV logs from a compare-servo-options.sh
            output directory and print a side-by-side statistics table
  Usage:    python3 scripts/testing/summarize-comparison.py <comparison_dir>
  Input:    Directory produced by compare-servo-options.sh
  Output:   Per-config offset/drift statistics (min, max, mean, std, RMS)
  Example:  python3 scripts/testing/summarize-comparison.py \
              scripts/ptpd_logs/comparison_20260312_220035/
  Requires: Python 3

================================================================================
                            ANALYSIS SCRIPTS
================================================================================

All analysis scripts are located in scripts/analysis/

analyze_ptp.py
  Purpose:  Statistical analysis of PTP offset/drift from CSV log files
  Usage:    python3 scripts/analysis/analyze_ptp.py <csv_file>
  Input:    CSV statistics file produced by ptpd2 or ptp-app-run.sh
  Output:   - All data statistics (min, max, mean, median, std dev, RMS)
            - Offset distribution by magnitude (<1 ms, <10 ms, <100 ms)
            - Well-synchronized period analysis (|offset| < 1 ms)
            - Jitter analysis for synchronized data
            - Path delay statistics
  Example:  python3 scripts/analysis/analyze_ptp.py \
              scripts/ptpd_logs/20260312_220035/ptpd_daemon_en5.csv
  Requires: Python 3, numpy

analyze_pcap.sh
  Purpose:  PTP packet capture protocol analysis
  Usage:    scripts/analysis/analyze_pcap.sh <pcap_file>
  Input:    PCAP file produced by ptp-app-run.sh or ptpd-run.sh
  Output:   - Capture summary (packet count, duration)
            - PTP message type distribution
            - Master/slave clock identities and IP addresses
            - Grandmaster clock properties (class, accuracy, priority)
            - Transport configuration and multicast addressing
            - Timing intervals and message sequencing
  Example:  scripts/analysis/analyze_pcap.sh \
              scripts/ptpd_logs/20260312_220035/ptp_en5.pcap
  Requires: tcpdump

================================================================================
                          DEVELOPMENT TOOLS
================================================================================

All development tools are located in scripts/tools/

gen-leap-header.py
  Purpose:  Build-time code generator — parses resources/leap-seconds.list
            and emits src/def/leap_seconds_builtin.h (compiled into libptpd2)
  Usage:    Invoked automatically by the leap_header CMake custom target;
            not normally run directly
  Output:   src/def/leap_seconds_builtin.h  (gitignored)
  Notes:    - Called by CMake via find_package(Python3 REQUIRED)
            - Generated header is a dependency of ptpd2, ptpd-static,
              ptpd-shared, and all test_leap_builtin GTest targets

compare-binaries.sh
  Purpose:  Compare two PTPd binaries for equivalence
  Usage:    ./scripts/tools/compare-binaries.sh <binary1> <binary2>
  Output:   File size diff, symbol count diff, symbol diff report
  Example:  ./scripts/tools/compare-binaries.sh \
              build-cmake/macos-debug/src/ptpd2 \
              build-cmake/macos-release/src/ptpd2
  Notes:    - Uses nm for symbol extraction
            - Flags size differences outside 5% tolerance

extract-symbols.sh
  Purpose:  Extract and analyze symbols from a binary
  Usage:    ./scripts/tools/extract-symbols.sh <binary> [output_file]
  Output:   Global symbols, symbol counts by type, undefined symbols,
            top-50 text symbols, top-30 data symbols
  Example:  ./scripts/tools/extract-symbols.sh \
              build-cmake/macos-debug/src/ptpd2 symbols.txt

clean-ptpd.sh
  Purpose:  Remove CMake build artifacts and temporary files
  Usage:    ./scripts/tools/clean-ptpd.sh [options]
  Options:  -L    Also remove ptp_test/ and ptp_logs/ directories
            -n    Dry run (show what would be removed, don't delete)
  Cleans:   - build-cmake/ directories
            - Compiled objects (.o, .lo, .la, .a)
            - compile_commands.json
            - macOS .DS_Store files
  Example:  ./scripts/tools/clean-ptpd.sh        # Clean build artifacts
            ./scripts/tools/clean-ptpd.sh -L     # Clean everything including logs
            ./scripts/tools/clean-ptpd.sh -n     # Preview

================================================================================
                            REQUIREMENTS
================================================================================

Common:
  - CMake 3.25 or higher
  - C compiler (clang recommended on macOS)
  - Bash 3.2+ (macOS default)
  - Python 3 (for gen-leap-header.py, analyze_ptp.py, summarize-comparison.py)

For ptp-app-run.sh / ptpd-run.sh:
  - Root/sudo privileges
  - tcpdump

For ptp-ios-run.sh:
  - Xcode with iOS Simulator runtime
  - xcrun / simctl

For run_sanitizers.sh:
  - clang with ASAN/TSAN/UBSAN support
  - clang-tidy and clang-format (brew install llvm)

For analyze_ptp.py / summarize-comparison.py:
  - numpy  (pip3 install numpy)

For binary analysis tools:
  - nm, file (pre-installed on macOS)

================================================================================
                            USAGE EXAMPLES
================================================================================

Build and run macOS test:
  cmake --preset macos-ptpd-app-debug
  cmake --build --preset macos-ptpd-app-debug
  sudo ./scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf -d 120

Build and run iOS simulator test:
  cmake --preset iossim-ptpd-app-debug
  cmake --build --preset iossim-ptpd-app-debug
  ./scripts/testing/ptp-ios-run.sh en5 192.168.68.114 -d 60

Run sanitizer checks:
  ./scripts/testing/run_sanitizers.sh
  ./scripts/testing/run_sanitizers.sh -s clang-tidy

Servo gain comparison (5 minutes per config, 15 minutes total):
  sudo ./scripts/testing/compare-servo-options.sh 300
  python3 scripts/testing/summarize-comparison.py \
      scripts/ptpd_logs/comparison_<timestamp>/

Analyze results:
  python3 scripts/analysis/analyze_ptp.py \
      scripts/ptpd_logs/<timestamp>/ptpd_daemon_en5.csv
  scripts/analysis/analyze_pcap.sh \
      scripts/ptpd_logs/<timestamp>/ptp_en5.pcap

================================================================================
                            RELATED DOCUMENTATION
================================================================================

For complete build instructions: See BUILD.md
For CMake presets and options:   See cmake/README.md
For configuration options:       See CONFIGURATION.md

================================================================================
