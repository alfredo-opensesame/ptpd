PTPd Development Notes
======================

PROJECT OVERVIEW
----------------
This is a fork of PTPd (Precision Time Protocol daemon) v2.3.x for macOS
development. The project uses CMake 3.15+ as its build system.


DIRECTORY STRUCTURE
-------------------

Source & Build System:
  src/              - PTPd source code
  CMakeLists.txt    - CMake build definition (root)
  cmake/            - CMake modules (platform detection, options)

Documentation:
  README.cmake.md   - CMake build instructions and examples
  CONFIGURATION.md  - Complete technical reference for all config options
  MyREADME.txt      - This file (workflow guide)
  PLAN.txt          - CMake migration plan and status

Development Tools (Custom Additions):
  scripts/          - Build automation, testing, and analysis tools
  resources/        - Configuration templates and resources

Build Outputs:
  build-cmake/debug/      - Debug build artifacts
  build-cmake/release/    - Release build artifacts


DEVELOPMENT WORKFLOWS
---------------------

Option A: VS Code Integrated (Recommended for Active Development)
------------------------------------------------------------------
Uses scripts/ + VS Code tasks + launch configurations

1. Configure & Build:
   - Press Cmd+Shift+B (default build task)
   - Or: Terminal → Run Task → "Build Debug"
   - This runs: scripts/config-cmake-debug.sh then cmake --build

2. Debug:
   - Press F5 or Run → Start Debugging
   - Uses configuration from .vscode/launch.json
   - Binary: build-cmake/debug/src/ptpd2
   - Config: ptpd.conf (in root)

3. Test:
   - Run: ./scripts/ptpd-run.sh -i <interface>
   - Advanced features: validation, pcap capture, analysis
   - Logs saved to: logs/<timestamp>/

4. Clean:
   - Run Task: "Clean"
   - Or: ./scripts/clean-ptpd.sh


Option B: Manual CMake Build (For Newcomers or CI)
---------------------------------------------------
Direct CMake commands - works anywhere

1. Configure & Build (Debug):
   ./scripts/config-cmake-debug.sh
   # Or manually:
   cmake -B build-cmake/debug -DCMAKE_BUILD_TYPE=Debug
   cmake --build build-cmake/debug
   - Binary: build-cmake/debug/src/ptpd2

2. Configure & Build (Release):
   ./scripts/config-cmake-release.sh
   # Or manually:
   cmake -B build-cmake/release -DCMAKE_BUILD_TYPE=Release -DENABLE_RUNTIME_DEBUG=OFF
   cmake --build build-cmake/release
   - Binary: build-cmake/release/src/ptpd2
   - Optimized with -O2

3. Configuration Options:
   cmake -B build -DENABLE_SNMP=ON -DENABLE_SLAVE_ONLY=ON -DDEBUG_LEVEL=all
   - See README.cmake.md for complete option reference
   - See CONFIGURATION.md for technical details on each option

4. Install:
   sudo cmake --install build-cmake/debug --prefix /usr/local
   - Installs binary, man pages, and data files

5. Multiple Configurations (CMake advantage):
   cmake -B build-debug -DCMAKE_BUILD_TYPE=Debug
   cmake -B build-release -DCMAKE_BUILD_TYPE=Release
   cmake -B build-minimal -DENABLE_STATISTICS=OFF -DENABLE_PCAP=OFF
   - All coexist without conflicts!

6. IDE Integration:
   - VS Code: Use CMake tasks (Cmd+Shift+B)
   - CLion: Native CMake support
   - Xcode: cmake -B build-xcode -G Xcode

Why CMake?
  + Better IDE integration (IntelliSense, CLion, Xcode)
  + Multiple build configs simultaneously (debug + release + custom)
  + Cross-platform (Linux, macOS, Windows, FreeBSD)
  + Modern dependency management
  + Faster configuration
  = Binary equivalence verified (98-100% symbol match with original autotools builds)


BUILD ARTIFACTS & CLEANING
---------------------------

Clean build artifacts:
  ./scripts/clean-ptpd.sh

This removes:
  - build-cmake/ directories
  - Object files (*.o)
  - Binaries (ptpd2)
  - compile_commands.json symlink

To rebuild after cleaning:
  ./scripts/config-cmake-debug.sh
  # Or: cmake -B build-cmake/debug && cmake --build build-cmake/debug


CONFIGURATION FILES
-------------------

Root:
  ptpd.conf                     - Local dev config (not in git)

resources/:
  ptpd-daemon.conf              - Production-style slave config

test/:
  client-e2e-*.conf             - E2E test configurations
  ptpd2-slave-sw-multicast.conf - SW clock multicast test config
  ptpd2-slave-sw-unicast.conf   - SW clock unicast test config
  ptpd2-slave-sw-mixed.conf     - SW clock mixed mode test config

Use resources/ for configuration templates.
Use test/ for test configurations.


GIT TRACKED vs IGNORED
-----------------------

