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

- (instancetype)initWithMasterIP:(NSString *)masterIP;
- (void)run;
- (void)stop;
- (PTPStatus)getStatus;

+ (void)setLogCallback:(void (^)(NSString *message, int level))callback;

@end

NS_ASSUME_NONNULL_END
