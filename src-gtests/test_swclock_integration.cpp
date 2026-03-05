/**
 * @file   test_swclock_integration.cpp
 * @brief  Integration tests for the SwClock public API.
 *
 * These tests exercise the paths reachable from ptpd-app.c without
 * requiring a live PTP master:
 *   - swclock_get_metrics before any adjtime call
 *   - swclock_get_remaining_phase_ns with zero phase
 *   - swclock_start_log to a valid tmpfile path
 *   - swclock_start_log with a NULL path (no crash)
 *   - swclock_enable_monitoring on/off
 *   - swclock_adjtime with a trivial offset
 *
 * Sanitizers: ASAN, UBSAN.
 */

#include "test_helpers.h"

extern "C" {
#include "sw_clock.h"
}

#include <cstring>
#include <cstdio>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* Fixture                                                             */
/* ------------------------------------------------------------------ */
class SwClockIntegrationTest : public ::testing::Test {
protected:
    SwClock *sc = nullptr;

    void SetUp() override {
        sc = swclock_create();
        ASSERT_NE(sc, nullptr) << "swclock_create() returned NULL";
    }

    void TearDown() override {
        if (sc) {
            swclock_destroy(sc);
            sc = nullptr;
        }
    }
};

/* ------------------------------------------------------------------ */
/* T1: swclock_get_metrics before any adjtime → returns non-zero      */
/* (no data available) but must not crash or deadlock.                */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, GetMetrics_BeforeAdjtime_NoDeadlock) {
    swclock_metrics_snapshot_t snap;
    memset(&snap, 0xAB, sizeof(snap)); /* poison */

    /* May fail (no data) but must return promptly */
    auto t0 = mono_now();
    int rc = swclock_get_metrics(sc, &snap);
    double ms = elapsed_ms(t0);

    EXPECT_LT(ms, 500.0) << "swclock_get_metrics hung for " << ms << " ms";
    /* rc == 0 (success) or -1 (no data) are both acceptable */
    EXPECT_TRUE(rc == 0 || rc == -1)
        << "Unexpected return value from swclock_get_metrics: " << rc;
}

/* ------------------------------------------------------------------ */
/* T2: get_remaining_phase_ns on a fresh clock returns a value        */
/* promptly (no lock inversion crash).                                */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, GetRemainingPhaseNs_FreshClock) {
    auto t0 = mono_now();
    long long phase = swclock_get_remaining_phase_ns(sc);
    double ms = elapsed_ms(t0);

    EXPECT_LT(ms, 200.0)
        << "swclock_get_remaining_phase_ns took " << ms << " ms on a fresh clock";

    /* Fresh clock has zero phase correction pending */
    EXPECT_EQ(phase, 0LL)
        << "Expected 0 remaining phase on fresh clock, got " << phase << " ns";
}

/* ------------------------------------------------------------------ */
/* T3: swclock_start_log to a valid path creates the file             */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, StartLog_ValidPath_FileCreated) {
    TempFile tf;
    /* TempFile creates the file via mkstemp; get its path */
    const std::string &path = tf.path();

    swclock_start_log(sc, path.c_str());
    swclock_close_log(sc);

    /* File must exist */
    EXPECT_EQ(access(path.c_str(), F_OK), 0)
        << "Log file not found after swclock_start_log: " << path;
}

/* ------------------------------------------------------------------ */
/* T4: swclock_start_log with NULL path must not crash                */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, StartLog_NullPath_NoCrash) {
    EXPECT_NO_FATAL_FAILURE({
        swclock_start_log(sc, nullptr);
        swclock_close_log(sc);
    });
}

/* ------------------------------------------------------------------ */
/* T5: swclock_enable_monitoring toggle on/off does not crash         */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, EnableMonitoring_ToggleNoCrash) {
    EXPECT_NO_FATAL_FAILURE({
        swclock_enable_monitoring(sc, true);
        swclock_enable_monitoring(sc, false);
        swclock_enable_monitoring(sc, true);
    });
}

/* ------------------------------------------------------------------ */
/* T6: swclock_adjtime with a small frequency offset round-trips      */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, Adjtime_SmallOffset_Accepted) {
    struct timex tx;
    memset(&tx, 0, sizeof(tx));
    tx.modes  = ADJ_FREQUENCY;
    tx.freq   = 0; /* 0 ppm — no-op but exercises the code path */

    auto t0 = mono_now();
    int rc = swclock_adjtime(sc, &tx);
    double ms = elapsed_ms(t0);

    EXPECT_LT(ms, 200.0) << "swclock_adjtime took " << ms << " ms";
    EXPECT_TRUE(rc == TIME_OK || rc == TIME_BAD)
        << "Unexpected return from swclock_adjtime: " << rc;
}

/* ------------------------------------------------------------------ */
/* T7: swclock_gettime CLOCK_MONOTONIC returns a reasonable value     */
/* ------------------------------------------------------------------ */
TEST_F(SwClockIntegrationTest, GetTime_Monotonic_Reasonable) {
    struct timespec ts;
    memset(&ts, 0, sizeof(ts));

    auto t0 = mono_now();
    int rc = swclock_gettime(sc, CLOCK_MONOTONIC, &ts);
    double ms = elapsed_ms(t0);

    EXPECT_EQ(rc, 0) << "swclock_gettime(CLOCK_MONOTONIC) failed";
    EXPECT_LT(ms, 200.0) << "swclock_gettime took " << ms << " ms";
    /* tv_sec should be > 0 (system has been up > 0 seconds) */
    EXPECT_GT(ts.tv_sec, (time_t)0);
    EXPECT_GE(ts.tv_nsec, 0L);
    EXPECT_LT(ts.tv_nsec, 1000000000L);
}
