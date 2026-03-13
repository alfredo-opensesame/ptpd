cmake_minimum_required(VERSION 3.15)

project(ptpd VERSION 2.3.1 LANGUAGES C)

# Consumer mode: when set, imports a pre-built library instead of rebuilding it.
# Set PTPD_PREBUILT_DIR in a preset's cacheVariables to build only the app or
# tests without recompiling src/ or libraries/swclock/.
set(PTPD_PREBUILT_DIR "" CACHE PATH
    "Path to a pre-built ptpd library build directory. When set, src/ and \
    libraries/swclock/ are NOT rebuilt; their static libraries are imported.")

# Override PROJECT_VERSION with VERSION_NUMBER from m4/version.m4
# PACKAGE_VERSION must match VERSION_NUMBER (6.6.6) not project VERSION (2.3.1)
# This is what autotools uses and what's displayed in --version output
set(PROJECT_VERSION "6.6.6")

# Set C standard to C99 (matching autotools AC_PROG_CC_C99)
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# Add cmake modules directory to module path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Phase 2: Platform detection (matching autotools configure.ac)
# Perform comprehensive header, function, type, and symbol checks
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/CheckPlatform.cmake)

# Find required libraries (matching AC_SEARCH_LIBS in configure.ac)
find_library(LIBM_LIBRARY m)
if(LIBM_LIBRARY)
    set(MATH_LIBRARY ${LIBM_LIBRARY})
else()
    set(MATH_LIBRARY "")
endif()

find_library(LIBRT_LIBRARY rt)
if(LIBRT_LIBRARY)
    set(RT_LIBRARY ${LIBRT_LIBRARY})
else()
    set(RT_LIBRARY "")
endif()

# Phase 3: Find PCAP library using FindPCAP module (pcap-config or fallback)
# User can disable with -DENABLE_PCAP=OFF
# Note: FindPCAP sets HAVE_PCAP_H and HAVE_PCAP_PCAP_H as cache variables
find_package(PCAP)

# Phase 3: Find Net-SNMP library using FindNETSNMP module (net-snmp-config)
# User can disable with -DENABLE_SNMP=OFF
find_package(NETSNMP)

# Phase 7: Build date and version information (matching autotools configure.ac)
# Get build date in YYYYMMDD format (always set, but only used if CODE_REVISION is defined)
string(TIMESTAMP BUILD_DATE "%Y%m%d")

# Get git revision only if VERSION_NUMBER contains "-svn" suffix (matching autotools logic)
# In autotools: ver_prefix=`echo VERSION_NUMBER | cut -s -d- -f2`
# Only set CODE_REVISION if ver_prefix = "svn"
string(REGEX MATCH "-([a-z]+)$" VERSION_SUFFIX "${PROJECT_VERSION}")
if(VERSION_SUFFIX)
    string(SUBSTRING "${VERSION_SUFFIX}" 1 -1 VERSION_SUFFIX_TYPE)
    if(VERSION_SUFFIX_TYPE STREQUAL "svn")
        # Check for git (modern replacement for svnversion)
        find_package(Git QUIET)
        if(GIT_FOUND)
            execute_process(
                COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
                WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                OUTPUT_VARIABLE GIT_REVISION
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
            )
            if(GIT_REVISION)
                set(CODE_REVISION ${GIT_REVISION})
            endif()
        endif()
    endif()
endif()

# Phase 4: Configuration options (--enable-xxx / --disable-xxx flags)
# Must come after library detection so we know what's available
# Sets ENABLE_* options and validates their values
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/Options.cmake)

# Generate config.h — in consumer mode copy from the pre-built dir to guarantee ABI alignment
if(PTPD_PREBUILT_DIR)
    configure_file(
        "${PTPD_PREBUILT_DIR}/config.h"
        "${PROJECT_BINARY_DIR}/config.h"
        COPYONLY
    )
else()
    configure_file(
        ${CMAKE_CURRENT_SOURCE_DIR}/cmake/config.h.in
        ${PROJECT_BINARY_DIR}/config.h
        @ONLY
    )
endif()

# Set install directories (matching autotools defaults)
include(GNUInstallDirs)

# Phase 6: Man page variables for substitution (matching m4/version.m4)
set(VERSION_NUMBER "6.6.6")
set(RELEASE_DATE "October, 2015")
set(PACKAGE_NAME "ptpd")

# Set install prefix for man pages (matching autotools @prefix@ substitution)
set(prefix ${CMAKE_INSTALL_PREFIX})

# Runtime template variables that should remain in man pages
# These are substituted at runtime by ptpd, not at build time
set(instance "@instance@")
set(pid "@pid@")
set(hostname "@hostname@")
set(name "@name@")

