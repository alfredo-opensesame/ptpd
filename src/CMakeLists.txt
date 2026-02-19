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
    ${PTPD2_SNMP_SOURCES}
)

# Check if building in library mode (for iOS or other library use cases)
# PTPD_LIBRARY_MODE is passed via CMAKE_C_FLAGS
if(CMAKE_C_FLAGS MATCHES "PTPD_LIBRARY_MODE")
    message(STATUS "Building ptpd as static library (PTPD_LIBRARY_MODE enabled)")
    add_library(ptpd2 STATIC ${PTPD2_SOURCES})
    set(PTPD_IS_LIBRARY TRUE)
else()
    message(STATUS "Building ptpd as executable (daemon mode)")
    add_executable(ptpd2 ${PTPD2_SOURCES})
    set(PTPD_IS_LIBRARY FALSE)
endif()

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

# Add SwClock include directories if enabled
if(BUILD_WITH_SWCLOCK)
    target_include_directories(ptpd2 PRIVATE 
        ${CMAKE_SOURCE_DIR}/libraries/swclock/src/sw_clock
    )
endif()

# Set compiler definitions (matching autotools AM_CPPFLAGS)
target_compile_definitions(ptpd2 PRIVATE
    HAVE_CONFIG_H              # Signal that we have config.h
    DATADIR="${CMAKE_INSTALL_FULL_DATADIR}"  # Data directory
)

# Add SwClock compile definition if enabled
if(BUILD_WITH_SWCLOCK)
    target_compile_definitions(ptpd2 PRIVATE PTPD_USE_SWCLOCK)
endif()

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

# Linux kernel headers (matching autotools configure.ac lines 59-77)
# Only needed on Linux if linux/net_tstamp.h not in standard location
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(NOT HAVE_LINUX_NET_TSTAMP_H)
        # Try RHEL/CentOS location
        execute_process(
            COMMAND uname -r
            OUTPUT_VARIABLE KERNEL_VERSION
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(EXISTS "/usr/src/kernels/${KERNEL_VERSION}/include")
            target_include_directories(ptpd2 PRIVATE "/usr/src/kernels/${KERNEL_VERSION}/include")
            message(STATUS "Using Linux kernel headers: /usr/src/kernels/${KERNEL_VERSION}/include")
        # Try Debian/Ubuntu location
        elseif(EXISTS "/usr/src/linux-headers-${KERNEL_VERSION}/include")
            target_include_directories(ptpd2 PRIVATE "/usr/src/linux-headers-${KERNEL_VERSION}/include")
            message(STATUS "Using Linux kernel headers: /usr/src/linux-headers-${KERNEL_VERSION}/include")
        endif()
    endif()
endif()

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

# Link SwClock if enabled
if(BUILD_WITH_SWCLOCK)
    target_link_libraries(ptpd2 PRIVATE swclock)
endif()

# config.h is now generated in root CMakeLists.txt (Phase 2)
# with full platform detection from cmake/CheckPlatform.cmake

# Phase 6: Install binary target (matching autotools)
# Skip installation for iOS (apps are bundled differently)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    install(TARGETS ptpd2
        RUNTIME DESTINATION ${CMAKE_INSTALL_SBINDIR}
        BUNDLE DESTINATION ${CMAKE_INSTALL_BINDIR}
    )
endif()

# Man pages and data files installed in root CMakeLists.txt

# ==============================================================================
# Optional Library Build
# ==============================================================================

# Option to build library (OFF by default to maintain current behavior)
option(BUILD_PTPD_LIBRARY "Build ptpd as a library in addition to executable" OFF)

