/**
 * @file   ptpd-app.c
 * @brief  Example application using ptpdlib
 *
 * This is a reference implementation showing how to use ptpd as a library.
 * It provides identical functionality to the built-in ptpd2 executable
 * but uses the public library API which runs the daemon in a background thread.
 * 
 * This example also demonstrates reading time via ptpd_gettime(), which
 * returns time from the clock backend (swclock or system clock).
 */

/* Include config.h first to get platform-specific definitions */
#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include "ptpdlib.h"
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <string.h>

static PtpClock *g_ptp = NULL;
static int show_time = 0;  /* Set to 1 with --show-time to display clock */

void signal_handler(int sig) {
	if (sig == SIGINT || sig == SIGTERM) {
		fprintf(stderr, "\nReceived signal %d, shutting down...\n", sig);
		if (g_ptp) {
			ptpd_shutdown(g_ptp);
			g_ptp = NULL;
		}
		exit(0);
	}
}

int main(int argc, char **argv)
{
	Integer16 ret;
	int new_argc = argc;
	char **new_argv = argv;
	int i;

	/* Check for --show-time flag before passing to ptpd */
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--show-time") == 0) {
			show_time = 1;
			/* Remove this argument from argv */
			new_argc--;
			/* Shift remaining args */
			for (int j = i; j < argc - 1; j++) {
				argv[j] = argv[j + 1];
			}
			break;
		}
	}

	/* Install signal handlers */
	signal(SIGINT, signal_handler);
	signal(SIGTERM, signal_handler);

	/* Initialize PTP daemon */
	g_ptp = ptpd_init(new_argc, new_argv, &ret);
	if (!g_ptp) {
		return ret;
	}

	/* Start daemon in background thread */
	if (ptpd_start(g_ptp) != 0) {
		fprintf(stderr, "Failed to start PTP daemon\n");
		return -1;
	}

	/* Keep running until daemon stops or signal received */
	if (show_time) {
		/* Demonstrate ptpd_gettime() API */
		fprintf(stderr, "Displaying time from ptpd (swclock backend if enabled)\n");
		fprintf(stderr, "Press Ctrl+C to exit\n\n");
		
		while (ptpd_is_running(g_ptp)) {
			struct timespec ts;
			if (ptpd_gettime(g_ptp, CLOCK_REALTIME, &ts) == 0) {
				struct tm *tm_info = localtime(&ts.tv_sec);
				char time_str[64];
				strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);
				fprintf(stderr, "\r%s.%09ld", time_str, ts.tv_nsec);
				fflush(stderr);
			}
			usleep(100000);  /* Update 10x per second */
		}
	} else {
		/* Original behavior - just wait */
		while (ptpd_is_running(g_ptp)) {
			sleep(1);
		}
	}

	/* Cleanup */
	ptpd_shutdown(g_ptp);

	return 0;
}
