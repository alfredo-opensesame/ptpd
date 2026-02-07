cmake_minimum_required(VERSION 3.15)

project(ptpd VERSION 2.3.1 LANGUAGES C)

# Set C standard to C99 (matching autotools AC_PROG_CC_C99)
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# For Phase 1, we hardcode defaults matching autotools baseline:
# - PCAP: ON (found via pcap-config)
# - SNMP: OFF (for simplicity in Phase 1, will add in Phase 3)
# - STATISTICS: ON
# - POSIX_TIMERS: OFF (macOS default, use itimer)
# - SW_CLOCK: OFF
# - All other defaults from configure.ac

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

# Find PCAP library (matching autotools default)
# In Phase 1, use simple find_library (Phase 3 will add pcap-config support)
find_library(PCAP_LIBRARY pcap PATHS /usr/lib /usr/local/lib)
if(NOT PCAP_LIBRARY)
    message(FATAL_ERROR "PCAP library not found. Install libpcap-dev or disable PCAP support.")
endif()

# For now, assume PCAP headers are in standard location
include_directories(/usr/local/include)

# Set install directories (matching autotools defaults)
include(GNUInstallDirs)

# Add source directory
add_subdirectory(src)

# Show configuration summary
message(STATUS "====================================")
message(STATUS "PTPd Configuration (Phase 1 - Hardcoded)")
message(STATUS "====================================")
message(STATUS "  Build Type:        ${CMAKE_BUILD_TYPE}")
message(STATUS "  C Compiler:        ${CMAKE_C_COMPILER}")
message(STATUS "  C Standard:        C${CMAKE_C_STANDARD}")
message(STATUS "  Install Prefix:    ${CMAKE_INSTALL_PREFIX}")
message(STATUS "")
message(STATUS "  PCAP Support:      ON (${PCAP_LIBRARY})")
message(STATUS "  SNMP Support:      OFF (Phase 3)")
message(STATUS "  Statistics:        ON")
message(STATUS "  POSIX Timers:      OFF (using itimer)")
message(STATUS "  SW Clock:          OFF")
message(STATUS "  Daemon Mode:       ON")
message(STATUS "  Math Library:      ${MATH_LIBRARY}")
if(RT_LIBRARY)
message(STATUS "  RT Library:        ${RT_LIBRARY}")
endif()
message(STATUS "====================================")
