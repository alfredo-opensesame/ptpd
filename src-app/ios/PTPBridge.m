//
//  PTPBridge.m
//  PTP Monitor
//
//  Bridge between Swift and ptpd C library
//

#import "PTPBridge.h"
#include "ptpdlib.h"
#include <pthread.h>

static void (^logCallback)(NSString *, int) = nil;

// C callback function for ptpd logs
static void ios_log_handler(const char *message, int level) {
    // Always emit to system log so 'xcrun simctl spawn … log stream' and
    // Xcode debug console can see ptpd diagnostics.
    NSLog(@"[ptpd] %s", message);

    if (logCallback) {
        NSString *msg = [NSString stringWithUTF8String:message];
        dispatch_async(dispatch_get_main_queue(), ^{
            logCallback(msg, level);
        });
    }
}

@implementation PTPBridge {
    PtpdHandle *_ptpClock;
    NSString *_masterIP;
    NSString *_interface;
    PTPMode   _mode;
}

- (instancetype)initWithMasterIP:(NSString *)masterIP
                       interface:(NSString *)interface
                            mode:(PTPMode)mode {
    self = [super init];
    if (self) {
        _masterIP = [masterIP copy];
        _interface = (interface.length > 0) ? [interface copy] : @"en0";
        _mode     = mode;
        _ptpClock = NULL;
    }
    return self;
}

+ (NSString *)_typeForInterfaceName:(NSString *)name {
    if ([name hasPrefix:@"en"]) {
        // On a real iOS device en0 = Wi-Fi; en1+ = Ethernet/USB adapter.
        // On a Mac or simulator the numbering may differ.
        if ([name isEqualToString:@"en0"]) return @"Wi-Fi";
        return @"Ethernet";
    }
    if ([name hasPrefix:@"pdp_ip"]) return @"Cellular";
    if ([name hasPrefix:@"utun"])   return @"VPN";
    if ([name hasPrefix:@"bridge"]) return @"Bridge";
    if ([name hasPrefix:@"awdl"] ||
        [name hasPrefix:@"llw"])   return @"P2P";
    return @"Network";
}

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availableInterfaces {
    NSMutableArray *result    = [NSMutableArray array];
    NSMutableSet   *seen      = [NSMutableSet set];
    struct ifaddrs *ifaddr    = NULL;

    if (getifaddrs(&ifaddr) != 0) return result;

    for (struct ifaddrs *ifa = ifaddr; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_name)  continue;
        if (!ifa->ifa_addr)  continue;
        // Only IPv4, only UP, skip loopback
        if (ifa->ifa_addr->sa_family != AF_INET)  continue;
        if (!(ifa->ifa_flags & IFF_UP))            continue;
        if (  ifa->ifa_flags & IFF_LOOPBACK)       continue;

        NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
        if ([seen containsObject:name]) continue;
        [seen addObject:name];

        NSString *type  = [self _typeForInterfaceName:name];
        NSString *label = [NSString stringWithFormat:@"%@: %@", name, type];
        [result addObject:@{@"name": name, @"label": label}];
    }

    freeifaddrs(ifaddr);
    // Sort for stable display order
    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
    return [result copy];
}

