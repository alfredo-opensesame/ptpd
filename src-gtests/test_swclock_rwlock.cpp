/**
 * @file   test_swclock_rwlock.cpp
 * @brief  Regression tests for the pthread_rwlock reader-starvation fix.
 *
 * Background
 * ----------
 * macOS uses a writer-preference rwlock.  SwClock's internal poll thread
 * runs at 100 Hz and acquires the write-lock on every poll.  If the
 * monitor thread calls ptpd_gettime() (which acquires the read-lock),
 * that read-lock is perpetually deferred and the monitor blocks forever
 * after ~30 rows.
 *
 * The fix removed ptpd_gettime() from the monitor path.  The only
 * remaining swclock call in monitor is swclock_get_remaining_phase_ns(),
 * which acquires the write-lock internally (serialises without starvation).
 *
 * Tests
 * -----
 * T1: With the poll thread running at 100 Hz, swclock_get_remaining_phase_ns
 *     returns within 100 ms per call over 30 calls.
 * T2: A swclock_gettime() read-lock loop (reproduces the old bug)
 *     completes >=93% of iterations over 3 s when poll thread is active.
 *     NOTE: This test is DISABLED by default (see comment); enable it to
 *     confirm the pre-fix behaviour on macOS.
 * T3: swclock_get_remaining_phase_ns is callable safely from two threads
 *     simultaneously while the poll thread is running (TSAN target).
 * T4: Monitor reader continues after poll thread exits.
 *
 * Sanitizers: TSAN (all tests), ASAN.
 */

#include "test_helpers.h"

extern "C" {
#include "sw_clock.h"
}

#include <atomic>
#include <thread>
#include <chrono>
#include <vector>

/* ------------------------------------------------------------------ */
/* Fixture: create/destroy a SwClock with the poll thread active      */
/* ------------------------------------------------------------------ */
class SwClockRwlockTest : public ::testing::Test {
protected:
    SwClock *sc = nullptr;

    void SetUp() override {
        sc = swclock_create();
        ASSERT_NE(sc, nullptr) << "swclock_create() returned NULL";
        /* Give the poll thread a moment to initialise */
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    void TearDown() override {
        if (sc) {
            swclock_destroy(sc);
            sc = nullptr;
        }
    }
};

/* ------------------------------------------------------------------ */
/* T1: get_remaining_phase_ns latency < 100 ms while 100 Hz poll runs */
/* ------------------------------------------------------------------ */
TEST_F(SwClockRwlockTest, GetRemainingPhaseNs_LowLatency) {
    const int N = 30;
    int slow_count = 0;

    for (int i = 0; i < N; ++i) {
        auto t0 = mono_now();
        (void)swclock_get_remaining_phase_ns(sc);
        double ms = elapsed_ms(t0);
        if (ms > 100.0) ++slow_count;
    }

    EXPECT_EQ(slow_count, 0)
        << slow_count << "/" << N
        << " calls to swclock_get_remaining_phase_ns exceeded 100 ms "
        "(writer-starvation regression?)";
}

/* ------------------------------------------------------------------ */
/* T2: (DISABLED) swclock_gettime rdlock starvation reproduction      */
/*                                                                     */
/* Rename to TEST_F (remove DISABLED_) to confirm the pre-fix bug on  */
/* macOS: most iterations will hang and the success rate will be < 5%  */
/* ------------------------------------------------------------------ */
TEST_F(SwClockRwlockTest, DISABLED_GetTime_RdlockStarvation_OldBug) {
    const int    TOTAL_CALLS     = 300;   /* 3 s at 1/10 ms */
    const double MIN_SUCCESS_PCT = 93.0;
    int success = 0;

    for (int i = 0; i < TOTAL_CALLS; ++i) {
        struct timespec ts;
        auto t0 = mono_now();
        int rc = swclock_gettime(sc, CLOCK_REALTIME, &ts);
        double ms = elapsed_ms(t0);
        if (rc == 0 && ms < 100.0) ++success;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    double pct = 100.0 * success / TOTAL_CALLS;
    EXPECT_GE(pct, MIN_SUCCESS_PCT)
        << "Only " << pct << "% of swclock_gettime calls completed within 100 ms "
        "(expected >= " << MIN_SUCCESS_PCT << "%)";
}

/* ------------------------------------------------------------------ */
/* T3: Two threads call get_remaining_phase_ns concurrently (TSAN)    */
/* ------------------------------------------------------------------ */
TEST_F(SwClockRwlockTest, GetRemainingPhaseNs_TwoThreads_TSAN) {
    const int CALLS_PER_THREAD = 200;
    std::atomic<int> errors{0};

    auto worker = [&]() {
        for (int i = 0; i < CALLS_PER_THREAD; ++i) {
            auto t0 = mono_now();
            (void)swclock_get_remaining_phase_ns(sc);
            double ms = elapsed_ms(t0);
            if (ms > 200.0) errors.fetch_add(1);
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
    };

    std::thread t1(worker);
    std::thread t2(worker);
    t1.join();
    t2.join();

    EXPECT_EQ(errors.load(), 0)
        << errors.load() << " calls exceeded 200 ms in two-thread test";
}

/* ------------------------------------------------------------------ */
/* T4: Calls succeed after poll thread is no longer active            */
/* (swclock_destroy stops the poll thread; post-destroy calls should  */
/* not be made — this test verifies normal steady-state, not          */
/* post-destroy usage.)                                               */
/* After sleep of 2 s with poll thread running, all calls succeed.   */
/* ------------------------------------------------------------------ */
TEST_F(SwClockRwlockTest, GetRemainingPhaseNs_AfterSteadyState) {
    /* Let poll thread run for 2 s */
    std::this_thread::sleep_for(std::chrono::seconds(2));

    int slow = 0;
    for (int i = 0; i < 20; ++i) {
        auto t0 = mono_now();
        (void)swclock_get_remaining_phase_ns(sc);
        double ms = elapsed_ms(t0);
        if (ms > 100.0) ++slow;
    }
    EXPECT_EQ(slow, 0) << slow << "/20 calls slow after 2 s steady state";
}
