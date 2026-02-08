# CMake Module Documentation

This directory contains CMake modules that implement platform detection, library detection, and configuration option handling for the PTPd build system.

## Module Overview

### CheckPlatform.cmake

**Purpose**: Comprehensive platform detection matching autotools' AC_CHECK_* macros.

**Functions**:
- Header file detection (~60 headers)
- Function availability checks (~28 functions)
- Structure member checks (~8 members)
- Symbol declaration checks (MSG_ERRQUEUE, POSIX_TIMERS_SUPPORTED)
- Type size detection (uint8_t, uint32_t, size_t, etc.)
- Platform-specific definitions (__APPLE__, __linux__)

**Key Checks**:
```cmake
# Header checks with dependencies
check_include_file(sys/time.h HAVE_SYS_TIME_H)
check_include_file(netinet/in.h HAVE_NETINET_IN_H)

# Function checks
check_function_exists(clock_gettime HAVE_CLOCK_GETTIME)
check_function_exists(timer_create HAVE_TIMER_CREATE)

# Struct member checks
check_struct_has_member("struct sockaddr_in" sin_len
                        "netinet/in.h" HAVE_STRUCT_SOCKADDR_IN_SIN_LEN)

# Symbol declarations
check_symbol_exists(MSG_ERRQUEUE "sys/socket.h" HAVE_DECL_MSG_ERRQUEUE)
```

**Platform-Specific Behavior**:
- **macOS**: Detects BSD-style networking, no netinet/ether.h
- **Linux**: Searches for kernel headers (SO_TIMESTAMPING support)
  - Checks `/usr/src/linux-headers-$(uname -r)/include`
  - Checks `/usr/src/kernels/$(uname -r)/include`
- **All platforms**: Comprehensive POSIX timer detection

**Output**: Sets HAVE_* variables used in config.h.in

### FindPCAP.cmake

**Purpose**: Detect and configure libpcap, matching autotools' pcap-config logic.

**Detection Strategy**:
1. First tries `pcap-config` tool (preferred, matches autotools)
2. Falls back to `find_library()` if pcap-config not found
3. Validates header availability (pcap/pcap.h or pcap.h)

**Configuration Extraction**:
```cmake
# Get flags from pcap-config
execute_process(COMMAND pcap-config --cflags OUTPUT_VARIABLE PCAP_CFLAGS)
execute_process(COMMAND pcap-config --libs OUTPUT_VARIABLE PCAP_LIBS)

# Parse flags into components
# -D → definitions
# -I → include directories
# -F → framework directories (macOS)
# -U → undefine flags (as compiler options)
# -l, .a, .dylib, .so → libraries
```

**Exported Variables**:
- `PCAP_FOUND` - TRUE if PCAP detected
- `PCAP_INCLUDE_DIRS` - Include directories
- `PCAP_LIBRARIES` - Libraries to link
- `PCAP_DEFINITIONS` - Preprocessor definitions
- `PCAP_COMPILE_OPTIONS` - Additional compiler flags

**Usage**:
```cmake
find_package(PCAP REQUIRED)
target_include_directories(ptpd2 PRIVATE ${PCAP_INCLUDE_DIRS})
target_link_libraries(ptpd2 PRIVATE ${PCAP_LIBRARIES})
target_compile_definitions(ptpd2 PRIVATE ${PCAP_DEFINITIONS})
target_compile_options(ptpd2 PRIVATE ${PCAP_COMPILE_OPTIONS})
```

**Special Handling**:
- `-U` flags are treated as compiler options, not definitions
- Framework directories (`-F`) handled separately on macOS
- Graceful fallback if pcap-config not available

### FindNETSNMP.cmake

**Purpose**: Detect and configure Net-SNMP, using net-snmp-config tool.

**Detection Strategy**:
1. Find `net-snmp-config` tool (required for SNMP support)
2. Extract agent libraries and base flags
3. Validate net-snmp/net-snmp-config.h header
4. Parse complex flag combinations

**Configuration Extraction**:
```cmake
# Get libraries and flags from net-snmp-config
execute_process(COMMAND net-snmp-config --agent-libs
                OUTPUT_VARIABLE NETSNMP_AGENT_LIBS)
execute_process(COMMAND net-snmp-config --base-cflags
                OUTPUT_VARIABLE NETSNMP_BASE_CFLAGS)

# Parse complex output like:
# "-lnetsnmpmibs -lnetsnmpagent -lnetsnmp -lcrypto -lssl"
# "-I/usr/include -Dlinux -D_REENTRANT"
```

**Exported Variables**:
- `NETSNMP_FOUND` - TRUE if Net-SNMP detected
- `NETSNMP_INCLUDE_DIRS` - Include directories
- `NETSNMP_LIBRARIES` - Full library link line (preserves order)
- `NETSNMP_DEFINITIONS` - Preprocessor definitions
- `NETSNMP_CFLAGS` - Additional compiler flags

