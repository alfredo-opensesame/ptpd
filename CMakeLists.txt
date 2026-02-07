cmake_minimum_required(VERSION 3.15)

project(ptpd VERSION 2.3.1 LANGUAGES C)

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
find_package(PCAP)

# Phase 3: Find Net-SNMP library using FindNETSNMP module (net-snmp-config)
# User can disable with -DENABLE_SNMP=OFF
find_package(NETSNMP)

# Phase 4: Configuration options (--enable-xxx / --disable-xxx flags)
# Must come after library detection so we know what's available
# Sets ENABLE_* options and validates their values
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/Options.cmake)

# Generate config.h from template (with full platform detection + options)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/config.h.in
    ${PROJECT_BINARY_DIR}/config.h
    @ONLY
)

# Set install directories (matching autotools defaults)
include(GNUInstallDirs)

# Add source directory
add_subdirectory(src)

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

