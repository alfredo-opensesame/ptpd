/**
 * @file   ptpd_app_utils.h
 * @brief  Utility functions shared between ptpd-app.c and the unit test suite.
 *
 * Extracted from ptpd-app.c so that test_strip_arg.cpp and
 * test_monotonic_sleep.cpp can link against them directly without pulling in
 * ptpd library dependencies.  See TEST_PLAN.txt §E3 (Option B).
 */

#ifndef PTPD_APP_UTILS_H
#define PTPD_APP_UTILS_H

#include <stddef.h> /* size_t */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Strip one custom flag (and its optional value argument) from argv in-place.
 *
 * Shifts remaining elements down and decrements *argc.  If the flag requires
 * a value (has_value != 0) and none is present, prints an error to stderr and
 * calls exit(1).
 *
 * @param argc      Pointer to the current argc; decremented on match.
 * @param argv      The argv array; modified in-place on match.
 * @param i         Index of the element to test.
 * @param flag      Flag string to match (e.g. "--servo-log").
 * @param has_value 1 if the flag consumes the next element as its value.
 * @param buf       Output buffer for the value string, or NULL.
 * @param buf_len   Size of buf; value is truncated to buf_len-1 chars.
 * @return          1 if the flag was found and stripped, 0 otherwise.
 */
int strip_arg(int *argc, char **argv, int i,
              const char *flag, int has_value,
              char *buf, size_t buf_len);

/**
 * Sleep for approximately 1 second using a CLOCK_MONOTONIC deadline.
 *
 * Uses 50 ms nanosleep() slices so that:
 *   (a) *stop is checked at least every 50 ms — the caller wakes quickly
 *       after a SIGTERM sets *stop to non-zero, and
 *   (b) a CLOCK_REALTIME backward step (ptpd initial clock correction of
 *       ~−26 s) cannot extend the sleep period as nanosleep() with a
 *       relative timespec is based on CLOCK_REALTIME on some platforms.
 *
 * Returns as soon as the 1-second deadline has elapsed OR *stop != 0,
 * whichever comes first.
 *
 * @param stop  Pointer to a volatile flag checked between slices.
 */
void monotonic_sleep_1s(volatile int *stop);

#ifdef __cplusplus
}
#endif

#endif /* PTPD_APP_UTILS_H */
