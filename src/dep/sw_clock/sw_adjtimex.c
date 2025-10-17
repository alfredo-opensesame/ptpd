#include "sw_adjtimex.h"
#include "swclock_compat.h"
#include <stdlib.h>   /* llabs */
#include <errno.h>

#if ADJ_SETOFFSET
static inline int64_t timex_time_to_ns(const struct timex *tx) {
    int64_t sec = (int64_t)tx->time.tv_sec;
    int64_t sub = (int64_t)tx->time.tv_usec;
    if (tx->modes & ADJ_NANO)
        return sec * 1000000000LL + sub;
    else
        return sec * 1000000000LL + sub * 1000LL;
}
#endif

int sw_adjtimex(SwClock *sw, struct timex *tx)
{
    if (!sw || !tx) { errno = EINVAL; return -1; }
    const int modes = tx->modes;

    /* Frequency correction: scaled-ppm (ppm << 16) */
    if (modes & ADJ_FREQUENCY) {
        double ppm = ((double)tx->freq) / 65536.0;
        double ppb = ppm * 1000.0;
        swclock_set_freq(sw, ppb);
    }

    /* Offset via tx->offset (microseconds) */
    if (modes & ADJ_OFFSET) {
        int64_t delta_ns = (int64_t)tx->offset * 1000LL;
        int max_slew_ppm = 500;
        int64_t window_ns = 500000000LL;
        int64_t min_win = (llabs(delta_ns) * 1000000LL) / max_slew_ppm;
        if (min_win > window_ns) window_ns = min_win;

        struct timeval delta_tv = {
            .tv_sec  = (time_t)(delta_ns / 1000000000LL),
            .tv_usec = (suseconds_t)((delta_ns / 1000LL) % 1000000LL)
        };
        sw_adjtime(sw, &delta_tv, NULL, max_slew_ppm, window_ns);
    }

#if ADJ_SETOFFSET
    /* Relative offset adjustment (Linux only) */
    if (modes & ADJ_SETOFFSET) {
        int64_t delta_ns = timex_time_to_ns(tx);
        int max_slew_ppm = 500;
        int64_t window_ns = 500000000LL;
        int64_t min_win = (llabs(delta_ns) * 1000000LL) / max_slew_ppm;
        if (min_win > window_ns) window_ns = min_win;

        struct timeval delta_tv = {
            .tv_sec  = (time_t)(delta_ns / 1000000000LL),
            .tv_usec = (suseconds_t)((delta_ns / 1000LL) % 1000000LL)
        };
        sw_adjtime(sw, &delta_tv, NULL, max_slew_ppm, window_ns);
    }
#endif

    return TIME_OK;
}
