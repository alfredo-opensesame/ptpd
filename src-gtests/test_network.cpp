/**
 * @file   test_network.cpp
 * @brief  Network pre-flight checks (hardware-dependent).
 *
 * All tests use GTEST_SKIP() when the required hardware or network
 * state is absent.  They are FAIL only when the tested condition
 * represents an error that would prevent ptpd-app from running:
 *   - Port 319 or 320 occupied → stray ptpd-app process
 *
 * Sanitizers: none (syscall-heavy, not safety-relevant).
 */

#include "test_helpers.h"

#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <cstdlib>

/* The PTP network interface used by this test environment. */
static const char *PTP_IFACE = "en5";

/* Master clock IP used in the test environment. */
static const char *MASTER_IP = "192.168.8.234";

/* ------------------------------------------------------------------ */
/* T1: PTP interface exists and has an AF_INET address                */
/* ------------------------------------------------------------------ */
TEST(Network, InterfaceExists) {
    struct ifaddrs *ifa_list = nullptr;
    if (getifaddrs(&ifa_list) != 0)
        GTEST_SKIP() << "getifaddrs failed: " << strerror(errno);

    bool found = false;
    for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
        if (ifa->ifa_name && strcmp(ifa->ifa_name, PTP_IFACE) == 0 &&
            ifa->ifa_addr && ifa->ifa_addr->sa_family == AF_INET) {
            char addr_buf[INET_ADDRSTRLEN];
            struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
            inet_ntop(AF_INET, &sa->sin_addr, addr_buf, sizeof(addr_buf));
            RecordProperty("interface",  PTP_IFACE);
            RecordProperty("address",    addr_buf);
            found = true;
            break;
        }
    }
    freeifaddrs(ifa_list);

    if (!found)
        GTEST_SKIP() << "Interface " << PTP_IFACE << " not present or has no IPv4 address";

    SUCCEED();
}

/* ------------------------------------------------------------------ */
/* T2: Master clock responds to ping (ICMP echo)                      */
/* We use system("ping -c1 -W1 <ip>") for portability; this is fine  */
/* for a hardware pre-flight, not for unit coverage.                  */
/* ------------------------------------------------------------------ */
TEST(Network, MasterReachable) {
    /* Quick check: does the interface even exist? */
    struct ifaddrs *ifa_list = nullptr;
    bool iface_found = false;
    if (getifaddrs(&ifa_list) == 0) {
        for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
            if (ifa->ifa_name && strcmp(ifa->ifa_name, PTP_IFACE) == 0) {
                iface_found = true; break;
            }
        }
        freeifaddrs(ifa_list);
    }
    if (!iface_found)
        GTEST_SKIP() << "Interface " << PTP_IFACE << " not present";

    std::string cmd = std::string("ping -c1 -W1 ") + MASTER_IP + " >/dev/null 2>&1";
    int rc = system(cmd.c_str());
    if (rc != 0)
        GTEST_SKIP() << "Master " << MASTER_IP << " unreachable (ping returned " << rc << ")";

    SUCCEED();
}

/* ------------------------------------------------------------------ */
/* Helper: try to bind a UDP socket to port; return errno on failure. */
/* ------------------------------------------------------------------ */
static int try_bind_udp_port(int port) {
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) return errno;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in sa = {};
    sa.sin_family      = AF_INET;
    sa.sin_port        = htons((uint16_t)port);
    sa.sin_addr.s_addr = INADDR_ANY;
    int rc = bind(fd, (struct sockaddr *)&sa, sizeof(sa));
    int saved = errno;
    close(fd);
    return (rc == 0) ? 0 : saved;
}

/* ------------------------------------------------------------------ */
/* T3: UDP port 319 (PTP event) is free                               */
/* FAIL (not SKIP) because an occupied port means a stray ptpd-app.  */
/* ------------------------------------------------------------------ */
TEST(Network, Port319Free) {
    int err = try_bind_udp_port(319);
    if (err == EACCES) {
        GTEST_SKIP() << "No permission to bind port 319 (run as root or grant cap_net_bind)";
    }
    EXPECT_EQ(err, 0) << "UDP port 319 is in use (EADDRINUSE=" << EADDRINUSE << "): "
                      << "a stray ptpd-app process may be running.  err=" << err;
}

/* ------------------------------------------------------------------ */
/* T4: UDP port 320 (PTP general) is free                             */
/* ------------------------------------------------------------------ */
TEST(Network, Port320Free) {
    int err = try_bind_udp_port(320);
    if (err == EACCES) {
        GTEST_SKIP() << "No permission to bind port 320";
    }
    EXPECT_EQ(err, 0) << "UDP port 320 is in use: stray ptpd-app may be running.  err=" << err;
}

/* ------------------------------------------------------------------ */
/* T5: No ptpd-app process is currently running                       */
/* A live ptpd-app would hold ports 319/320 and interfere with       */
/* hardware comparison runs.                                           */
/* ------------------------------------------------------------------ */
TEST(Network, NoPtpdAppRunning) {
    int rc = system("pgrep -x ptpd-app >/dev/null 2>&1");
    /* pgrep returns 0 if a match is found, 1 if no match */
    EXPECT_NE(rc, 0) << "ptpd-app process is currently running — stop it before testing";
}