Tracked (source):
  - *.c, *.h (source code)
  - CMakeLists.txt (CMake build definition)
  - cmake/ (CMake modules)
  - Custom scripts (scripts/)
  - Documentation (README.md, COPYRIGHT, etc.)

Ignored (generated/logs):
  - Build artifacts (build-cmake/, *.o, ptpd2)
  - CMake generated files (CMakeCache.txt, cmake_install.cmake, etc.)
  - VS Code database (.vscode/browse.vc.db)
  - Test logs (logs/)
  - Local config (ptpd.conf)

See .gitignore for complete list.


NOTES FOR CONTRIBUTORS
----------------------

1. CMake 3.15+ is the build system for this project.

2. See README.cmake.md for CMake build instructions.

3. See CONFIGURATION.md for detailed technical reference on all 12 configuration options.

4. The scripts/ folder contains development tools consolidated from previous
   @build-scripts/ and @test-scripts/ directories.

5. VS Code configuration supports CMake builds with IntelliSense, debugging, and tasks.

6. Test logs can be safely deleted - they're not tracked in git.


RECENT CHANGES
--------------

- Feb 2026: Completed CMake migration, removed autotools
- Feb 2026: Consolidated scripts into scripts/ directory
- Feb 2026: Created resources/ for configuration templates
- Feb 2026: Added comprehensive CONFIGURATION.md reference
- Oct 2025: Added SW clock implementation
- Oct 2025: VS Code integration enhanced


SOURCE CODE CHANGES (Since Fork)
---------------------------------

This fork has 13 commits modifying src/ beyond the upstream ptpd codebase.
All changes were made in October 2025 by Alfredo Franco.

MAJOR ADDITION: Software Clock Implementation
----------------------------------------------

New directory: src/dep/sw_clock/ (434 lines)
  - sw_adjtimex.c/h      (62 + 55 lines) - adjtime() emulation for macOS
  - swclock.c/h          (178 + 40 lines) - Software clock core
  - swclock_compat.c/h   (66 + 33 lines) - Platform compatibility layer

Purpose: Provides a software-based clock adjustment mechanism for macOS,
which lacks native adjtime() support. Enabled with --enable-sw-clock flag.

Status: Implementation complete, integration in progress.


MODIFIED FILES
--------------

src/dep/sys.c (232 lines changed)
  - Changed POSIX timer detection from _POSIX_TIMERS to POSIX_TIMERS_SUPPORTED
  - Improved platform compatibility for timer functions
  - Status: Has uncommitted local changes

src/dep/startup.c (294 lines refactored)
  - Integration hooks for SW clock initialization
  - Build system updates for sw_clock/ subdirectory

src/dep/servo.c
  - Clock adjustment logic modifications
  - SW clock integration points

src/dep/timingdomain.c
  - Timing domain handling updates

src/datatypes.h
  - Added SW clock data structures
  - Configuration flags for SW clock feature

src/dep/eventtimer_itimer.c
src/dep/eventtimer_posix.c
  - Event timer compatibility improvements


COMMIT TIMELINE (Chronological)
--------------------------------

1. 2ec83d8 - Commented out noisy timer logs
2. fd4a59d - Cosmetic changes
3. 2f03cc0 - Debug messages added and formatting improved
4. 438b384 - Improved formatting
5. ef38baa - Added the SW clock implementation (origin/macos)
6. 365049a - Formatting fixes and documentation
7. 4247fc3 - Start to integrate a SW clock
8. 13b1192 - Start of sw_clock integration (HEAD)

Branch Status: 3 commits ahead of origin/macos


KEY MODIFICATIONS
-----------------

1. SW Clock Core:
   - Provides adjtime() emulation for macOS
   - Software-based frequency adjustment
   - Compatible with ptpd servo mechanisms

2. Platform Compatibility:
   - POSIX timer detection improvements
   - macOS-specific workarounds
   - Conditional compilation via --enable-sw-clock

3. Code Quality:
   - Formatting consistency improvements
   - Debug message enhancements
   - Reduced log verbosity (commented noisy timers)

4. Build System:
   - Makefile.am updated for src/dep/sw_clock/
   - Configure flag: --enable-sw-clock
   - Conditional compilation support


INTEGRATION STATUS
------------------

✅ Complete:
  - SW clock implementation (434 lines)
  - Build system integration (--enable-sw-clock flag)
  - Basic formatting and cleanup

🔄 In Progress:
  - Full integration with ptpd servo (commits 4247fc3, 13b1192)
  - POSIX timer compatibility refinement

⚠️  Uncommitted:
  - src/dep/sys.c: POSIX_TIMERS macro change


TESTING
-------

To build with SW clock support:
  cmake -B build -DENABLE_SW_CLOCK=ON
  cmake --build build

Test configurations available in test/ptpd2-slave-sw-*.conf


FOR MORE INFORMATION
--------------------

Upstream PTPd: https://github.com/ptpd/ptpd
Documentation: doc/ folder
Man pages: src/ptpd2.8.in, src/ptpd2.conf.5.in
CMake Build Guide: README.cmake.md
Configuration Reference: CONFIGURATION.md
