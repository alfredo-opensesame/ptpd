PTPd Development Notes
======================

PROJECT OVERVIEW
----------------
This is a fork of PTPd (Precision Time Protocol daemon) v2.3.x for macOS
development. The project supports TWO build systems:
  - GNU Autotools (autoconf/automake) - Traditional build system
  - CMake 3.15+ - Modern alternative build system

Both build systems are fully maintained in parallel and produce equivalent
binaries. Use whichever fits your workflow better.


DIRECTORY STRUCTURE
-------------------

Source & Build System:
  src/              - PTPd source code
  m4/               - Autoconf macros
  configure.ac      - Autoconf input
  Makefile.am       - Automake input
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
  macos/            - Standalone macOS toolkit (legacy/alternative)

Generated (by autotools):
  configure         - Configuration script (from configure.ac)
  Makefile.in       - Makefile template (from Makefile.am)
  aclocal.m4        - Autoconf macros (from m4/)
  config.h.in       - Config header template
  build-aux/        - Autotools helper scripts
  autom4te.cache/   - Autoconf cache

Generated (by configure):
  Makefile          - Actual makefiles
  config.h          - Configuration header
  config.status     - Configuration state
  libtool           - Libtool script

Build Outputs:
  build/debug/      - Debug build artifacts
  build/release/    - Release build artifacts


DEVELOPMENT WORKFLOWS
---------------------

Option A: VS Code Integrated (Recommended for Active Development)
------------------------------------------------------------------
Uses scripts/ + VS Code tasks + launch configurations

1. Configure & Build:
   - Press Cmd+Shift+B (default build task)
   - Or: Terminal → Run Task → "Build Debug"
   - This runs: scripts/config-debug.sh then make

2. Debug:
   - Press F5 or Run → Start Debugging
   - Uses configuration from .vscode/launch.json
   - Binary: build/debug/src/ptpd2
   - Config: ptpd.conf (in root)

3. Test:
   - Run: ./scripts/ptpd-run.sh -i <interface>
   - Advanced features: validation, pcap capture, analysis
   - Logs saved to: logs/<timestamp>/

4. Clean:
   - Run Task: "Distclean"
   - Or: ./macos/clean-ptpd.sh -a


Option B: Standalone Scripts (For Newcomers or CI)
---------------------------------------------------
Uses macos/ scripts - self-contained, no VS Code needed

1. Build:
   ./macos/ptpd-build-macos.sh
   - Checks dependencies
   - Runs autoreconf
   - Configures and builds
   - Output: macos/build/src/ptpd2

2. Test:
   ./macos/ptpd-run-macos.sh -i <interface> -t <seconds>
   - Simpler test runner
   - Auto-detects binary
   - Creates plots in ./ptp_logs/

3. Clean:
   ./macos/clean-ptpd.sh -a


COMPARISON: scripts/ vs macos/
-------------------------------

scripts/config-debug.sh:
  - VS Code task integration
  - Builds to: build/debug/
  - Generates compile_commands.json (IntelliSense)
  - Minimal: configure only

macos/ptpd-build-macos.sh:
  - Standalone script
  - Builds to: macos/build/
  - Full: deps + autoreconf + configure + compile
  - No VS Code integration

scripts/ptpd-run.sh (949 lines):
  - Advanced testing framework
  - Configuration validation
  - Health checks
  - Comprehensive logging

macos/ptpd-run-macos.sh (329 lines):
  - Simple test runner
  - Quick plotting
  - Auto-detection

Both are valid! Use scripts/ for daily development in VS Code,
use macos/ for quick standalone testing or onboarding new developers.


Option C: CMake Build (Modern Alternative)
-------------------------------------------
Uses CMake 3.15+ as alternative to autotools. See README.cmake.md for details.

1. Configure & Build (Debug):
   cmake -B build-cmake -DCMAKE_BUILD_TYPE=Debug
   cmake --build build-cmake
   - Binary: build-cmake/src/ptpd2
   - Or use VS Code tasks: "CMake Configure Debug" + "CMake Build Debug"

2. Configure & Build (Release):
   cmake -B build-release -DCMAKE_BUILD_TYPE=Release
   cmake --build build-release
   - Binary: build-release/src/ptpd2
   - Optimized with -O2

3. Configuration Options:
   cmake -B build -DENABLE_SNMP=ON -DENABLE_SLAVE_ONLY=ON -DDEBUG_LEVEL=all
   - All autotools options have CMake equivalents
   - See README.cmake.md for complete option reference

4. Install:
   sudo cmake --install build-cmake --prefix /usr/local
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
  + Faster configuration than autotools
  = Binary equivalence verified (98-100% symbol match)

Why Autotools?
  + Traditional Unix/Linux build system
  + Widely understood by sysadmins
  + Proven stability (decades of use)
  = Binary equivalence verified

Both systems tested comprehensively. Choose based on preference!


BUILD ARTIFACTS & CLEANING
---------------------------

Clean build artifacts only (keeps configure scripts):
  ./macos/clean-ptpd.sh

Full distclean (removes all generated files):
  ./macos/clean-ptpd.sh -a

This removes:
  - build/ directories
  - Object files (*.o, *.lo, *.la)
  - Binaries (src/ptpd2)
  - Generated autotools files (configure, Makefile.in, config.h.in, etc.)
  - build-aux/, autom4te.cache/
  - Makefiles, config.h, config.status, libtool

To rebuild after distclean:
  autoreconf -i   # Regenerates configure scripts
  ./configure     # Or use scripts/config-debug.sh


CONFIGURATION FILES
-------------------

Root:
  ptpd.conf                     - Local dev config (not in git)

resources/:
  ptpd-daemon.conf              - Production-style slave config

macos/conf-files/:
  ptpd2-slave-sw-multicast.conf - SW clock multicast
  ptpd2-slave-sw-unicast.conf   - SW clock unicast
  ptpd2-slave-sw-mixed.conf     - SW clock mixed mode

Use resources/ for configuration templates.
Use macos/conf-files/ for testing with macos/ptpd-run-macos.sh


GIT TRACKED vs IGNORED
-----------------------

Tracked (source):
  - *.c, *.h (source code)
  - Makefile.am (automake input)
  - configure.ac (autoconf input)
  - Custom scripts (scripts/, macos/)
  - Documentation (README.md, COPYRIGHT, etc.)

Ignored (generated/logs):
  - Build artifacts (build/, *.o, ptpd2)
  - Autotools generated (configure, Makefile.in, config.h.in, etc.)
  - VS Code database (.vscode/browse.vc.db)
  - Test logs (logs/)
  - Local config (ptpd.conf)

See .gitignore for complete list.


NOTES FOR CONTRIBUTORS
----------------------

1. Both autotools and CMake build systems are supported and maintained.

2. See README.cmake.md for CMake build instructions.

3. The scripts/ folder contains development tools consolidated from previous
   @build-scripts/ and @test-scripts/ directories.

4. VS Code configuration supports both autotools and CMake builds.

5. Test logs can be safely deleted - they're not tracked in git.


RECENT CHANGES
--------------

- Feb 2026: CMake build system added (parallel with autotools)
- Feb 2026: Consolidated scripts into scripts/ directory
- Feb 2026: Created resources/ for configuration templates
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
  ./configure --enable-sw-clock
  make

Test configurations available in macos/conf-files/ptpd2-slave-sw-*.conf


FOR MORE INFORMATION
--------------------

Upstream PTPd: https://github.com/ptpd/ptpd
Documentation: doc/ folder
Man pages: src/ptpd2.8.in, src/ptpd2.conf.5.in
macOS README: macos/README.md (Note: CMake sections are outdated)
