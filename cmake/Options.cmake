# Options.cmake - Build configuration options for ptpd
# Matches autotools configure.ac option behavior

# Phase 4: Configuration options matching autotools --enable/--disable flags

# Note: Some options have smart defaults based on platform detection.
# These are set after platform detection completes.

# ===================================================================
# Option: POSIX Timers (--enable-posix-timers / --disable-posix-timers)
# Default: ON if POSIX timers supported, OFF otherwise
# User can force OFF with -DENABLE_POSIX_TIMERS=OFF
# ===================================================================
# This will be set to the detected value from CheckPlatform.cmake
# User can override to OFF
if(NOT DEFINED ENABLE_POSIX_TIMERS)
    if(HAVE_DECL_POSIX_TIMERS_SUPPORTED)
        set(ENABLE_POSIX_TIMERS_DEFAULT ON)
    else()
        set(ENABLE_POSIX_TIMERS_DEFAULT OFF)
    endif()
    option(ENABLE_POSIX_TIMERS "Enable POSIX timer support (auto-detected by default)" ${ENABLE_POSIX_TIMERS_DEFAULT})
else()
    option(ENABLE_POSIX_TIMERS "Enable POSIX timer support (auto-detected by default)" ${ENABLE_POSIX_TIMERS})
endif()

# ===================================================================
# Option: PCAP Support (--enable-pcap / --disable-pcap)
# Default: ON if pcap-config found, OFF otherwise
# ===================================================================
if(PCAP_FOUND)
    set(ENABLE_PCAP_DEFAULT ON)
else()
    set(ENABLE_PCAP_DEFAULT OFF)
endif()
option(ENABLE_PCAP "Enable PCAP support for packet capture" ${ENABLE_PCAP_DEFAULT})

# Override PTPD_PCAP based on option
if(ENABLE_PCAP AND PCAP_FOUND)
    set(PTPD_PCAP TRUE)
else()
    set(PTPD_PCAP FALSE)
endif()

# ===================================================================
# Option: SNMP Support (--enable-snmp / --disable-snmp)
# Default: ON if net-snmp-config found, OFF otherwise
# ===================================================================
if(NETSNMP_FOUND)
    set(ENABLE_SNMP_DEFAULT ON)
else()
    set(ENABLE_SNMP_DEFAULT OFF)
endif()
option(ENABLE_SNMP "Enable SNMP support" ${ENABLE_SNMP_DEFAULT})

# Override PTPD_SNMP based on option
if(ENABLE_SNMP AND NETSNMP_FOUND)
    set(PTPD_SNMP TRUE)
else()
    set(PTPD_SNMP FALSE)
endif()

# ===================================================================
# Option: Runtime Debug (--enable-runtime-debug)
# Default: OFF
# Mutually exclusive with DEBUG_LEVEL
# ===================================================================
option(ENABLE_RUNTIME_DEBUG "Enable all runtime debug messages" OFF)

# ===================================================================
# Option: Debug Level (--enable-debug-level=basic/medium/all)
# Default: none
# Mutually exclusive with ENABLE_RUNTIME_DEBUG
# ===================================================================
set(DEBUG_LEVEL "none" CACHE STRING "Debug message level: none, basic, medium, all")
set_property(CACHE DEBUG_LEVEL PROPERTY STRINGS none basic medium all)

# Validate mutual exclusivity
if(ENABLE_RUNTIME_DEBUG AND NOT DEBUG_LEVEL STREQUAL "none")
    message(WARNING "ENABLE_RUNTIME_DEBUG and DEBUG_LEVEL are mutually exclusive. Using ENABLE_RUNTIME_DEBUG.")
    set(DEBUG_LEVEL "none" CACHE STRING "Debug message level" FORCE)
endif()

# Set defines for config.h based on debug level
if(DEBUG_LEVEL STREQUAL "basic")
    set(DEBUG_LEVEL_BASIC ON)
elseif(DEBUG_LEVEL STREQUAL "medium")
    set(DEBUG_LEVEL_MEDIUM ON)