if(BUILD_PTPD_LIBRARY)
    message(STATUS "Building ptpd library (static and shared)")
    
    # Helper function to configure library targets (avoid code duplication)
    function(configure_ptpd_library target_name)
        # Set target include directories
        target_include_directories(${target_name} PRIVATE
            ${PROJECT_BINARY_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/dep
        )
        
        # Add PCAP include directories if found
        if(PTPD_PCAP AND PCAP_INCLUDE_DIRS)
            target_include_directories(${target_name} PRIVATE ${PCAP_INCLUDE_DIRS})
        endif()
        
        # Add SNMP include directories if found
        if(PTPD_SNMP AND NETSNMP_INCLUDE_DIRS)
            target_include_directories(${target_name} PRIVATE ${NETSNMP_INCLUDE_DIRS})
        endif()
        
        # Add SwClock include directories if enabled
        if(BUILD_WITH_SWCLOCK)
            target_include_directories(${target_name} PRIVATE 
                ${CMAKE_SOURCE_DIR}/libraries/swclock/src/sw_clock
            )
        endif()
        
        # Set compiler definitions (same as ptpd2 but with PTPD_LIBRARY_MODE)
        target_compile_definitions(${target_name} PRIVATE
            HAVE_CONFIG_H
            DATADIR="${CMAKE_INSTALL_FULL_DATADIR}"
            PTPD_LIBRARY_MODE  # Enable library mode
        )
        
        # Add SwClock compile definition if enabled
        if(BUILD_WITH_SWCLOCK)
            target_compile_definitions(${target_name} PRIVATE PTPD_USE_SWCLOCK)
        endif()
        
        # Add PCAP preprocessor definitions if enabled
        if(PTPD_PCAP)
            if(PCAP_DEFINITIONS)
                foreach(def ${PCAP_DEFINITIONS})
                    if(def MATCHES "^-U")
                        target_compile_options(${target_name} PRIVATE ${def})
                    elseif(def MATCHES "^-D")
                        string(REGEX REPLACE "^-D" "" def_clean "${def}")
                        target_compile_definitions(${target_name} PRIVATE ${def_clean})
                    else()
                        target_compile_definitions(${target_name} PRIVATE ${def})
                    endif()
                endforeach()
            endif()
        endif()
        
        # Add SNMP preprocessor definitions if enabled
        if(PTPD_SNMP)
            if(NETSNMP_DEFINITIONS)
                foreach(def ${NETSNMP_DEFINITIONS})
                    if(def MATCHES "^-U")
                        target_compile_options(${target_name} PRIVATE ${def})
                    elseif(def MATCHES "^-D")
                        string(REGEX REPLACE "^-D" "" def_clean "${def}")
                        target_compile_definitions(${target_name} PRIVATE ${def_clean})
                    else()
                        target_compile_definitions(${target_name} PRIVATE ${def})
                    endif()
                endforeach()
            endif()
        endif()
        
        # Set compiler flags (matching ptpd2)
        target_compile_options(${target_name} PRIVATE
            -Wall
            -fexceptions
            $<$<CONFIG:Debug>:-g -O0>
            $<$<CONFIG:Release>:-O2>
            $<$<CONFIG:RelWithDebInfo>:-g -O2>
        )
        
        # Add stack protector if supported
        include(CheckCCompilerFlag)
        check_c_compiler_flag(-fstack-protector HAS_STACK_PROTECTOR)
        if(HAS_STACK_PROTECTOR)
            target_compile_options(${target_name} PRIVATE -fstack-protector)
        endif()
        
        # Link libraries (same as ptpd2 but with pthread required)
        target_link_libraries(${target_name} PRIVATE
            ${MATH_LIBRARY}
            pthread  # Required for library threading
        )
        
        # Link PCAP libraries if enabled
        if(PTPD_PCAP)
            target_link_libraries(${target_name} PRIVATE ${PCAP_LIBRARIES})
        endif()
        
        # Link SNMP libraries if enabled
        if(PTPD_SNMP)
            separate_arguments(SNMP_LINK_ARGS UNIX_COMMAND "${NETSNMP_LIBRARIES}")
            target_link_libraries(${target_name} PRIVATE ${SNMP_LINK_ARGS})
        endif()
        
        if(RT_LIBRARY)
            target_link_libraries(${target_name} PRIVATE ${RT_LIBRARY})
        endif()
        
        # Link SwClock if enabled
        if(BUILD_WITH_SWCLOCK)
            target_link_libraries(${target_name} PRIVATE swclock)
        endif()
    endfunction()
    
    # Build static library
    add_library(ptpd-static STATIC ${PTPD2_SOURCES})
    set_target_properties(ptpd-static PROPERTIES OUTPUT_NAME ptpd)
    configure_ptpd_library(ptpd-static)
    
    # Build shared library
    add_library(ptpd-shared SHARED ${PTPD2_SOURCES})
    set_target_properties(ptpd-shared PROPERTIES 
        OUTPUT_NAME ptpd
        VERSION ${PROJECT_VERSION}
        SOVERSION 2
    )
    configure_ptpd_library(ptpd-shared)
    
    # Install libraries
    install(TARGETS ptpd-static ptpd-shared
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )
    
    # Install public headers
    install(FILES 
        ptpdlib.h
        ptpd.h
        datatypes.h
        constants.h
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )
    
    message(STATUS "Library will be installed to: ${CMAKE_INSTALL_LIBDIR}")
    message(STATUS "Headers will be installed to: ${CMAKE_INSTALL_INCLUDEDIR}")
endif()
