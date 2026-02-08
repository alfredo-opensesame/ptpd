================================================================================
                            PTPd Scripts Directory
================================================================================

This directory contains build, test, analysis, and utility scripts for the
PTPd project. All scripts support the CMake build system (autotools removed).

================================================================================
                        BUILD & CONFIGURATION SCRIPTS
================================================================================

config-cmake-debug.sh
  Purpose:  Configure CMake build in Debug mode
  Usage:    ./scripts/config-cmake-debug.sh
  Output:   build-cmake/debug/ directory with Makefiles
  Options:  Debug build with all debugging enabled, runtime checks, PCAP,
            statistics, daemon mode OFF, software clock ON
  Notes:    - Creates compile_commands.json for IDE IntelliSense
            - After running, use: cd build-cmake/debug && make -j4

config-cmake-release.sh
  Purpose:  Configure CMake build in Release mode
  Usage:    ./scripts/config-cmake-release.sh
  Output:   build-cmake/release/ directory with Makefiles
  Options:  Release build with optimizations, PCAP, statistics, daemon ON
  Notes:    - Creates compile_commands.json for IDE IntelliSense
            - After running, use: cd build-cmake/release && make -j4
            - To install: cmake --install build-cmake/release --prefix /usr/local

================================================================================
                            TESTING SCRIPTS
================================================================================

test-config.sh
  Purpose:  Test a specific PTPd configuration build
  Usage:    ./scripts/test-config.sh <config_name>
  Configs:  1|default, 2|minimal, 3|sw-clock, 4|slave-only, 5|no-posix-timers,
            6|no-pcap, 7|no-snmp, 8|no-statistics, 9|debug-basic,
            10|debug-medium, 11|debug-all, 12|runtime-debug, 13|experimental,
            14|no-daemon, 15|high-unicast, 16|combined
  Output:   Builds with CMake, compares binary size and symbol counts
  Example:  ./scripts/test-config.sh minimal
  Notes:    - Originally used for autotools-vs-CMake migration validation
            - Now validates CMake build configurations only

test-all-configs.sh
  Purpose:  Run comprehensive tests on all 16 configurations
  Usage:    ./scripts/test-all-configs.sh
  Output:   test-results/test-report-<timestamp>.txt
  Example:  ./scripts/test-all-configs.sh
  Notes:    - Tests all configurations from CONFIGURATION-MATRIX.txt
            - Generates summary report with pass/fail counts
            - Cleans up test directories automatically

ptpd-run.sh
  Purpose:  Comprehensive PTPd daemon test runner with logging and analysis
  Usage:    ./scripts/ptpd-run.sh <interface> <config_file> [options]
  Options:  -d, --duration N  Run duration in seconds (default: 60)
            -v, --verbose     Enable verbose output
            -h, --help        Show help message
  Features: - Configuration validation using PTPd binary
            - Comprehensive PTP traffic analysis
            - Statistical analysis and plotting
            - Packet capture (tcpdump) and protocol analysis
            - Automatic cleanup and resource management
            - Live master detection and synchronization monitoring
  Example:  sudo ./scripts/ptpd-run.sh en0 resources/conf/ptpd-daemon.conf -d 120
  Notes:    - Requires root privileges (uses sudo automatically)
            - Creates timestamped log directories
            - Generates CSV statistics files
            - Size: 950 lines (comprehensive logging & validation)

================================================================================
                            ANALYSIS SCRIPTS
================================================================================

analyze_ptp.py
  Purpose:  Analyze PTP statistics from CSV log files
  Usage:    python3 scripts/analyze_ptp.py <csv_file>
  Input:    CSV file with PTP statistics (from ptpd-run.sh or ptpd2 logs)
  Output:   Statistical analysis including:
            - Offset from Master (mean, median, std dev, RMS, peak-to-peak)
            - Jitter analysis (mean, std dev)
            - Allan Deviation approximation
            - Path Delay statistics
  Example:  python3 scripts/analyze_ptp.py ptp_logs/20240101_120000/stats.csv
  Requires: Python 3, numpy
  Notes:    - Filters outliers (>10ms)
            - Converts values to microseconds for readability
            - Only analyzes slave state data

compare-binaries.sh
  Purpose:  Compare two PTPd binaries for equivalence
  Usage:    ./scripts/compare-binaries.sh <binary1> <binary2>
  Output:   Detailed comparison report including:
            - File size and size difference percentage
            - File type information
            - Symbol count and symbol difference
            - Symbol diff (identical/missing/added symbols)
  Example:  ./scripts/compare-binaries.sh build-old/src/ptpd2 build-new/src/ptpd2
  Notes:    - Used during CMake migration to verify binary equivalence
            - Checks if size difference is within 5% tolerance
            - Compares exported symbols