# Phase 6: Generate man pages from templates
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ptpd2.8.in
    ${PROJECT_BINARY_DIR}/ptpd2.8
    @ONLY
)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/src/ptpd2.conf.5.in
    ${PROJECT_BINARY_DIR}/ptpd2.conf.5
    @ONLY
)

# ── Consumer mode or Library mode? ─────────────────────────────────────────────
if(PTPD_PREBUILT_DIR)
    # ── Consumer mode: import pre-built artifacts; skip rebuilding src/ and swclock/ ──
    message(STATUS "Consumer mode: importing pre-built library from ${PTPD_PREBUILT_DIR}")

    # Determine config-specific library sub-paths (Xcode multi-config vs single-config)
    if(CMAKE_GENERATOR MATCHES "Xcode")
        string(TOLOWER "${CMAKE_OSX_SYSROOT}" _sysroot_lc)
        if(_sysroot_lc MATCHES "iphonesimulator")
            set(_sfx_d "Debug-iphonesimulator")
            set(_sfx_r "Release-iphonesimulator")
        elseif(_sysroot_lc MATCHES "iphoneos")
            set(_sfx_d "Debug-iphoneos")
            set(_sfx_r "Release-iphoneos")
        else()
            set(_sfx_d "Debug")
            set(_sfx_r "Release")
        endif()
        set(_ptpd2_d "${PTPD_PREBUILT_DIR}/src/${_sfx_d}/libptpd2.a")
        set(_ptpd2_r "${PTPD_PREBUILT_DIR}/src/${_sfx_r}/libptpd2.a")
        set(_swclk_d "${PTPD_PREBUILT_DIR}/libraries/swclock/${_sfx_d}/libswclock.a")
        set(_swclk_r "${PTPD_PREBUILT_DIR}/libraries/swclock/${_sfx_r}/libswclock.a")
    else()
        # Single-config (Unix Makefiles)
        set(_ptpd2_d "${PTPD_PREBUILT_DIR}/src/libptpd2.a")
        set(_ptpd2_r "${PTPD_PREBUILT_DIR}/src/libptpd2.a")
        set(_swclk_d "${PTPD_PREBUILT_DIR}/libraries/swclock/libswclock.a")
        set(_swclk_r "${PTPD_PREBUILT_DIR}/libraries/swclock/libswclock.a")
    endif()

    # Import ptpd2 static library
    add_library(ptpd2 STATIC IMPORTED GLOBAL)
    set_target_properties(ptpd2 PROPERTIES
        IMPORTED_LOCATION           "${_ptpd2_d}"
        IMPORTED_LOCATION_DEBUG     "${_ptpd2_d}"
        IMPORTED_LOCATION_RELEASE   "${_ptpd2_r}"
    )
    target_include_directories(ptpd2 INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${PROJECT_BINARY_DIR}"
    )
    # Compatibility aliases expected by src-app and src-gtests
    add_library(ptpd-static ALIAS ptpd2)
    add_library(ptpd-shared ALIAS ptpd2)

    # Import swclock static library
    option(BUILD_WITH_SWCLOCK "Link against pre-built swclock library" ON)
    if(BUILD_WITH_SWCLOCK)
        # zlib is a transitive dependency of swclock (used for log compression)
        find_package(ZLIB REQUIRED)
        add_library(swclock STATIC IMPORTED GLOBAL)
        set_target_properties(swclock PROPERTIES
            IMPORTED_LOCATION           "${_swclk_d}"
            IMPORTED_LOCATION_DEBUG     "${_swclk_d}"
            IMPORTED_LOCATION_RELEASE   "${_swclk_r}"
        )
        target_include_directories(swclock INTERFACE
            "${CMAKE_CURRENT_SOURCE_DIR}/libraries/swclock/src/sw_clock"
        )
        target_link_libraries(swclock INTERFACE ZLIB::ZLIB ${MATH_LIBRARY})
    endif()

    # Declare transitive link deps on ptpd2 (pcap, pthread, math)
    # These were embedded in the library's translation units; consumers must
    # supply them at their final link.
    set(_ptpd2_iface_libs "pthread;${MATH_LIBRARY}")
    if(PCAP_FOUND)
        list(APPEND _ptpd2_iface_libs "${PCAP_LIBRARIES}")
    endif()
    target_link_libraries(ptpd2 INTERFACE ${_ptpd2_iface_libs})

    # macOS ptpd-app (also builds ptpd_app_utils, required by gtest targets)
    option(BUILD_PTPD_APP  "Build ptpd-app macOS example application" OFF)
    # iOS PTP Monitor app (Swift + ObjC; requires an iOS preset)
    option(BUILD_IOS_APP   "Build iOS PTP Monitor application"        OFF)
    # GTest suite
    option(BUILD_PTPD_TESTS "Build GoogleTest unit/integration tests" OFF)

    if(BUILD_PTPD_APP OR BUILD_PTPD_TESTS)
        add_subdirectory(src-app)
    endif()

    if(BUILD_IOS_APP)
        enable_language(Swift OBJC)
        set(CMAKE_Swift_LANGUAGE_VERSION 5.0)
        set(CMAKE_XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2")
        add_subdirectory(src-app/ios)
    endif()

    if(BUILD_PTPD_TESTS)
        enable_language(CXX)
        set(CMAKE_CXX_STANDARD 17)
        set(CMAKE_CXX_STANDARD_REQUIRED ON)
        include(CTest)
        enable_testing()
        add_subdirectory(src-gtests)
    endif()

else()
    # ── Library mode (existing) ──────────────────────────────────────────────
    # Add source directory
    add_subdirectory(src)

    # SwClock integration option (compile-time backend selection)
    option(BUILD_WITH_SWCLOCK "Build ptpd with swclock backend (software clock)" ON)
    if(BUILD_WITH_SWCLOCK)
        # Add swclock as a subdirectory
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libraries/swclock/CMakeLists.txt")
            add_subdirectory(libraries/swclock)
            message(STATUS "SwClock backend: ENABLED (software clock)")
        else()
            message(FATAL_ERROR "BUILD_WITH_SWCLOCK is ON but libraries/swclock not found. Please initialize git submodule.")
        endif()
    else()
        message(STATUS "SwClock backend: DISABLED (system clock)")
    endif()

    # Add example application if library build is enabled
    option(BUILD_PTPD_LIBRARY "Build ptpd as a library in addition to executable" OFF)
    if(BUILD_PTPD_LIBRARY)
        add_subdirectory(src-app)
    endif()

    # GoogleTest unit/integration tests for ptpd-app and swclock integration.
    # Requires BUILD_PTPD_LIBRARY=ON (for ptpd-shared target) and GTest.
    option(BUILD_PTPD_TESTS "Build GoogleTest unit/integration tests" OFF)
    if(BUILD_PTPD_TESTS)
        if(NOT BUILD_PTPD_LIBRARY)
            message(FATAL_ERROR
                "BUILD_PTPD_TESTS=ON requires BUILD_PTPD_LIBRARY=ON")
        endif()
        # Test sources are C++ — enable the language now (project() only declared C)
        enable_language(CXX)
        set(CMAKE_CXX_STANDARD 17)
        set(CMAKE_CXX_STANDARD_REQUIRED ON)
        include(CTest)
        enable_testing()
        add_subdirectory(src-gtests)
    endif()

endif()

# Phase 6: Install targets
# Install man pages (generated from .in templates)
install(FILES ${PROJECT_BINARY_DIR}/ptpd2.8
        DESTINATION ${CMAKE_INSTALL_MANDIR}/man8)
install(FILES ${PROJECT_BINARY_DIR}/ptpd2.conf.5
        DESTINATION ${CMAKE_INSTALL_MANDIR}/man5)

# Install configuration files to ${datadir}/ptpd
install(FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/resources/ptpd2.conf.minimal
    ${CMAKE_CURRENT_SOURCE_DIR}/resources/ptpd2.conf.default-full
    ${CMAKE_CURRENT_SOURCE_DIR}/resources/templates.conf
    DESTINATION ${CMAKE_INSTALL_DATADIR}/ptpd)

# Install data files to ${datadir}/ptpd
install(FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/resources/leap-seconds.list
    ${CMAKE_CURRENT_SOURCE_DIR}/doc/PTPBASE-MIB.txt
    DESTINATION ${CMAKE_INSTALL_DATADIR}/ptpd)

# Show configuration summary
message(STATUS "")
message(STATUS "====================================")
message(STATUS "PTPd Configuration (Phase 4 - Configuration Options)")
message(STATUS "====================================")
message(STATUS "  Build Type:        ${CMAKE_BUILD_TYPE}")
message(STATUS "  C Compiler:        ${CMAKE_C_COMPILER}")
message(STATUS "  C Standard:        C${CMAKE_C_STANDARD}")
message(STATUS "  Install Prefix:    ${CMAKE_INSTALL_PREFIX}")
message(STATUS "  Math Library:      ${MATH_LIBRARY}")
if(RT_LIBRARY)
message(STATUS "  RT Library:        ${RT_LIBRARY}")
endif()
message(STATUS "====================================")
message(STATUS "")
