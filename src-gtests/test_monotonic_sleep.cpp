/**
 * @file   test_monotonic_sleep.cpp
 * @brief  Unit tests for monotonic_sleep_1s() in ptpd_app_utils.c
 *
 * Sanitizers: TSAN (two-thread stop signal test T2).
 */

#include "test_helpers.h"

extern "C" {
#include "ptpd_app_utils.h"
}

#include <atomic>
#include <thread>
#include <chrono>

/* ------------------------------------------------------------------ */
/* T1: Normal 1-second sleep completes in [900 ms, 1200 ms]          */
/* ------------------------------------------------------------------ */
TEST(MonotonicSleep, NormalDuration) {
    volatile int stop = 0;
    auto t0 = mono_now();
    monotonic_sleep_1s(&stop);
    double ms = elapsed_ms(t0);

    EXPECT_GE(ms, 900.0)  << "sleep ended too early: " << ms << " ms";
    EXPECT_LE(ms, 1200.0) << "sleep took too long: "   << ms << " ms";
}

/* ------------------------------------------------------------------ */
/* T2: Setting *stop causes early exit within 250 ms (TSAN target)    */
/* A second thread sets stop after 200 ms; the sleep must return      */
/* within 200 ms + one 50 ms slice = 250 ms budget.                   */
/* Upper bound is generous (600 ms) to tolerate slow CI runners.      */
/* ------------------------------------------------------------------ */
TEST(MonotonicSleep, EarlyExitOnStop) {
    volatile int stop = 0;

    /* Launch stopper thread: sets stop after 200 ms */
    std::thread stopper([&stop]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        stop = 1;
    });

    auto t0 = mono_now();
    monotonic_sleep_1s(&stop); /* would block 1 s without stop */
    double ms = elapsed_ms(t0);
    stopper.join();

    EXPECT_LT(ms, 600.0) << "early-exit too slow: " << ms << " ms";
    EXPECT_GE(ms, 150.0) << "early-exit too fast (stop not respected?): " << ms << " ms";
}

/* ------------------------------------------------------------------ */
/* T3: Repeated calls accumulate ~N seconds                           */
/* 10 iterations → elapsed should be in [9.5 s, 12.0 s]              */
/* Upper bound is generous to tolerate slow CI runners.               */
/* ------------------------------------------------------------------ */
TEST(MonotonicSleep, RepeatedCallsAccumulate) {
    volatile int stop = 0;
    const int N = 10;
    auto t0 = mono_now();
    for (int i = 0; i < N; ++i)
        monotonic_sleep_1s(&stop);
    double ms = elapsed_ms(t0);

    EXPECT_GE(ms, 9500.0)  << "accumulated time too short: " << ms << " ms";
    EXPECT_LE(ms, 12000.0) << "accumulated time too long: "  << ms << " ms";
}

/* ------------------------------------------------------------------ */
/* T4: stop=1 on entry — returns immediately (< 60 ms)               */
/* ------------------------------------------------------------------ */
TEST(MonotonicSleep, PresetStopReturnsImmediately) {
    volatile int stop = 1;
    auto t0 = mono_now();
    monotonic_sleep_1s(&stop);
    double ms = elapsed_ms(t0);

    EXPECT_LT(ms, 60.0) << "should return immediately when stop=1: " << ms << " ms";
}
