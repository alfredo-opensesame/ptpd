#ifndef SWCLOCK_COMPAT_H
#define SWCLOCK_COMPAT_H

#include <stdint.h>
#include <sys/time.h>
#include <errno.h>
#include "swclock.h"

#ifdef __cplusplus
extern "C" {
#endif

int sw_gettimeofday(SwClock *sw, struct timeval *tv, void *tz);
int sw_adjtime(SwClock *sw,
               const struct timeval *delta,
               struct timeval *olddelta,
               int max_slew_ppm,
               int64_t default_window_ns);

typedef enum { SW_SET_HARD_ALIGN = 0, SW_SET_SLEW_TO_TARGET = 1 } sw_set_mode_t;

int sw_settimeofday(SwClock *sw,
                    const struct timeval *tv,
                    const struct timezone *tz,
                    sw_set_mode_t mode,
                    int max_slew_ppm,
                    int64_t default_window_ns);

#ifdef __cplusplus
}
#endif

#endif // SWCLOCK_COMPAT_H