**Usage**:
```cmake
find_package(NETSNMP)
if(NETSNMP_FOUND)
  target_include_directories(ptpd2 PRIVATE ${NETSNMP_INCLUDE_DIRS})
  target_link_libraries(ptpd2 PRIVATE ${NETSNMP_LIBRARIES})
  target_compile_definitions(ptpd2 PRIVATE ${NETSNMP_DEFINITIONS})
endif()
```

**Complexity Notes**:
- Net-SNMP has complex dependencies (crypto, ssl, etc.)
- Library order matters for linking
- Must preserve exact `--agent-libs` output
- Platform-specific library paths

### Options.cmake

**Purpose**: Define all user-configurable options matching autotools configure flags.

**Option Categories**:

1. **Feature Toggles** (ON/OFF)
   ```cmake
   option(ENABLE_POSIX_TIMERS "Use POSIX timers" AUTO)
   option(ENABLE_STATISTICS "Enable statistics collection" ON)
   option(ENABLE_DAEMON "Enable daemon mode" ON)
   option(ENABLE_RUNTIME_DEBUG "Enable runtime debug control" OFF)
   option(ENABLE_EXPERIMENTAL "Enable experimental options" OFF)
   option(ENABLE_SLAVE_ONLY "Enable slave-only mode" OFF)
   option(ENABLE_SW_CLOCK "Enable software clock" OFF)
   ```

2. **Library Enable/Disable**
   ```cmake
   option(ENABLE_PCAP "Enable PCAP support" AUTO)
   option(ENABLE_SNMP "Enable SNMP support" OFF)
   ```

3. **Debug Levels** (enum-like)
   ```cmake
   set(DEBUG_LEVEL "none" CACHE STRING "Debug level: none|basic|medium|all")
   set_property(CACHE DEBUG_LEVEL PROPERTY STRINGS none basic medium all)
   ```

4. **Numeric Parameters** (validated range)
   ```cmake
   set(MAX_UNICAST_DESTINATIONS 128 CACHE STRING "Max unicast destinations (16-2048)")
   # Validation:
   if(MAX_UNICAST_DESTINATIONS LESS 16 OR MAX_UNICAST_DESTINATIONS GREATER 2048)
     message(FATAL_ERROR "MAX_UNICAST_DESTINATIONS must be between 16 and 2048")
   endif()
   ```

**Smart Defaults**:
- `ENABLE_POSIX_TIMERS`: Auto-detects based on platform support
- `ENABLE_PCAP`: Auto-enables if pcap-config found
- `ENABLE_SNMP`: Defaults to OFF (requires explicit user enablement)
- `ENABLE_SO_TIMESTAMPING`: Auto-detects Linux kernel headers

**Mutual Exclusivity**:
```cmake
# DEBUG_LEVEL and ENABLE_RUNTIME_DEBUG are mutually exclusive
if(NOT DEBUG_LEVEL STREQUAL "none" AND ENABLE_RUNTIME_DEBUG)
  message(FATAL_ERROR
    "DEBUG_LEVEL and ENABLE_RUNTIME_DEBUG are mutually exclusive")
endif()
```

**Option Mapping to Defines**:
```cmake
# In config.h.in:
#cmakedefine PTPD_STATISTICS
#cmakedefine SW_CLOCK_ENABLED
#cmakedefine PTPD_SLAVE_ONLY
#cmakedefine RUNTIME_DEBUG
#define PTPD_UNICAST_MAX @MAX_UNICAST_DESTINATIONS@
```

**Configuration Summary**:
Displays all options at end of CMake configuration:
```
-- Configuration Summary:
--   Build Type:               Debug
--   POSIX Timers:             ON
--   PCAP Support:             ON
--   SNMP Support:             OFF
--   Statistics:               ON
--   Debug Level:              none
--   Runtime Debug:            OFF
--   Slave Only:               OFF
--   Daemon Mode:              ON
--   Max Unicast:              128
```

## File Dependencies

```
CMakeLists.txt (root)
  ├─ cmake/CheckPlatform.cmake    # Must run FIRST (detects capabilities)
  ├─ cmake/FindPCAP.cmake         # Called by find_package(PCAP)
  ├─ cmake/FindNETSNMP.cmake      # Called by find_package(NETSNMP)
  └─ cmake/Options.cmake          # Must run AFTER library detection

config.h.in
  └─ Uses variables set by CheckPlatform.cmake and Options.cmake
     Configured to: ${PROJECT_BINARY_DIR}/config.h
```

## Order of Execution

**Critical**: Modules must be processed in this order:

1. **CheckPlatform.cmake** - Detect all platform capabilities
   - Sets HAVE_* variables
   - Detects POSIX timer support
   - Finds kernel headers (Linux)

2. **find_package(PCAP)** - Detect PCAP library
   - Uses FindPCAP.cmake
   - Sets PCAP_FOUND
   - Extracts PCAP flags

