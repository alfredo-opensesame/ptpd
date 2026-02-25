# FindPCAP.cmake - Find PCAP library using pcap-config or fallback
# This module matches the autotools --with-pcap-config behavior
#
# Outputs:
#   PCAP_FOUND          - System has PCAP
#   PCAP_INCLUDE_DIRS   - PCAP include directories
#   PCAP_LIBRARIES      - PCAP libraries
#   PCAP_CFLAGS         - PCAP compiler flags
#   PCAP_DEFINITIONS    - PCAP preprocessor definitions

# Option to specify pcap-config path (matching --with-pcap-config)
set(PCAP_CONFIG "pcap-config" CACHE STRING "Path to pcap-config (or name to search in PATH)")

# Try to find pcap-config
find_program(PCAP_CONFIG_EXECUTABLE
    NAMES ${PCAP_CONFIG} pcap-config
    DOC "pcap-config executable"
)

if(PCAP_CONFIG_EXECUTABLE)
    message(STATUS "Found pcap-config: ${PCAP_CONFIG_EXECUTABLE}")

    # Get libraries from pcap-config --libs
    execute_process(
        COMMAND ${PCAP_CONFIG_EXECUTABLE} --libs
        OUTPUT_VARIABLE PCAP_LIBS_RAW
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE PCAP_CONFIG_LIBS_RESULT
    )

    # Get compiler flags from pcap-config --cflags
    execute_process(
        COMMAND ${PCAP_CONFIG_EXECUTABLE} --cflags
        OUTPUT_VARIABLE PCAP_CFLAGS_RAW
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE PCAP_CONFIG_CFLAGS_RESULT
    )

    if(PCAP_CONFIG_LIBS_RESULT EQUAL 0 AND PCAP_CONFIG_CFLAGS_RESULT EQUAL 0)
        # Parse libraries (remove -l prefix and -L paths)
        string(REGEX REPLACE "-l([^ ]+)" "\\1" PCAP_LIBRARIES "${PCAP_LIBS_RAW}")
        string(REGEX REPLACE "-L([^ ]+)" "" PCAP_LIBRARIES "${PCAP_LIBRARIES}")
        string(STRIP "${PCAP_LIBRARIES}" PCAP_LIBRARIES)

        # Separate CFLAGS into CPPFLAGS (preprocessor) and CFLAGS (compiler)
        # CPPFLAGS: -D, -I, -F, -U
        # CFLAGS: everything else
        set(PCAP_DEFINITIONS "")
        set(PCAP_INCLUDE_DIRS "")
        set(PCAP_CFLAGS "")

        string(REPLACE " " ";" CFLAGS_LIST "${PCAP_CFLAGS_RAW}")
        foreach(flag ${CFLAGS_LIST})
            if(flag MATCHES "^-D" OR flag MATCHES "^-U")
                list(APPEND PCAP_DEFINITIONS ${flag})
            elseif(flag MATCHES "^-I")
                string(REGEX REPLACE "^-I" "" inc_dir "${flag}")
                list(APPEND PCAP_INCLUDE_DIRS ${inc_dir})
            elseif(flag MATCHES "^-F")
                list(APPEND PCAP_CFLAGS ${flag})
            else()
                list(APPEND PCAP_CFLAGS ${flag})
            endif()
        endforeach()

        # Convert library names to full paths if possible
        set(PCAP_LIBRARIES_LIST "")
        foreach(lib ${PCAP_LIBRARIES})
            find_library(PCAP_${lib}_LIBRARY NAMES ${lib})
            if(PCAP_${lib}_LIBRARY)
                list(APPEND PCAP_LIBRARIES_LIST ${PCAP_${lib}_LIBRARY})
            else()
                list(APPEND PCAP_LIBRARIES_LIST ${lib})
            endif()
        endforeach()
        set(PCAP_LIBRARIES ${PCAP_LIBRARIES_LIST})

        set(PCAP_CONFIG_METHOD "pcap-config")
    else()
        message(WARNING "pcap-config found but failed to execute")
        set(PCAP_CONFIG_EXECUTABLE "")
    endif()
endif()

# Fallback: try to find libpcap directly if pcap-config not found or failed
if(NOT PCAP_CONFIG_EXECUTABLE)
    message(STATUS "pcap-config not found, trying direct library search")

    find_library(PCAP_LIBRARY
        NAMES pcap
        PATHS /usr/lib /usr/local/lib /opt/local/lib
        DOC "PCAP library"
    )

    find_path(PCAP_INCLUDE_DIR
        NAMES pcap/pcap.h pcap.h
        PATHS /usr/include /usr/local/include /opt/local/include
        DOC "PCAP include directory"
    )

    if(PCAP_LIBRARY)
        set(PCAP_LIBRARIES ${PCAP_LIBRARY})
        set(PCAP_INCLUDE_DIRS ${PCAP_INCLUDE_DIR})
        set(PCAP_DEFINITIONS "")
        set(PCAP_CFLAGS "")
        set(PCAP_CONFIG_METHOD "direct search")
    endif()
endif()

# Check for PCAP headers (pcap/pcap.h or pcap.h)
include(CheckIncludeFile)
set(CMAKE_REQUIRED_INCLUDES ${PCAP_INCLUDE_DIRS})
check_include_file(pcap/pcap.h HAVE_PCAP_PCAP_H)
check_include_file(pcap.h HAVE_PCAP_H)

# Make header detection results available globally for config.h
# check_include_file sets cache variables, but we need to ensure they're propagated
set(HAVE_PCAP_PCAP_H ${HAVE_PCAP_PCAP_H} CACHE INTERNAL "")
set(HAVE_PCAP_H ${HAVE_PCAP_H} CACHE INTERNAL "")

# Determine if PCAP is found
if(PCAP_LIBRARIES AND (HAVE_PCAP_PCAP_H OR HAVE_PCAP_H))
    set(PCAP_FOUND TRUE)
else()
    set(PCAP_FOUND FALSE)
endif()

# Standard package handling
include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(PCAP
    REQUIRED_VARS PCAP_LIBRARIES
    FOUND_VAR PCAP_FOUND
)

if(PCAP_FOUND)
    message(STATUS "PCAP detection method: ${PCAP_CONFIG_METHOD}")
    message(STATUS "PCAP libraries: ${PCAP_LIBRARIES}")
    if(PCAP_INCLUDE_DIRS)
        message(STATUS "PCAP include dirs: ${PCAP_INCLUDE_DIRS}")
    endif()
    if(PCAP_DEFINITIONS)
        message(STATUS "PCAP definitions: ${PCAP_DEFINITIONS}")
    endif()
endif()

mark_as_advanced(
    PCAP_CONFIG_EXECUTABLE
    PCAP_LIBRARY
    PCAP_INCLUDE_DIR
)
