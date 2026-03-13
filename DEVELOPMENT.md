PTPd Development Notes
======================

PROJECT OVERVIEW
----------------
This is a fork of PTPd (Precision Time Protocol daemon) v2.3.x for macOS
development. The project uses CMake 3.15+ as its build system.


DIRECTORY STRUCTURE
-------------------

Source & Build System:
  src/                  - PTPd core source code
  src-app/macos/        - macOS example application (ptpd-app)
  src-app/ios/          - iOS SwiftUI application (PTPMonitor)
  src-gtests/           - GTest integration tests
  libraries/swclock/    - Software clock backend (git submodule)
  CMakeLists.txt        - Root CMake build definition
  CMakePresets.json     - All 12 named build presets
  cmake/                - CMake modules (platform detection, options)

Documentation:
  BUILD.md          - CMake build guide and option reference
  CONFIGURATION.md  - Technical reference for all config options
  DEVELOPMENT.md    - This file (workflow guide)
  USAGE.md          - Library integration guide and API reference
  docs/             - Supplemental notes and configs

Development Tools:
  scripts/testing/  - Test runners (ptp-app-run.sh, ptp-ios-run.sh, ptpd-run.sh)
  scripts/analysis/ - Post-run analysis tools
  scripts/tools/    - Utilities (clean-ptpd.sh, etc.)
  resources/        - Configuration templates

Build Outputs (all under build-cmake/):
  macos-debug/              - macOS library, debug
  macos-release/            - macOS library, release
  ios-simulator-debug/      - iOS simulator library, debug
  ios-simulator-release/    - iOS simulator library, release
  ios-debug/                - iOS device library, debug
  ios-release/              - iOS device library, release
  macos-ptpd-app-debug/     - macOS ptpd-app binary, debug
  macos-ptpd-app-release/   - macOS ptpd-app binary, release
  macos-gtest-debug/        - GTest suite, debug
  macos-gtest-release/      - GTest suite, release
  iossim-ptpd-app-debug/    - iOS simulator PTPMonitor.app, debug
  iossim-ptpd-app-release/  - iOS simulator PTPMonitor.app, release


DEVELOPMENT WORKFLOWS
---------------------

Option A: VS Code Integrated (Recommended)
------------------------------------------

1. Configure & Build:
   - Press Cmd+Shift+B → "Build macOS Debug" (default task)
   - Or: Terminal → Run Task → choose any of the 24 configure/build tasks
   - Tasks auto-copy compile_commands.json to the workspace root for clangd

2. Test (macOS library app):
   ./scripts/testing/ptp-app-run.sh en5 resources/ptpd-daemon.conf -d 120
   Logs saved to: scripts/ptpd_logs/<timestamp>/

3. Test (iOS Simulator):
   ./scripts/testing/ptp-ios-run.sh en5 192.168.68.114 -d 120

4. Clean:
   - Run Task: "Clean" (removes all 12 build-cmake/ directories)
   - Or: ./scripts/tools/clean-ptpd.sh


Option B: Command Line
----------------------

# Step 1 — build the libraries (required first)
cmake --preset macos-debug
cmake --build --preset macos-debug

# Step 2 — build a consumer (app / tests) against the pre-built libraries
cmake --preset macos-ptpd-app-debug
cmake --build --preset macos-ptpd-app-debug
# Binary: build-cmake/macos-ptpd-app-debug/src-app/ptpd-app

cmake --preset macos-gtest-debug
cmake --build --preset macos-gtest-debug

# iOS Simulator
cmake --preset ios-simulator-debug
cmake --build --preset ios-simulator-debug
cmake --preset iossim-ptpd-app-debug
cmake --build --preset iossim-ptpd-app-debug

All presets and their binaryDirs are defined in CMakePresets.json.
See BUILD.md for a full option reference.


BUILD ARTIFACTS & CLEANING
---------------------------

Clean build artifacts:
  ./scripts/tools/clean-ptpd.sh
  # Or via VS Code task: "Clean"

This removes all 12 build-cmake/ preset directories and compile_commands.json.

To rebuild after cleaning:
  cmake --preset macos-debug && cmake --build --preset macos-debug
  cmake --preset macos-ptpd-app-debug && cmake --build --preset macos-ptpd-app-debug


CONFIGURATION FILES
-------------------

Root:
  ptpd.conf                     - Local dev config (not in git, gitignored)

resources/:
  ptpd-daemon.conf              - Unicast slave config (used by test scripts)
  ptpd2.conf.default-full       - Full annotated default config
  ptpd2.conf.minimal            - Minimal slave config
  templates.conf                - Config templates reference
  test/
    client-e2e-*.conf             - E2E test configurations
    ptpd2-slave-sw-*.conf         - SW clock test configs


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

1. CMake 3.25+ is required (CMakePresets.json uses presets version 6).

2. Always build a library preset before its consumer preset:
   cmake --preset macos-debug before cmake --preset macos-ptpd-app-debug.

3. See BUILD.md for a full option reference table.

4. See CONFIGURATION.md for PTP runtime configuration options.

5. compile_commands.json at the workspace root is auto-generated by the
   "Configure macOS Debug" VS Code task — needed for clangd/IntelliSense.

6. Test logs in scripts/ptpd_logs/ can be safely deleted; they are gitignored.


RECENT CHANGES
--------------

- Mar 2026: Added CMakePresets.json with 12 presets (6 library + 6 consumer)
- Mar 2026: Added PTPD_PREBUILT_DIR consumer mode to CMakeLists.txt
- Mar 2026: iOS PTPMonitor app: noAdjust flag, PTPManager/ContentView improvements
- Mar 2026: Added ptp-ios-run.sh test runner for iOS Simulator
- Mar 2026: Updated all test scripts for new preset-based build directories
- Mar 2026: Removed obsolete scripts/build/ scripts (superseded by presets)
- Mar 2026: API anti-windup fix in swclock PI servo
- Mar 2026: clang-format (LLVM) applied to src/
- Feb 2026: Completed CMake migration, removed autotools
- Oct 2025: Added SW clock implementation (swclock submodule)


SWCLOCK SUBMODULE
-----------------

The software clock backend lives in libraries/swclock/ as a git submodule.
After cloning, initialise it with:

  git submodule update --init --recursive

BUILD_WITH_SWCLOCK=ON is the default for all presets and is required for
the iOS and macOS apps. The submodule is automatically built as part of the
library presets (macos-debug, ios-simulator-debug, etc.).


FOR MORE INFORMATION
--------------------

Upstream PTPd: https://github.com/ptpd/ptpd
Man pages: src/ptpd2.8.in, src/ptpd2.conf.5.in
Build guide: BUILD.md
Configuration reference: CONFIGURATION.md
Library integration: USAGE.md
