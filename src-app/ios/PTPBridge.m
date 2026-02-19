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
}

- (instancetype)initWithMasterIP:(NSString *)masterIP {
    self = [super init];
    if (self) {
        _masterIP = [masterIP copy];  // Retain a copy
        _ptpClock = NULL;
    }
    return self;
}

- (void)run {
    NSLog(@"PTPBridge: Starting ptpd with master IP: %@", _masterIP);
    
    // Convert master IP to C string
    const char *masterIPCStr = [_masterIP UTF8String];
    
    // Build command line arguments for ptpd
    const char *argv[] = {
        "ptpd",
        "-C",                              // Client mode (slave)
        "-g",                              // Run in foreground (don't daemonize)
        "-V",                              // Verbose logging
        "-L",                              // Ignore lock file (can't create in /var/run on iOS)
        "-i", "en0",                       // Network interface
        "-u", masterIPCStr,                // Unicast master IP
        NULL
    };
    int argc = 9;  // ptpd + 8 flags/args
    
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
    
    // Wait for ptpd to run (it runs in its own thread)
    while (ptpd_is_running(_ptpClock)) {
        sleep(1);
        
        // Check if we should exit
        if (_ptpClock->ios_should_exit) {
            NSLog(@"PTPBridge: Stop requested");
            break;
        }
    }
    
    NSLog(@"PTPBridge: Shutting down ptpd");
    if (logCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            logCallback(@"PTP daemon shutting down...", 1);
        });
    }
    
    ptpd_shutdown(_ptpClock);
    _ptpClock = NULL;
    
    NSLog(@"PTPBridge: Stopped");
}

- (void)stop {
    if (_ptpClock) {
        _ptpClock->ios_should_exit = TRUE;
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
