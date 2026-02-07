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

# Generate config.h from template (now with full platform detection)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/config.h.in
    ${PROJECT_BINARY_DIR}/config.h
    @ONLY
)

# For Phase 3, we use proper library detection modules:
# - PCAP: Use FindPCAP.cmake (pcap-config or fallback)
# - SNMP: Use FindNETSNMP.cmake (net-snmp-config)
# - STATISTICS: ON
# - POSIX_TIMERS: OFF (macOS default, use itimer)
# - SW_CLOCK: OFF
# - Phase 4 will add build options to enable/disable these

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
find_package(PCAP REQUIRED)
if(PCAP_FOUND)
    set(PTPD_PCAP TRUE)
else()
    message(FATAL_ERROR "PCAP library not found. Install libpcap-dev.")
endif()

# Phase 3: Find Net-SNMP library using FindNETSNMP module (net-snmp-config)
# For now, SNMP is optional (OFF by default like autotools when net-snmp-config not found)
find_package(NETSNMP)
if(NETSNMP_FOUND)
    set(PTPD_SNMP TRUE)
    message(STATUS "Net-SNMP support enabled")
else()
    set(PTPD_SNMP FALSE)
    message(STATUS "Net-SNMP not found, SNMP support disabled")
endif()

# Set install directories (matching autotools defaults)
include(GNUInstallDirs)

# Add source directory
add_subdirectory(src)

# Show configuration summary
message(STATUS "====================================")
message(STATUS "PTPd Configuration (Phase 3 - Library Detection)")
message(STATUS "====================================")
message(STATUS "  Build Type:        ${CMAKE_BUILD_TYPE}")
message(STATUS "  C Compiler:        ${CMAKE_C_COMPILER}")
message(STATUS "  C Standard:        C${CMAKE_C_STANDARD}")
message(STATUS "  Install Prefix:    ${CMAKE_INSTALL_PREFIX}")
message(STATUS "")
if(PTPD_PCAP)
message(STATUS "  PCAP Support:      ON")
if(PCAP_LIBRARIES)
message(STATUS "    Libraries:       ${PCAP_LIBRARIES}")
endif()
if(PCAP_INCLUDE_DIRS)
message(STATUS "    Include dirs:    ${PCAP_INCLUDE_DIRS}")
endif()
else()
message(STATUS "  PCAP Support:      OFF")
endif()
if(PTPD_SNMP)
message(STATUS "  SNMP Support:      ON")
if(NETSNMP_LIBRARIES)
message(STATUS "    Libraries:       ${NETSNMP_LIBRARIES}")
endif()
else()
message(STATUS "  SNMP Support:      OFF")
endif()
message(STATUS "  Statistics:        ON")
message(STATUS "  POSIX Timers:      OFF (using itimer)")
message(STATUS "  SW Clock:          OFF")
message(STATUS "  Daemon Mode:       ON")
message(STATUS "  Math Library:      ${MATH_LIBRARY}")
if(RT_LIBRARY)
message(STATUS "  RT Library:        ${RT_LIBRARY}")
endif()
message(STATUS "====================================")
