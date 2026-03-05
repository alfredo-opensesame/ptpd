/**
 * @file   ptpd_app_utils.c
 * @brief  Utility functions shared between ptpd-app.c and the unit test suite.
 *
 * Keep this file free of ptpd / swclock includes so test targets can link it
 * directly without pulling in the full ptpd shared library.
 */

#include "ptpd_app_utils.h"

#include <stdio.h>   /* fprintf, stderr */
#include <stdlib.h>  /* exit */
#include <string.h>  /* strcmp, strncpy */
#include <time.h>    /* clock_gettime, nanosleep, CLOCK_MONOTONIC */

/* ------------------------------------------------------------------ */
int strip_arg(int *argc, char **argv, int i,
              const char *flag, int has_value,
              char *buf, size_t buf_len)
{
	if (strcmp(argv[i], flag) != 0)
		return 0;

	if (has_value) {
		if (i + 1 >= *argc) {
			fprintf(stderr, "Error: %s requires an argument\n", flag);
			exit(1);
		}
		if (buf && buf_len > 0) {
			strncpy(buf, argv[i + 1], buf_len - 1);
			buf[buf_len - 1] = '\0';
		}
		for (int j = i; j < *argc - 2; j++)
			argv[j] = argv[j + 2];
		*argc -= 2;
	} else {
		for (int j = i; j < *argc - 1; j++)
			argv[j] = argv[j + 1];
		*argc -= 1;
	}
	return 1;
}

/* ------------------------------------------------------------------ */
void monotonic_sleep_1s(volatile int *stop)
{
	struct timespec deadline;
	clock_gettime(CLOCK_MONOTONIC, &deadline);
	deadline.tv_sec += 1;

	while (!*stop) {
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		long long remain_ns =
			(long long)(deadline.tv_sec  - now.tv_sec)  * 1000000000LL
			+ (long long)(deadline.tv_nsec - now.tv_nsec);
		if (remain_ns <= 0)
			break;
		struct timespec slice = {
			0,
			remain_ns < 50000000L ? remain_ns : 50000000L
		};
		nanosleep(&slice, NULL);
	}
}
