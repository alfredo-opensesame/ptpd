# Source files for ptpd2 (from src/Makefile.am)

# Base sources (always compiled)
set(PTPD2_BASE_SOURCES
    arith.c
    bmc.c
    display.c
    management.c
    signaling.c
    protocol.c
    ptpd.c
    ptp_timers.c
    timingdomain.c
    dep/ipv4_acl.c
    dep/msg.c
    dep/net.c
    dep/eventtimer.c
    dep/servo.c
    dep/iniparser/dictionary.c
    dep/iniparser/iniparser.c
    dep/configdefaults.c
    dep/daemonconfig.c
    dep/startup.c
    dep/sys.c
    dep/ntpengine/ntp_isc_md5.c
    dep/ntpengine/ntpdcontrol.c
    dep/alarms.c
)

# Phase 4: STATISTICS sources - conditional based on ENABLE_STATISTICS option
if(ENABLE_STATISTICS)
    set(PTPD2_STATISTICS_SOURCES
        dep/statistics.c
        dep/outlierfilter.c
    )
else()
    set(PTPD2_STATISTICS_SOURCES "")
endif()

# Phase 4: POSIX_TIMERS sources - conditional based on ENABLE_POSIX_TIMERS option
if(ENABLE_POSIX_TIMERS)
    set(PTPD2_TIMER_SOURCES
        dep/eventtimer_posix.c
    )
else()
    # Use itimer fallback
    set(PTPD2_TIMER_SOURCES
        dep/eventtimer_itimer.c
    )
endif()

# Phase 4: SW_CLOCK sources - conditional based on ENABLE_SW_CLOCK option
if(ENABLE_SW_CLOCK)
    # TODO: Add SW_CLOCK-specific sources when implementing Phase 4
    # From autotools: libcck dep/sw_clock/*.c
    message(WARNING "SW_CLOCK support not yet fully implemented in CMake")
    set(PTPD2_SW_CLOCK_SOURCES "")
else()
    set(PTPD2_SW_CLOCK_SOURCES "")
endif()

# Phase 3: SNMP sources - conditional based on NETSNMP detection
if(PTPD_SNMP)
    set(PTPD2_SNMP_SOURCES
        dep/snmp.c
    )
else()
    set(PTPD2_SNMP_SOURCES "")
endif()

# Combine all sources
set(PTPD2_SOURCES
    ${PTPD2_BASE_SOURCES}
    ${PTPD2_STATISTICS_SOURCES}
    ${PTPD2_TIMER_SOURCES}
    ${PTPD2_SW_CLOCK_SOURCES}
    ${PTPD2_SNMP_SOURCES}
)

# Create executable
add_executable(ptpd2 ${PTPD2_SOURCES})

# Set target include directories
# Build directory MUST come first to find CMake-generated config.h
# before any config.h from old autotools builds
target_include_directories(ptpd2 PRIVATE
    ${PROJECT_BINARY_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/dep
)

# Add PCAP include directories if found
if(PTPD_PCAP AND PCAP_INCLUDE_DIRS)
    target_include_directories(ptpd2 PRIVATE ${PCAP_INCLUDE_DIRS})
endif()

# Add SNMP include directories if found
if(PTPD_SNMP AND NETSNMP_INCLUDE_DIRS)
    target_include_directories(ptpd2 PRIVATE ${NETSNMP_INCLUDE_DIRS})
endif()

# Set compiler definitions (matching autotools AM_CPPFLAGS)
target_compile_definitions(ptpd2 PRIVATE
    HAVE_CONFIG_H              # Signal that we have config.h
    DATADIR="${CMAKE_INSTALL_FULL_DATADIR}"  # Data directory
)

# Phase 4: MAX_UNICAST_DESTINATIONS is now in config.h via Options.cmake
# No need to define PTPD_STATISTICS here - it's in config.h

# Add PCAP preprocessor definitions if enabled
if(PTPD_PCAP)
    # PTPD_PCAP define is now in config.h via Options.cmake
    # Add PCAP-specific preprocessor definitions from pcap-config
    if(PCAP_DEFINITIONS)
        foreach(def ${PCAP_DEFINITIONS})
            # -U flags need to be added as compile options, not definitions
            if(def MATCHES "^-U")
                target_compile_options(ptpd2 PRIVATE ${def})
            elseif(def MATCHES "^-D")
                string(REGEX REPLACE "^-D" "" def_clean "${def}")
                target_compile_definitions(ptpd2 PRIVATE ${def_clean})
            else()
                # Already stripped -D in FindPCAP, so add as-is
                target_compile_definitions(ptpd2 PRIVATE ${def})
            endif()
        endforeach()
    endif()
endif()

# Add SNMP preprocessor definitions if enabled
if(PTPD_SNMP)
    # PTPD_SNMP define is now in config.h via Options.cmake
    # Add SNMP-specific preprocessor definitions from net-snmp-config
    if(NETSNMP_DEFINITIONS)
        foreach(def ${NETSNMP_DEFINITIONS})
            # -U flags need to be added as compile options, not definitions
            if(def MATCHES "^-U")
                target_compile_options(ptpd2 PRIVATE ${def})
            elseif(def MATCHES "^-D")
                string(REGEX REPLACE "^-D" "" def_clean "${def}")
                target_compile_definitions(ptpd2 PRIVATE ${def_clean})
            else()
                # Already stripped -D in FindNETSNMP, so add as-is
                target_compile_definitions(ptpd2 PRIVATE ${def})
            endif()
        endforeach()
    endif()
endif()

# Set compiler flags (matching autotools AM_CFLAGS)
target_compile_options(ptpd2 PRIVATE
    -Wall
    -fexceptions
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O2>
    $<$<CONFIG:RelWithDebInfo>:-g -O2>
)

# Add stack protector if supported (matching autotools check)
include(CheckCCompilerFlag)
check_c_compiler_flag(-fstack-protector HAS_STACK_PROTECTOR)
if(HAS_STACK_PROTECTOR)
    target_compile_options(ptpd2 PRIVATE -fstack-protector)
endif()

# Link libraries (matching autotools AM_LDFLAGS and AC_SEARCH_LIBS)
target_link_libraries(ptpd2 PRIVATE
    ${MATH_LIBRARY}
)

# Link PCAP libraries if enabled
if(PTPD_PCAP)
    target_link_libraries(ptpd2 PRIVATE ${PCAP_LIBRARIES})
endif()

# Link SNMP libraries if enabled (--agent-libs includes full link line)
if(PTPD_SNMP)
    # NETSNMP_LIBRARIES contains full link line from net-snmp-config --agent-libs
    # We need to parse it and add each component
    separate_arguments(SNMP_LINK_ARGS UNIX_COMMAND "${NETSNMP_LIBRARIES}")
    target_link_libraries(ptpd2 PRIVATE ${SNMP_LINK_ARGS})
endif()

if(RT_LIBRARY)
    target_link_libraries(ptpd2 PRIVATE ${RT_LIBRARY})
endif()

# config.h is now generated in root CMakeLists.txt (Phase 2)
# with full platform detection from cmake/CheckPlatform.cmake

# Install targets (matching autotools)
install(TARGETS ptpd2
    RUNTIME DESTINATION ${CMAKE_INSTALL_SBINDIR}
)

# Man pages and data files will be added in Phase 6
