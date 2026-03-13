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
    if (logCallback) {
        NSString *msg = [NSString stringWithUTF8String:message];
        dispatch_async(dispatch_get_main_queue(), ^{
            logCallback(msg, level);
        });
    }
}

@implementation PTPBridge {
    PtpClock *_ptpClock;
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
    NSLog(@"PTPBridge: Starting ptpd with master IP: %@", _masterIP);
    
    // Convert master IP to C string
    const char *masterIPCStr = [_masterIP UTF8String];
    
    // Convert interface to C string
    const char *ifaceCStr = [_interface UTF8String];

    // Build command line arguments for ptpd.
    // Multicast: no -u/-g flags — ptpd joins 224.0.1.129 and discovers the master.
    // Unicast:   -u <masterIP> + -g (unicast negotiation) — slave sends
    //            REQUEST_UNICAST_TRANSMISSION signaling to master:general-port,
    //            master grants Announce/Sync/Delay_Resp, then exchange begins.
    const char *argv_multicast[] = {
        "ptpd",
        "-C",           // ptpengine:preset=slaveonly
        "-V",           // verbose logging
        "-L",           // ignore lock file
        "-i", ifaceCStr,
        NULL
    };
    int argc_multicast = 6;

    const char *argv_unicast[] = {
        "ptpd",
        "-C",           // ptpengine:preset=slaveonly
        "-V",           // verbose logging
        "-L",           // ignore lock file
        "-i", ifaceCStr,
        "-g",           // ptpengine:unicast_negotiation=y
        "-u", masterIPCStr, // ptpengine:unicast_destinations=<IP>
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
    // stop() may call ptpd_shutdown() concurrently; guard every access to
    // _ptpClock with a local snapshot to avoid null-dereference races.
    while (YES) {
        PtpClock *clock = _ptpClock; // snapshot
        if (!clock || !ptpd_is_running(clock)) {
            break;
        }
        usleep(100000); // 100 ms
    }

    NSLog(@"PTPBridge: run loop exited");

    // Call shutdown only if stop() hasn't already done so (i.e. _ptpClock
    // is still non-NULL — stop() NULLs it after ptpd_shutdown).
    PtpClock *clock = _ptpClock;
    if (clock) {
        NSLog(@"PTPBridge: Shutting down ptpd (natural exit)");
        if (logCallback) {
            dispatch_async(dispatch_get_main_queue(), ^{
                logCallback(@"PTP daemon shutting down...", 1);
            });
        }
        ptpd_shutdown(clock);
        _ptpClock = NULL;
    }
    
    NSLog(@"PTPBridge: Stopped");
}

- (void)stop {
    if (_ptpClock) {
        // ptpd_shutdown signals the protocol thread (sets library_should_exit)
        // and waits for it to finish via pthread_join, then cleans up.
        // Must be called from a background thread (not main) since it blocks.
        ptpd_shutdown(_ptpClock);
        _ptpClock = NULL;
    }
}

- (PTPStatus)getStatus {
    PTPStatus status = { .state = "STOPPED", .offset = 0, .delay = 0, .drift = 0.0 };
    
    if (!_ptpClock) {
        return status;
    }
    
    // Get port state
    const char *stateName = portState_getName(_ptpClock->portDS.portState);
    strncpy(status.state, stateName, sizeof(status.state) - 1);
    
    // Get timing statistics (nanoseconds)
    status.offset = _ptpClock->currentDS.offsetFromMaster.nanoseconds +
                   (_ptpClock->currentDS.offsetFromMaster.seconds * 1000000000LL);
    status.delay = _ptpClock->currentDS.meanPathDelay.nanoseconds +
                  (_ptpClock->currentDS.meanPathDelay.seconds * 1000000000LL);
    
    // Drift is not easily accessible from public API, leave as 0 for now
    status.drift = 0.0;
    
    return status;
}

+ (void)setLogCallback:(void (^)(NSString *, int))callback {
    logCallback = [callback copy];
    // Register C callback with ptpd
    ptpd_set_log_callback(ios_log_handler);
}

@end
