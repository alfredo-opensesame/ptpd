# CheckPlatform.cmake - Platform detection for ptpd
# This module performs all the system checks equivalent to autotools configure.ac
# Matches configure.ac header checks, function checks, type checks, and symbol checks

include(CheckIncludeFile)
include(CheckFunctionExists)
include(CheckSymbolExists)
include(CheckStructHasMember)
include(CheckTypeSize)
include(CheckCSourceCompiles)

message(STATUS "====================================")
message(STATUS "Platform Detection (Phase 2)")
message(STATUS "====================================")

# Build date
string(TIMESTAMP BUILD_DATE "%Y%m%d")

# Standard headers check
set(CMAKE_REQUIRED_DEFINITIONS -D_GNU_SOURCE)

# Basic header checks (no dependencies)
check_include_file(arpa/inet.h HAVE_ARPA_INET_H)
check_include_file(dlfcn.h HAVE_DLFCN_H)
check_include_file(endian.h HAVE_ENDIAN_H)
check_include_file(fcntl.h HAVE_FCNTL_H)
check_include_file(getopt.h HAVE_GETOPT_H)
check_include_file(glob.h HAVE_GLOB_H)
check_include_file(ifaddrs.h HAVE_IFADDRS_H)
check_include_file(inttypes.h HAVE_INTTYPES_H)
check_include_file(limits.h HAVE_LIMITS_H)
check_include_file(linux/net_tstamp.h HAVE_LINUX_NET_TSTAMP_H)
check_include_file(linux/rtc.h HAVE_LINUX_RTC_H)
check_include_file(machine/endian.h HAVE_MACHINE_ENDIAN_H)
check_include_file(netdb.h HAVE_NETDB_H)
check_include_file(netinet/in.h HAVE_NETINET_IN_H)
check_include_file(netinet/in_systm.h HAVE_NETINET_IN_SYSTM_H)
check_include_file(sched.h HAVE_SCHED_H)
check_include_file(stdbool.h HAVE_STDBOOL_H)
check_include_file(stdint.h HAVE_STDINT_H)
check_include_file(stdio.h HAVE_STDIO_H)
check_include_file(stdlib.h HAVE_STDLIB_H)
check_include_file(strings.h HAVE_STRINGS_H)
check_include_file(string.h HAVE_STRING_H)
check_include_file(syslog.h HAVE_SYSLOG_H)
check_include_file(sys/ioctl.h HAVE_SYS_IOCTL_H)
check_include_file(sys/isa_defs.h HAVE_SYS_ISA_DEFS_H)
check_include_file(sys/param.h HAVE_SYS_PARAM_H)
check_include_file(sys/select.h HAVE_SYS_SELECT_H)
check_include_file(sys/socket.h HAVE_SYS_SOCKET_H)
check_include_file(sys/sockio.h HAVE_SYS_SOCKIO_H)
check_include_file(sys/stat.h HAVE_SYS_STAT_H)
check_include_file(sys/timex.h HAVE_SYS_TIMEX_H)
check_include_file(sys/time.h HAVE_SYS_TIME_H)
check_include_file(sys/types.h HAVE_SYS_TYPES_H)
check_include_file(sys/uio.h HAVE_SYS_UIO_H)
check_include_file(unistd.h HAVE_UNISTD_H)
check_include_file(unix.h HAVE_UNIX_H)
check_include_file(utmpx.h HAVE_UTMPX_H)
check_include_file(utmp.h HAVE_UTMP_H)

# Math.h is required
check_include_file(math.h HAVE_MATH_H)
if(NOT HAVE_MATH_H)
    message(FATAL_ERROR "math.h is required to compile PTPd")
endif()

# Headers that require sys/param.h
if(HAVE_SYS_PARAM_H)
    set(CMAKE_EXTRA_INCLUDE_FILES sys/param.h)
    check_include_file(sys/cpuset.h HAVE_SYS_CPUSET_H)
    set(CMAKE_EXTRA_INCLUDE_FILES)
endif()

