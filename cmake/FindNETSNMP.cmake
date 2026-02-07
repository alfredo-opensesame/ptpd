# FindNETSNMP.cmake - Find Net-SNMP library using net-snmp-config
# This module matches the autotools --with-net-snmp-config behavior
#
# Outputs:
#   NETSNMP_FOUND          - System has Net-SNMP
#   NETSNMP_INCLUDE_DIRS   - Net-SNMP include directories
#   NETSNMP_LIBRARIES      - Net-SNMP libraries
#   NETSNMP_CFLAGS         - Net-SNMP compiler flags
#   NETSNMP_DEFINITIONS    - Net-SNMP preprocessor definitions

# Option to specify net-snmp-config path (matching --with-net-snmp-config)
set(NETSNMP_CONFIG "net-snmp-config" CACHE STRING "Path to net-snmp-config (or name to search in PATH)")

# Try to find net-snmp-config
find_program(NETSNMP_CONFIG_EXECUTABLE
    NAMES ${NETSNMP_CONFIG} net-snmp-config
    DOC "net-snmp-config executable"
)

if(NETSNMP_CONFIG_EXECUTABLE)
    message(STATUS "Found net-snmp-config: ${NETSNMP_CONFIG_EXECUTABLE}")
    
    # Get agent libraries from net-snmp-config --agent-libs
    execute_process(
        COMMAND ${NETSNMP_CONFIG_EXECUTABLE} --agent-libs
        OUTPUT_VARIABLE NETSNMP_LIBS_RAW
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE NETSNMP_CONFIG_LIBS_RESULT
    )
    
    # Get base compiler flags from net-snmp-config --base-cflags
    execute_process(
        COMMAND ${NETSNMP_CONFIG_EXECUTABLE} --base-cflags
        OUTPUT_VARIABLE NETSNMP_CFLAGS_RAW
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE NETSNMP_CONFIG_CFLAGS_RESULT
    )
    
    if(NETSNMP_CONFIG_LIBS_RESULT EQUAL 0 AND NETSNMP_CONFIG_CFLAGS_RESULT EQUAL 0)
        # The --agent-libs output includes full link line with -L and -l flags
        # We'll use it as-is for linking
        set(NETSNMP_LIBRARIES ${NETSNMP_LIBS_RAW})
        
        # Separate CFLAGS into CPPFLAGS (preprocessor) and CFLAGS (compiler)
        # CPPFLAGS: -D, -I, -F, -U
        # CFLAGS: everything else
        set(NETSNMP_DEFINITIONS "")
        set(NETSNMP_INCLUDE_DIRS "")
        set(NETSNMP_CFLAGS "")
        
        string(REPLACE " " ";" CFLAGS_LIST "${NETSNMP_CFLAGS_RAW}")
        foreach(flag ${CFLAGS_LIST})
            if(flag MATCHES "^-D" OR flag MATCHES "^-U")
                list(APPEND NETSNMP_DEFINITIONS ${flag})
            elseif(flag MATCHES "^-I")
                string(REGEX REPLACE "^-I" "" inc_dir "${flag}")
                list(APPEND NETSNMP_INCLUDE_DIRS ${inc_dir})
            elseif(flag MATCHES "^-F")
                list(APPEND NETSNMP_CFLAGS ${flag})
            else()
                list(APPEND NETSNMP_CFLAGS ${flag})
            endif()
        endforeach()
        
        set(NETSNMP_CONFIG_METHOD "net-snmp-config")
    else()
        message(WARNING "net-snmp-config found but failed to execute")
        set(NETSNMP_CONFIG_EXECUTABLE "")
    endif()
endif()

# Without net-snmp-config, we cannot reliably find Net-SNMP
if(NOT NETSNMP_CONFIG_EXECUTABLE)
    message(STATUS "net-snmp-config not found, cannot detect Net-SNMP")
    set(NETSNMP_FOUND FALSE)
    return()
endif()

# Check for Net-SNMP header (net-snmp/net-snmp-config.h)
include(CheckIncludeFile)
set(CMAKE_REQUIRED_INCLUDES ${NETSNMP_INCLUDE_DIRS})

# Need to handle the definitions for the header check
set(CMAKE_REQUIRED_FLAGS "")
foreach(def ${NETSNMP_DEFINITIONS})
    set(CMAKE_REQUIRED_FLAGS "${CMAKE_REQUIRED_FLAGS} ${def}")
endforeach()

check_include_file(net-snmp/net-snmp-config.h HAVE_NET_SNMP_NET_SNMP_CONFIG_H)

# Determine if Net-SNMP is found
if(NETSNMP_LIBRARIES AND HAVE_NET_SNMP_NET_SNMP_CONFIG_H)
    set(NETSNMP_FOUND TRUE)
else()
    set(NETSNMP_FOUND FALSE)
endif()

# Standard package handling
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(NETSNMP
    REQUIRED_VARS NETSNMP_LIBRARIES HAVE_NET_SNMP_NET_SNMP_CONFIG_H
    FOUND_VAR NETSNMP_FOUND
)

if(NETSNMP_FOUND)
    message(STATUS "Net-SNMP detection method: ${NETSNMP_CONFIG_METHOD}")
    message(STATUS "Net-SNMP libraries: ${NETSNMP_LIBRARIES}")
    if(NETSNMP_INCLUDE_DIRS)
        message(STATUS "Net-SNMP include dirs: ${NETSNMP_INCLUDE_DIRS}")
    endif()
    if(NETSNMP_DEFINITIONS)
        message(STATUS "Net-SNMP definitions: ${NETSNMP_DEFINITIONS}")
    endif()
endif()

mark_as_advanced(
    NETSNMP_CONFIG_EXECUTABLE
)