extract-symbols.sh
  Purpose:  Extract and analyze symbols from a binary
  Usage:    ./scripts/extract-symbols.sh <binary> [output_file]
  Output:   Symbol analysis report including:
            - Global symbols (exported)
            - Symbol count by type (T, D, B, etc.)
            - Undefined symbols (external dependencies)
            - Text symbols (functions, top 50)
            - Data symbols (top 30)
            - Statistics summary
  Example:  ./scripts/extract-symbols.sh build-cmake/debug/src/ptpd2 symbols.txt
  Notes:    - Uses 'nm' command for symbol extraction
            - Outputs to stdout or specified file
            - Useful for debugging linking issues

================================================================================
                            UTILITY SCRIPTS
================================================================================

clean-ptpd.sh
  Purpose:  Clean CMake build artifacts and temporary files
  Usage:    ./scripts/clean-ptpd.sh [options]
  Options:  -L    Also remove ./ptp_test and ./ptp_logs directories
            -n    Dry run (show what would be removed, don't delete)
  Cleans:   - CMake build directories (build-cmake/, build/ninja-*)
            - Compiled objects (.o, .lo, .la, .a files)
            - macOS junk (.DS_Store files)
            - compile_commands.json symlink
            - Optional: test artifacts and log directories
  Example:  ./scripts/clean-ptpd.sh        # Clean build artifacts
            ./scripts/clean-ptpd.sh -L     # Clean everything including logs
            ./scripts/clean-ptpd.sh -n     # Preview what will be deleted
  Notes:    - Safe to run anytime (includes dry-run mode)
            - Runs 'make clean' or 'ninja clean' before removing directories
            - Respects .git directory (never touches it)

================================================================================
                            REQUIREMENTS
================================================================================

Common Requirements:
  - CMake 3.15 or higher
  - Make or Ninja build system
  - C compiler (clang or gcc)
  - Bash shell

For ptpd-run.sh:
  - Root/sudo privileges (for network operations)
  - tcpdump (for packet capture)
  - Network interface with PTP support

For analyze_ptp.py:
  - Python 3
  - numpy library (pip3 install numpy)

For binary analysis:
  - nm (part of binutils, usually pre-installed)
  - file command
  - Standard Unix tools (awk, sed, grep)

================================================================================
                            USAGE EXAMPLES
================================================================================

Quick Start - Build & Run:
  # Configure and build debug version
  ./scripts/config-cmake-debug.sh
  cd build-cmake/debug && make -j4

  # Run PTPd daemon with config file (requires sudo)
  sudo ./build-cmake/debug/src/ptpd2 -f resources/conf/ptpd-daemon.conf -m

Full Test Workflow:
  # Clean previous builds
  ./scripts/clean-ptpd.sh -L

  # Configure and test debug build
  ./scripts/test-config.sh default

  # Run comprehensive daemon test
  sudo ./scripts/ptpd-run.sh en0 resources/conf/ptpd-daemon.conf -d 120

  # Analyze results
  python3 scripts/analyze_ptp.py ptp_logs/*/stats.csv

Migration Validation:
  # Test all configurations (CMake validation)
  ./scripts/test-all-configs.sh

  # Compare binaries
  ./scripts/compare-binaries.sh old-binary new-binary

  # Extract symbols for analysis
  ./scripts/extract-symbols.sh build-cmake/debug/src/ptpd2 symbols-debug.txt
  ./scripts/extract-symbols.sh build-cmake/release/src/ptpd2 symbols-release.txt

Development Workflow:
  # Configure debug build with IntelliSense support
  ./scripts/config-cmake-debug.sh

  # Build (VS Code task or manual)
  cd build-cmake/debug && make -j4

  # Clean and rebuild
  ./scripts/clean-ptpd.sh
  ./scripts/config-cmake-debug.sh
  cd build-cmake/debug && make -j4

================================================================================
                            HISTORICAL NOTES
================================================================================

These scripts were created during the CMake migration project (Phase 0-12).
Some scripts (test-config.sh, compare-binaries.sh) originally compared
autotools vs CMake builds. The migration is complete, and autotools has been
removed. These scripts now validate CMake configurations only.

Original autotools scripts (removed):
  - @build-scripts/config-debug.sh (autotools configure wrapper)
  - @build-scripts/config-release.sh (autotools configure wrapper)
  - macos/ptpd-run-macos.sh (macOS-specific runner, superseded by ptpd-run.sh)

The scripts in this directory are maintained and support CMake-only builds.

================================================================================
                            RELATED DOCUMENTATION
================================================================================

For complete build instructions: See BUILD.md
For development workflows:      See DEVELOPMENT.md
For CMake configuration:        See cmake/README.md
For configuration options:      See CONFIGURATION.md

================================================================================
