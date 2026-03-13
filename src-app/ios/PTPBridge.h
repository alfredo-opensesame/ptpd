//
//  PTPBridge.h
//  PTP Monitor
//
//  Swift-accessible interface to ptpd C library
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    char state[32];
    int64_t offset;      // nanoseconds
    int64_t delay;       // nanoseconds
    double drift;        // ppm
} PTPStatus;

@interface PTPBridge : NSObject

typedef NS_ENUM(NSInteger, PTPMode) {
    PTPModeMulticast = 0,
    PTPModeUnicast   = 1,
};

- (instancetype)initWithMasterIP:(NSString *)masterIP
                       interface:(NSString *)interface
                            mode:(PTPMode)mode;
- (void)run;
- (void)stop;
- (PTPStatus)getStatus;

+ (void)setLogCallback:(void (^)(NSString *message, int level))callback;

/// Returns an array of dicts with keys "name" (e.g. "en5") and
/// "label" (e.g. "en5: Ethernet") for every up, non-loopback
/// IPv4 interface currently available on the device.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)availableInterfaces;

@end

NS_ASSUME_NONNULL_END