elseif(DEBUG_LEVEL STREQUAL "all")
    set(DEBUG_LEVEL_ALL ON)
endif()

# ===================================================================
# Option: Daemon Mode (--enable-daemon / --disable-daemon)
# Default: ON
# ===================================================================
option(ENABLE_DAEMON "Enable daemon mode" ON)

# ===================================================================
# Option: Experimental Options (--enable-experimental-options)
# Default: OFF
# ===================================================================
option(ENABLE_EXPERIMENTAL "Enable experimental options" OFF)

# ===================================================================
# Option: Statistics (--enable-statistics / --disable-statistics)
# Default: ON
# ===================================================================
option(ENABLE_STATISTICS "Enable realtime statistics support" ON)

# ===================================================================
# Option: Software Clock (--enable-sw-clock)
# Default: OFF
# ===================================================================
option(ENABLE_SW_CLOCK "Enable software clock implementation" OFF)

# ===================================================================
# Option: SO_TIMESTAMPING (--enable-so-timestamping / --disable-so-timestamping)
# Default: ON on Linux, N/A elsewhere
# ===================================================================
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    option(ENABLE_SO_TIMESTAMPING "Enable SO_TIMESTAMPING support on Linux" ON)
else()
    set(ENABLE_SO_TIMESTAMPING OFF)
endif()

# ===================================================================
# Option: Slave Only Mode (--enable-slave-only)
# Default: OFF
# ===================================================================
option(ENABLE_SLAVE_ONLY "Enable slave-only mode" OFF)

# ===================================================================
# Option: Maximum Unicast Destinations (--with-max-unicast-destinations)
# Default: 128, Range: 16-2048
# ===================================================================
set(MAX_UNICAST_DESTINATIONS 128 CACHE STRING "Maximum unicast destination table size (16-2048)")

# Validate range
if(MAX_UNICAST_DESTINATIONS LESS 16)
    message(WARNING "MAX_UNICAST_DESTINATIONS too small, setting to 16")
    set(MAX_UNICAST_DESTINATIONS 16 CACHE STRING "Maximum unicast destination table size" FORCE)
endif()
if(MAX_UNICAST_DESTINATIONS GREATER 2048)
    message(WARNING "MAX_UNICAST_DESTINATIONS too large, setting to 2048")
    set(MAX_UNICAST_DESTINATIONS 2048 CACHE STRING "Maximum unicast destination table size" FORCE)
endif()

# ===================================================================
# Display Configuration Summary
# ===================================================================
message(STATUS "")
message(STATUS "====================================")
message(STATUS "Build Options Summary")
message(STATUS "====================================")
message(STATUS "  ENABLE_POSIX_TIMERS:     ${ENABLE_POSIX_TIMERS}")
message(STATUS "  ENABLE_PCAP:             ${ENABLE_PCAP}")
message(STATUS "  ENABLE_SNMP:             ${ENABLE_SNMP}")
message(STATUS "  ENABLE_STATISTICS:       ${ENABLE_STATISTICS}")
message(STATUS "  ENABLE_SW_CLOCK:         ${ENABLE_SW_CLOCK}")
message(STATUS "  ENABLE_DAEMON:           ${ENABLE_DAEMON}")
message(STATUS "  ENABLE_EXPERIMENTAL:     ${ENABLE_EXPERIMENTAL}")
message(STATUS "  ENABLE_RUNTIME_DEBUG:    ${ENABLE_RUNTIME_DEBUG}")
message(STATUS "  DEBUG_LEVEL:             ${DEBUG_LEVEL}")
message(STATUS "  ENABLE_SLAVE_ONLY:       ${ENABLE_SLAVE_ONLY}")
message(STATUS "  ENABLE_SO_TIMESTAMPING:  ${ENABLE_SO_TIMESTAMPING}")
message(STATUS "  MAX_UNICAST_DESTINATIONS: ${MAX_UNICAST_DESTINATIONS}")
message(STATUS "====================================")
message(STATUS "")