- (void)run {
    NSLog(@"PTPBridge: Starting ptpd with master IP: %@  interface: %@  mode: %@",
          _masterIP, _interface, (_mode == PTPModeUnicast) ? @"unicast" : @"multicast");

    // Convert master IP to C string
    const char *masterIPCStr = [_masterIP UTF8String];

    // Convert interface to C string
    const char *ifaceCStr = [_interface UTF8String];

    // Locate the bundled config file — same conf used by the macOS daemon.
    // It carries clock:step_startup, clock:step_startup_force, drift_handling,
    // slaveonly preset, and all other tuned settings.
    NSString *confNS = [[NSBundle mainBundle] pathForResource:@"ptpd-daemon" ofType:@"conf"];
    if (!confNS) {
        NSLog(@"PTPBridge: FATAL — ptpd-daemon.conf not found in app bundle");
        if (logCallback) {
            dispatch_async(dispatch_get_main_queue(), ^{
                logCallback(@"ERROR: ptpd-daemon.conf not found in app bundle", 0);
            });
        }
        return;
    }
    const char *confPath = [confNS UTF8String];
    NSLog(@"PTPBridge: Using config file: %@", confNS);

    // Build command line arguments — identical invocation to macOS:
    //   ptpd -C -c <conf> -i <iface> -D -D -D
    // The config file handles preset=slaveonly, step_startup, drift_handling, etc.
    // -i overrides ptpengine:interface from conf.
    // -u overrides ptpengine:unicast_destinations from conf (unicast mode only).
    // Identical invocation to macOS: ptpd -C -c <conf> -i <iface> -D -D -D
    // global:ignore_lock=y is set in the conf (sandbox can't write /var/run).
    // unicast_negotiation and unicast_destinations are set in the conf.
    const char *argv_multicast[] = {
        "ptpd",
        "-C",            // global:foreground=Y
        "-c", confPath,  // full daemon config
        "-i", ifaceCStr, // override interface
        "-D", "-D", "-D",
        NULL
    };
    int argc_multicast = 9;

    const char *argv_unicast[] = {
        "ptpd",
        "-C",
        "-c", confPath,
        "-i", ifaceCStr,
        "-D", "-D", "-D",
        NULL
    };
    int argc_unicast = 9;

    const char **argv = (_mode == PTPModeUnicast) ? argv_unicast  : argv_multicast;
    int          argc = (_mode == PTPModeUnicast) ? argc_unicast  : argc_multicast;

    Integer16 ret = 0;

    // Set up log callback before init
    if (logCallback) {
        ptpd_set_log_callback(ios_log_handler);
    }

    // Initialize ptpd
    _ptpClock = ptpd_init(argc, (char **)argv, &ret);
    if (!_ptpClock) {
        NSLog(@"PTPBridge: Failed to initialize ptpd (ret=%d)", ret);
        if (logCallback) {
            NSString *msg = [NSString stringWithFormat:@"ERROR: Failed to initialize PTP daemon (code %d)", ret];
            dispatch_async(dispatch_get_main_queue(), ^{
                logCallback(msg, 0);
            });
        }
        return;
    }

    NSLog(@"PTPBridge: ptpd initialized successfully");
    if (logCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            logCallback(@"PTP daemon initialized successfully", 1);
        });
    }

    // Start ptpd protocol engine in background thread
    int start_ret = ptpd_start(_ptpClock);
    if (start_ret != 0) {
        NSLog(@"PTPBridge: Failed to start ptpd (ret=%d)", start_ret);
        if (logCallback) {
            dispatch_async(dispatch_get_main_queue(), ^{
                logCallback(@"ERROR: Failed to start PTP protocol engine", 0);
            });
        }
        ptpd_shutdown(_ptpClock);
        _ptpClock = NULL;
        return;
    }

    NSLog(@"PTPBridge: ptpd started successfully");
    if (logCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            logCallback(@"PTP protocol engine started successfully", 1);
        });
    }

    // Wait for ptpd to finish.  Poll at 100 ms so stop() is responsive.
    // The _ptpClock pointer may be NULLed by stop() at any time; take a
    // @synchronized snapshot on every iteration to avoid racing with stop().
    while (YES) {
        PtpdHandle *clock = nil;
        @synchronized(self) { clock = _ptpClock; }
        if (!clock || !ptpd_is_running(clock)) {
            break;
        }
        usleep(100000); // 100 ms
    }

    NSLog(@"PTPBridge: run loop exited");

    // Atomically take ownership of _ptpClock so stop() cannot also call
    // ptpd_shutdown on the same pointer (double-free crash).
    PtpdHandle *clock = nil;
    @synchronized(self) {
        clock = _ptpClock;
        _ptpClock = NULL;
    }
    if (clock) {
        NSLog(@"PTPBridge: Shutting down ptpd (natural exit)");
        if (logCallback) {
            dispatch_async(dispatch_get_main_queue(), ^{
                logCallback(@"PTP daemon shutting down...", 1);
            });
        }
        ptpd_shutdown(clock);
    }

    NSLog(@"PTPBridge: Stopped");
}

- (void)stop {
    // Atomically take ownership of _ptpClock so run()'s natural-exit path
    // cannot also call ptpd_shutdown on the same pointer (double-free crash).
    PtpdHandle *clock = nil;
    @synchronized(self) {
        clock = _ptpClock;
        _ptpClock = NULL;
    }
    if (clock) {
        // ptpd_shutdown signals the protocol thread (sets library_should_exit)
        // and waits for it to finish via pthread_join, then cleans up.
        // Must be called from a background thread (not main) since it blocks.
        ptpd_shutdown(clock);
    }
}

- (PTPStatus)getStatus {
    PTPStatus status = { .state = "STOPPED", .offset = 0, .delay = 0, .drift = 0.0 };

    if (!_ptpClock) {
        return status;
    }

    ptpd_status_t s;
    if (ptpd_get_status(_ptpClock, &s) != 0) {
        return status;
    }

    strncpy(status.state, ptpd_state_name(s.state), sizeof(status.state) - 1);
    status.state[sizeof(status.state) - 1] = '\0';
    status.offset = s.offset_ns;
    status.delay  = s.delay_ns;
    status.drift  = (double)s.drift_ppb;

    return status;
}

+ (void)setLogCallback:(void (^)(NSString *, int))callback {
    logCallback = [callback copy];
    // Register C callback with ptpd
    ptpd_set_log_callback(ios_log_handler);
}

@end
