#include "swclock_compat.h"
#include <stdlib.h>  // for llabs()

int sw_gettimeofday(SwClock *sw, struct timeval *tv, void *tz)
{
    if (!sw || !tv) { errno = EINVAL; return -1; }
    int64_t ns = swclock_now_ns(sw);
    tv->tv_sec  = (time_t)(ns / 1000000000LL);
    tv->tv_usec = (suseconds_t)((ns / 1000) % 1000000);
    (void)tz;
    return 0;
}

int sw_adjtime(SwClock *sw,
               const struct timeval *delta,
               struct timeval *olddelta,
               int max_slew_ppm,
               int64_t default_window_ns) {
    if (!sw) { errno = EINVAL; return -1; }

    if (olddelta) {
        swclock_state_t s; swclock_get_state(sw, &s);
        int64_t rem = s.slew_remaining_ns;
        if (rem < 0) rem = -rem;
        olddelta->tv_sec  = (time_t)(rem / 1000000000LL);
        olddelta->tv_usec = (suseconds_t)((rem / 1000) % 1000000);
    }
    if (!delta) return 0;

    int64_t req_ns = (int64_t)delta->tv_sec * 1000000000LL +
                     (int64_t)delta->tv_usec * 1000LL;

    int64_t window_ns = default_window_ns > 0 ? default_window_ns : 500000000LL;
    if (max_slew_ppm > 0) {
        int64_t min_window = (llabs(req_ns) * 1000000LL) / (int64_t)max_slew_ppm;
        if (min_window > window_ns) window_ns = min_window;
    }

    swclock_adjust(sw, req_ns, window_ns);
    return 0;
}

int sw_settimeofday(SwClock *sw,
                    const struct timeval *tv,
                    const struct timezone *tz,
                    sw_set_mode_t mode,
                    int max_slew_ppm,
                    int64_t default_window_ns) {
    if (!sw || !tv) { errno = EINVAL; return -1; }
    (void)tz;

    int64_t target_ns = (int64_t)tv->tv_sec * 1000000000LL +
                        (int64_t)tv->tv_usec * 1000LL;

    if (mode == SW_SET_HARD_ALIGN) {
        swclock_align_now(sw, target_ns);
        return 0;
    }

    struct timeval delta;
    int64_t now_ns = swclock_now_ns(sw);
    int64_t diff_ns = target_ns - now_ns;
    delta.tv_sec  = (time_t)(diff_ns / 1000000000LL);
    delta.tv_usec = (suseconds_t)((diff_ns / 1000) % 1000000);
    return sw_adjtime(sw, &delta, NULL, max_slew_ppm, default_window_ns);
}
