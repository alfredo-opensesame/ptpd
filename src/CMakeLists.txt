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

# Phase 1: Hardcoded defaults
# STATISTICS: ON (default in autotools)
set(PTPD2_STATISTICS_SOURCES
    dep/statistics.c
    dep/outlierfilter.c
)

# POSIX_TIMERS: OFF on macOS (default detected by autotools)
# Use itimer instead
set(PTPD2_TIMER_SOURCES
    dep/eventtimer_itimer.c
)

# SW_CLOCK: OFF (default)
# (no additional sources)

# SNMP: OFF for Phase 1 (will add in Phase 3)
# (no additional sources)

# Combine all sources
set(PTPD2_SOURCES
    ${PTPD2_BASE_SOURCES}
    ${PTPD2_STATISTICS_SOURCES}
    ${PTPD2_TIMER_SOURCES}
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

# Set compiler definitions (matching autotools AM_CPPFLAGS)
target_compile_definitions(ptpd2 PRIVATE
    HAVE_CONFIG_H              # Signal that we have config.h
    DATADIR="${CMAKE_INSTALL_FULL_DATADIR}"  # Data directory
    PTPD_PCAP                  # PCAP support enabled
    PTPD_STATISTICS            # Statistics enabled
    PTPD_UNICAST_MAX=128       # Default max unicast destinations
)

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
    ${PCAP_LIBRARY}
    ${MATH_LIBRARY}
)

if(RT_LIBRARY)
    target_link_libraries(ptpd2 PRIVATE ${RT_LIBRARY})
endif()

# Generate a minimal config.h for Phase 1
# In Phase 2, we'll properly detect all system headers and functions
# Get current date for BUILD_DATE
string(TIMESTAMP BUILD_DATE "%Y%m%d")
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/config.h.in.phase1
    ${PROJECT_BINARY_DIR}/config.h
    @ONLY
)

# Install targets (matching autotools)
install(TARGETS ptpd2
    RUNTIME DESTINATION ${CMAKE_INSTALL_SBINDIR}
)

# Man pages and data files will be added in Phase 6
