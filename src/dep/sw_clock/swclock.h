#ifndef SWCLOCK_H
#define SWCLOCK_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SwClock SwClock;

SwClock* swclock_create(void);
void     swclock_destroy(SwClock* c);
int64_t  swclock_now_ns(SwClock* c);
void     swclock_set_freq(SwClock* c, double freq_ppb);
void     swclock_adjust(SwClock* c, int64_t offset_ns, int64_t slew_window_ns);
void     swclock_set_backstep_guard(SwClock* c, int64_t guard_ns);

typedef struct {
    double  base_scale;
    double  slew_scale;
    int64_t slew_remaining_ns;
    int64_t slew_window_left_ns;
    int64_t last_out_ns;
} swclock_state_t;

void     swclock_get_state(SwClock* c, swclock_state_t* out);

/* Align swclock so swclock_now_ns(c) == target_now_ns at this instant. */
void     swclock_align_now(SwClock* c, int64_t target_now_ns);

#ifdef __APPLE__
int64_t  swclock__mono_now_ns(void);
#endif

#ifdef __cplusplus
}
#endif
#endif // SWCLOCK_H
