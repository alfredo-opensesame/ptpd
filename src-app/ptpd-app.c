/**
 * @file   ptpd-app.c
 * @brief  Example application using ptpdlib
 *
 * This is a reference implementation showing how to use ptpd as a library.
 * It provides identical functionality to the built-in ptpd2 executable
 * but uses the public library API which runs the daemon in a background thread.
 */

/* Include config.h first to get platform-specific definitions */
#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include "ptpdlib.h"
#include <stdio.h>
#include <signal.h>
#include <unistd.h>

static PtpClock *g_ptp = NULL;

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

	/* Install signal handlers */
	signal(SIGINT, signal_handler);
	signal(SIGTERM, signal_handler);

	/* Initialize PTP daemon */
	g_ptp = ptpd_init(argc, argv, &ret);
	if (!g_ptp) {
		return ret;
	}

	/* Start daemon in background thread */
	if (ptpd_start(g_ptp) != 0) {
		fprintf(stderr, "Failed to start PTP daemon\n");
		return -1;
	}

	/* Keep running until daemon stops or signal received */
	while (ptpd_is_running(g_ptp)) {
		sleep(1);
	}

	/* Cleanup */
	ptpd_shutdown(g_ptp);

	return 0;
}