3. **find_package(NETSNMP)** - Detect Net-SNMP library
   - Uses FindNETSNMP.cmake
   - Sets NETSNMP_FOUND
   - Extracts SNMP flags

4. **Options.cmake** - Process user options
   - Uses detection results from steps 1-3
   - Sets smart defaults based on capabilities
   - Validates option combinations

5. **configure_file(config.h.in)** - Generate config.h
   - Uses all variables from steps 1-4
   - Creates final configuration header

**Why Order Matters**:
- Options.cmake needs to know if POSIX timers are supported (from CheckPlatform)
- Options.cmake needs to know if PCAP was found (from FindPCAP)
- config.h generation needs all variables set

## Autotools Equivalence

### configure.ac Section Mapping

| configure.ac Lines | CMake Module | Purpose |
|-------------------|--------------|---------|
| 48-89 | CheckPlatform.cmake | Header checks (AC_CHECK_HEADERS) |
| 92-173 | CheckPlatform.cmake | Function checks (AC_CHECK_FUNCS) |
| 190-225 | CheckPlatform.cmake | Member checks (AC_CHECK_MEMBERS) |
| 246-289 | CheckPlatform.cmake | POSIX timer detection |
| 290-460 | FindPCAP.cmake | PCAP detection (pcap-config) |
| 460-600 | FindNETSNMP.cmake | Net-SNMP detection (net-snmp-config) |
| 621-920 | Options.cmake | AC_ARG_ENABLE options |

### Macro Equivalence

| Autotools | CMake | Module |
|-----------|-------|--------|
| `AC_CHECK_HEADERS([sys/time.h])` | `check_include_file(sys/time.h HAVE_SYS_TIME_H)` | CheckPlatform |
| `AC_CHECK_FUNCS([clock_gettime])` | `check_function_exists(clock_gettime HAVE_CLOCK_GETTIME)` | CheckPlatform |
| `AC_CHECK_MEMBERS([struct sockaddr_in.sin_len])` | `check_struct_has_member(...)` | CheckPlatform |
| `AC_ARG_ENABLE([slave-only])` | `option(ENABLE_SLAVE_ONLY ...)` | Options |
| `AC_SEARCH_LIBS([pow], [m])` | `find_library(LIBM m)` | CheckPlatform |

## Adding New Options

To add a new configuration option:

1. **Add to Options.cmake**:
   ```cmake
   option(ENABLE_NEW_FEATURE "Enable new feature" OFF)
   ```

2. **Add to config.h.in**:
   ```cmake
   #cmakedefine NEW_FEATURE_ENABLED
   ```

3. **Use in CMakeLists.txt**:
   ```cmake
   if(ENABLE_NEW_FEATURE)
     target_compile_definitions(ptpd2 PRIVATE NEW_FEATURE_ENABLED)
     target_sources(ptpd2 PRIVATE src/dep/new_feature.c)
   endif()
   ```

4. **Add to configuration summary** in Options.cmake:
   ```cmake
   message(STATUS "  New Feature:              ${ENABLE_NEW_FEATURE}")
   ```

5. **Update README.cmake.md** with documentation

## Testing

To test individual modules:

```bash
# Test platform detection
cmake -B build-test -DCMAKE_BUILD_TYPE=Debug
grep HAVE_ build-test/config.h | sort

# Test PCAP detection
cmake -B build-test -DENABLE_PCAP=ON
grep PCAP build-test/CMakeCache.txt

# Test option validation
cmake -B build-test -DMAX_UNICAST_DESTINATIONS=99999
# Should fail with range error

# Test configuration combinations
cmake -B build-test -DENABLE_SLAVE_ONLY=ON -DENABLE_SW_CLOCK=ON
cmake --build build-test
```

## Debugging

### View All CMake Variables
```bash
cmake -B build -LAH
```

### View Specific Module Output
```cmake
# In module file, add:
message(STATUS "PCAP_FOUND = ${PCAP_FOUND}")
message(STATUS "PCAP_LIBRARIES = ${PCAP_LIBRARIES}")
```

### Test Find Module in Isolation
```bash
cmake --find-package \
      -DNAME=PCAP \
      -DCOMPILER_ID=GNU \
      -DLANGUAGE=C \
      -DMODE=EXIST
```

## Contributing

When modifying CMake modules:

1. **Maintain autotools equivalence** - Compare configure.ac carefully
2. **Test on multiple platforms** - Linux, macOS, FreeBSD
3. **Validate all configurations** - Run test matrix
4. **Update documentation** - Both this file and README.cmake.md
5. **Check binary equivalence** - Use scripts/compare-binaries.sh

## References

- [CMake Documentation](https://cmake.org/documentation/)
- [CMake Check Modules](https://cmake.org/cmake/help/latest/module/CheckIncludeFile.html)
- [CMake Find Modules](https://cmake.org/cmake/help/latest/manual/cmake-developer.7.html#find-modules)
- [BUILD.md](../BUILD.md) - Comprehensive build guide

---

Last Updated: February 8, 2026
