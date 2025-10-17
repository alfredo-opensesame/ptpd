#include "swclock.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <math.h>
#include <stdatomic.h>

#if defined(__APPLE__)
#include <mach/mach_time.h>
static int64_t mono_now_ns(void) {
    static mach_timebase_info_data_t tb = {0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t t = mach_absolute_time();
    return (int64_t)((__int128)t * tb.numer / tb.denom);
}
int64_t swclock__mono_now_ns(void) { return mono_now_ns(); }
#else
#include <time.h>
static int64_t mono_now_ns(void) {
    struct timespec ts;
    #ifdef CLOCK_MONOTONIC_RAW
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    #else
    clock_gettime(CLOCK_MONOTONIC, &ts);
    #endif
    return (int64_t)ts.tv_sec * 1000000000ll + ts.tv_nsec;
}
#endif

struct SwClock {
    int64_t ref_mono_ns;
    int64_t ref_out_ns;
    atomic_int_fast64_t last_out_ns;
    double base_scale;
    int64_t slew_remaining_ns;
    int64_t slew_window_left_ns;
    double  slew_scale;
    int64_t backstep_guard_ns;
    pthread_mutex_t mu;
};

static void rebaseline_locked(SwClock* c, int64_t mono_ns, int64_t out_ns) {
    c->ref_mono_ns = mono_ns;
    c->ref_out_ns  = out_ns;
    c->slew_scale  = 0.0;
}

static int64_t map_now_locked(SwClock* c, int64_t mono_ns) {
    int64_t d_mono = mono_ns - c->ref_mono_ns;
    if (d_mono < 0) d_mono = 0;

    if (c->slew_window_left_ns > 0 && c->slew_remaining_ns != 0) {
        c->slew_scale = (double)c->slew_remaining_ns / (double)c->slew_window_left_ns;
    } else {
        c->slew_scale = 0.0;
        c->slew_remaining_ns = 0;
        c->slew_window_left_ns = 0;
    }

    if (c->slew_window_left_ns > 0) {
        int64_t step = d_mono;
        if (step > c->slew_window_left_ns) step = c->slew_window_left_ns;

        int64_t repaid = (int64_t)llround(c->slew_scale * (double)step);
        if ((c->slew_remaining_ns > 0 && repaid > c->slew_remaining_ns) ||
            (c->slew_remaining_ns < 0 && repaid < c->slew_remaining_ns)) {
            repaid = c->slew_remaining_ns;
        }
        c->slew_remaining_ns -= repaid;
        c->slew_window_left_ns -= step;

        if (c->slew_window_left_ns == 0) {
            c->ref_out_ns += (int64_t)llround((c->base_scale + c->slew_scale) * (double)step);
            c->ref_mono_ns += step;
        }
    }

    double scale = c->base_scale + c->slew_scale;
    if (scale < 0.0) scale = 0.0;

    return c->ref_out_ns + (int64_t)llround(scale * (double)(mono_ns - c->ref_mono_ns));
}

SwClock* swclock_create(void) {
    SwClock* c = (SwClock*)calloc(1, sizeof(*c));
    if (!c) return NULL;
    pthread_mutex_init(&c->mu, NULL);

    int64_t m = mono_now_ns();
    c->ref_mono_ns = m;
    c->ref_out_ns  = 0;
    atomic_store_explicit(&c->last_out_ns, 0, memory_order_relaxed);
    c->base_scale  = 1.0;
    c->slew_remaining_ns = 0;
    c->slew_window_left_ns = 0;
    c->slew_scale  = 0.0;
    c->backstep_guard_ns = 0;
    return c;
}

void swclock_destroy(SwClock* c) {
    if (!c) return;
    pthread_mutex_destroy(&c->mu);
    free(c);
}

int64_t swclock_now_ns(SwClock* c) {
    if (!c) return 0;
    int64_t mono_ns = mono_now_ns();

    pthread_mutex_lock(&c->mu);
    int64_t raw = map_now_locked(c, mono_ns);
    pthread_mutex_unlock(&c->mu);

    int64_t last = atomic_load_explicit(&c->last_out_ns, memory_order_relaxed);
    int64_t out  = raw;
    if (out < last) {
        out = last;
    }
    atomic_store_explicit(&c->last_out_ns, out, memory_order_relaxed);
    return out;
}

void swclock_set_freq(SwClock* c, double freq_ppb) {
    if (!c) return;
    pthread_mutex_lock(&c->mu);
    int64_t mono_ns = mono_now_ns();
    int64_t out_ns  = map_now_locked(c, mono_ns);
    rebaseline_locked(c, mono_ns, out_ns);
    c->base_scale = 1.0 + freq_ppb * 1e-9;
    pthread_mutex_unlock(&c->mu);
}

void swclock_adjust(SwClock* c, int64_t offset_ns, int64_t slew_window_ns) {
    if (!c) return;
    if (slew_window_ns < 1) slew_window_ns = 1;
    pthread_mutex_lock(&c->mu);
    int64_t mono_ns = mono_now_ns();
    int64_t out_ns  = map_now_locked(c, mono_ns);
    rebaseline_locked(c, mono_ns, out_ns);
    c->slew_remaining_ns   = offset_ns;
    c->slew_window_left_ns = llabs(slew_window_ns);
    pthread_mutex_unlock(&c->mu);
}

void swclock_set_backstep_guard(SwClock* c, int64_t guard_ns) {
    if (!c) return;
    pthread_mutex_lock(&c->mu);
    c->backstep_guard_ns = guard_ns;
    pthread_mutex_unlock(&c->mu);
}

void swclock_get_state(SwClock* c, swclock_state_t* out) {
    if (!c || !out) return;
    pthread_mutex_lock(&c->mu);
    out->base_scale         = c->base_scale;
    out->slew_scale         = c->slew_scale;
    out->slew_remaining_ns  = c->slew_remaining_ns;
    out->slew_window_left_ns= c->slew_window_left_ns;
    out->last_out_ns        = atomic_load_explicit(&c->last_out_ns, memory_order_relaxed);
    pthread_mutex_unlock(&c->mu);
}

void swclock_align_now(SwClock* c, int64_t target_now_ns) {
    if (!c) return;
    pthread_mutex_lock(&c->mu);
    int64_t mono_ns = mono_now_ns();
    rebaseline_locked(c, mono_ns, target_now_ns);
    c->slew_remaining_ns   = 0;
    c->slew_window_left_ns = 0;
    c->slew_scale          = 0.0;
    pthread_mutex_unlock(&c->mu);
    atomic_store_explicit(&c->last_out_ns, target_now_ns, memory_order_relaxed);
}