# net/if.h requires sys/socket.h and sys/types.h on some systems
if(HAVE_SYS_SOCKET_H AND HAVE_SYS_TYPES_H)
    set(CMAKE_REQUIRED_DEFINITIONS)
    check_c_source_compiles("
        #include <sys/types.h>
        #include <sys/socket.h>
        #include <net/if.h>
        int main() { return 0; }
    " HAVE_NET_IF_H)
endif()

# net/if_arp.h requires net/if.h
if(HAVE_NET_IF_H)
    check_c_source_compiles("
        #include <sys/types.h>
        #include <sys/socket.h>
        #include <net/if.h>
        #include <net/if_arp.h>
        int main() { return 0; }
    " HAVE_NET_IF_ARP_H)
endif()

# netinet/if_ether.h requires multiple headers
if(HAVE_SYS_SOCKET_H AND HAVE_ARPA_INET_H AND HAVE_NET_IF_H)
    check_c_source_compiles("
        #include <sys/types.h>
        #include <sys/socket.h>
        #include <arpa/inet.h>
        #ifdef HAVE_NET_IF_ARP_H
        #include <net/if_arp.h>
        #endif
        #include <net/if.h>
        #include <netinet/if_ether.h>
        int main() { return 0; }
    " HAVE_NETINET_IF_ETHER_H)
endif()

# net/if_ether.h requires sys/types.h and net/if.h
if(HAVE_SYS_TYPES_H AND HAVE_NET_IF_H)
    check_c_source_compiles("
        #include <sys/types.h>
        #include <net/if.h>
        #include <net/if_ether.h>
        int main() { return 0; }
    " HAVE_NET_IF_ETHER_H)
endif()

# netinet/ether.h (typically not on macOS)
check_include_file(netinet/ether.h HAVE_NETINET_ETHER_H)

# net/ethernet.h
check_include_file(net/ethernet.h HAVE_NET_ETHERNET_H)

# PCAP headers
check_include_file(pcap/pcap.h HAVE_PCAP_PCAP_H)
check_include_file(pcap.h HAVE_PCAP_H)

# Function checks
check_function_exists(clock_gettime HAVE_CLOCK_GETTIME)
check_function_exists(dup2 HAVE_DUP2)
check_function_exists(endutent HAVE_ENDUTENT)
check_function_exists(ftruncate HAVE_FTRUNCATE)
check_function_exists(gethostbyname2 HAVE_GETHOSTBYNAME2)
check_function_exists(getopt_long HAVE_GETOPT_LONG)
check_function_exists(gettimeofday HAVE_GETTIMEOFDAY)
check_function_exists(glob HAVE_GLOB)
check_function_exists(inet_ntoa HAVE_INET_NTOA)
check_function_exists(memset HAVE_MEMSET)
check_function_exists(ntp_gettime HAVE_NTP_GETTIME)
check_function_exists(pow HAVE_POW)
check_function_exists(pututline HAVE_PUTUTLINE)
check_function_exists(select HAVE_SELECT)
check_function_exists(setutent HAVE_SETUTENT)
check_function_exists(signal HAVE_SIGNAL)
check_function_exists(socket HAVE_SOCKET)
check_function_exists(strchr HAVE_STRCHR)
check_function_exists(strdup HAVE_STRDUP)
check_function_exists(strerror HAVE_STRERROR)
check_function_exists(strftime HAVE_STRFTIME)
check_function_exists(strtol HAVE_STRTOL)
check_function_exists(updwtmpx HAVE_UPDWTMPX)
check_function_exists(utmpxname HAVE_UTMPXNAME)
check_function_exists(vprintf HAVE_VPRINTF)
check_function_exists(_doprnt HAVE_DOPRNT)

# Struct member checks
if(HAVE_NET_IF_H)
    check_struct_has_member("struct ifreq" ifr_hwaddr "net/if.h" HAVE_STRUCT_IFREQ_IFR_HWADDR LANGUAGE C)
    check_struct_has_member("struct ifreq" ifr_index "net/if.h" HAVE_STRUCT_IFREQ_IFR_INDEX LANGUAGE C)
    check_struct_has_member("struct ifreq" ifr_ifindex "net/if.h" HAVE_STRUCT_IFREQ_IFR_IFINDEX LANGUAGE C)
endif()

if(HAVE_SYS_TIMEX_H)
    check_struct_has_member("struct timex" tick "sys/timex.h" HAVE_STRUCT_TIMEX_TICK LANGUAGE C)
    check_struct_has_member("struct timex" tai "sys/timex.h" HAVE_STRUCT_TIMEX_TAI LANGUAGE C)

    check_c_source_compiles("
        #include <sys/time.h>
        #include <sys/timex.h>
        int main() {
            struct ntptimeval ntv;
            ntv.tai = 0;
            return 0;
        }
    " HAVE_STRUCT_NTPTIMEVAL_TAI)
endif()

if(HAVE_UTMP_H)
    check_struct_has_member("struct utmp" ut_time "utmp.h" HAVE_STRUCT_UTMP_UT_TIME LANGUAGE C)
endif()

# Check for struct ether_addr.octet
if(HAVE_NETINET_ETHER_H OR HAVE_NET_ETHERNET_H OR HAVE_NET_IF_ETHER_H)
    check_c_source_compiles("
        #include <sys/types.h>
        #ifdef HAVE_NETINET_ETHER_H
        #include <netinet/ether.h>
        #endif
        #ifdef HAVE_NET_ETHERNET_H
        #include <net/ethernet.h>
        #endif
        #ifdef HAVE_NET_IF_H
        #include <net/if.h>
        #endif
        #ifdef HAVE_NET_IF_ETHER_H
        #include <net/if_ether.h>
        #endif
        int main() {
            struct ether_addr ea;
            ea.octet[0] = 0;
            return 0;
        }
    " HAVE_STRUCT_ETHER_ADDR_OCTET)
endif()

# Symbol declaration checks
check_symbol_exists(MSG_ERRQUEUE "sys/socket.h" HAVE_DECL_MSG_ERRQUEUE)
if(HAVE_DECL_MSG_ERRQUEUE)
    set(HAVE_DECL_MSG_ERRQUEUE 1)
else()
    set(HAVE_DECL_MSG_ERRQUEUE 0)
endif()

check_symbol_exists(POSIX_TIMERS_SUPPORTED "unistd.h" HAVE_DECL_POSIX_TIMERS_SUPPORTED)
if(HAVE_DECL_POSIX_TIMERS_SUPPORTED)
    set(HAVE_DECL_POSIX_TIMERS_SUPPORTED 1)
else()
    set(HAVE_DECL_POSIX_TIMERS_SUPPORTED 0)
endif()

# Type checks
check_type_size(_Bool BOOL_SIZE)
if(HAVE_BOOL_SIZE)
    set(HAVE__BOOL 1)
endif()

# Check for standard types
check_type_size(uint8_t UINT8_T)
check_type_size(uint32_t UINT32_T)
check_type_size(uint64_t UINT64_T)
check_type_size(int64_t INT64_T)
check_type_size(size_t SIZE_T)
check_type_size(ssize_t SSIZE_T)

# Standard headers (STDC_HEADERS)
if(HAVE_STDLIB_H AND HAVE_STDINT_H AND HAVE_STRING_H)
    set(STDC_HEADERS 1)
endif()

# Time with sys/time (TIME_WITH_SYS_TIME)
if(HAVE_SYS_TIME_H)
    set(TIME_WITH_SYS_TIME 1)
endif()

# Signal return type (typically void on modern systems)
set(RETSIGTYPE void)

# Select argument types (standard on POSIX systems)
set(SELECT_TYPE_ARG1 int)
set(SELECT_TYPE_ARG234 "fd_set *")
set(SELECT_TYPE_ARG5 "struct timeval *")

# Malloc check (assume modern systems have working malloc)
set(HAVE_MALLOC 1)

# Libtool object directory
set(LT_OBJDIR ".libs/")

message(STATUS "Platform detection complete")
message(STATUS "  Headers detected: ${HAVE_ARPA_INET_H}, ${HAVE_ENDIAN_H}, ${HAVE_SYS_SOCKET_H}")
message(STATUS "  Functions detected: ${HAVE_CLOCK_GETTIME}, ${HAVE_SELECT}, ${HAVE_SOCKET}")
message(STATUS "====================================")
