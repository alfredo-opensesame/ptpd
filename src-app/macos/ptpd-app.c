/**
 * @file   ptpd-app.c
 * @brief  Example application using ptpdlib with detailed performance logging
 *
 * Extra flags (stripped before passing argv to ptpd):
 *   --show-time           Print live clock time to stderr
 *   --servo-log <path>    Write servo + swclock metrics CSV every second
 *   --swclock-log <path>  Write swclock internal event log (passed to swclock)
 *
 * Servo log CSV columns (when built with PTPD_STATISTICS and PTPD_USE_SWCLOCK):
 *   timestamp_iso, elapsed_s, ptp_active,
 *   ptpd_offset_input_ns, ptpd_servo_output_ppb, ptpd_observed_drift_ppb,
 *   ptpd_kP, ptpd_kI,
 *   ptpd_drift_mean_ppb, ptpd_drift_std_ppb, ptpd_drift_median_ppb,
 *   ptpd_update_count,
 *   swclock_remaining_phase_ns,
 *   swclock_mean_te_ns, swclock_std_te_ns, swclock_max_te_ns,
 *   swclock_mtie_1s_ns, swclock_mtie_10s_ns, swclock_tdev_1s_ns,
 *   gettime_vs_system_ns
 */

/* Include config.h first to get platform-specific definitions */
#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include "ptpdlib.h"
#include "datatypes.h"

#ifdef PTPD_USE_SWCLOCK
# include "sw_clock.h"
# include "sw_clock_monitor.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <pthread.h>
#include <math.h>
#include <limits.h>
#include "ptpd_app_utils.h"

/* ------------------------------------------------------------------ */
/* Globals                                                             */
/* ------------------------------------------------------------------ */
static PtpdHandle  *g_ptp             = NULL;
static int          show_time         = 0;
static char         servo_log_path[PATH_MAX]   = "";
static char         swclock_log_path[PATH_MAX] = "";
static volatile int g_stop            = 0;
static pthread_t    g_monitor_tid;
static struct timespec g_start_ts;   /* CLOCK_REALTIME at startup (pidfile timestamp) */
static struct timespec g_start_mono; /* CLOCK_MONOTONIC at startup (for elapsed_s)    */
static char         pidfile_path[PATH_MAX]     = "";

/* ------------------------------------------------------------------ */
/* Signal handler  (async-signal-safe: only sets g_stop flag)         */
/* ------------------------------------------------------------------ */
void signal_handler(int sig)
{
	(void)sig;
	g_stop = 1;
}

/* ------------------------------------------------------------------ */
/* ISO-8601 timestamp helper                                           */
/* ------------------------------------------------------------------ */
static void iso_timestamp(char *buf, size_t n)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	struct tm *tm_info = gmtime(&ts.tv_sec);
	size_t len = strftime(buf, n, "%Y-%m-%dT%H:%M:%S", tm_info);
	snprintf(buf + len, n - len, ".%06ldZ", ts.tv_nsec / 1000);
}

/* ------------------------------------------------------------------ */
/* Monitoring thread - polls servo + swclock state every 1s           */
/* ------------------------------------------------------------------ */
static void *monitor_thread(void *arg)
{
	FILE *fp = (FILE *)arg;

	/* Write CSV header - columns depend on compile-time features */
	fprintf(fp,
		"timestamp_iso,"
		"elapsed_s,"
		"ptp_active,"
		"ptpd_offset_input_ns,"
		"ptpd_servo_output_ppb,"
		"ptpd_observed_drift_ppb,"
		"ptpd_kP,"
		"ptpd_kI,"
		/* NOTE: gettime_vs_system_ns is intentionally omitted.
		 * ptpd_gettime() calls swclock_gettime() which acquires a pthread_rwlock_rdlock.
		 * The swclock background poll thread runs at 100 Hz and constantly acquires
		 * pthread_rwlock_wrlock.  On macOS (writer-preference rwlock) this starves
		 * all reader lock requests, causing the monitor thread to block permanently
		 * after ~30 rows.  The swclock_get_remaining_phase_ns() call below uses
		 * wrlock and is fine (wrlocks serialize without starvation). */
#ifdef PTPD_STATISTICS
		"ptpd_drift_mean_ppb,"
		"ptpd_drift_std_ppb,"
		"ptpd_drift_median_ppb,"
		"ptpd_update_count,"
#endif
#ifdef PTPD_USE_SWCLOCK
		"swclock_remaining_phase_ns,"
		"swclock_mean_te_ns,"
		"swclock_std_te_ns,"
		"swclock_max_te_ns,"
		"swclock_mtie_1s_ns,"
		"swclock_mtie_10s_ns,"
		"swclock_tdev_1s_ns"
#endif
		"\n");
	fflush(fp);

	/* Run for the full duration regardless of whether ptpd has a master.
	 * ptp_active=1 when locked, 0 when listening/no-master. This lets
	 * us record gettime drift even during the LISTENING phase and avoids
	 * the process dying silently if the GM is temporarily unavailable. */
	while (!g_stop) {
		char ts_buf[64];
		iso_timestamp(ts_buf, sizeof(ts_buf));

		/* Elapsed seconds — use CLOCK_MONOTONIC so ptpd's CLOCK_REALTIME
		 * step corrections don't produce negative or jumpy elapsed_s values. */
		struct timespec now_mono;
		clock_gettime(CLOCK_MONOTONIC, &now_mono);
		double elapsed = (double)(now_mono.tv_sec  - g_start_mono.tv_sec) +
		                 (now_mono.tv_nsec - g_start_mono.tv_nsec) * 1e-9;

		/* ptp_active=1 only when servo is engaged (kP > 0 means ptpd is
		 * in SLAVE/UNCALIBRATED state and processing sync messages). */
		int ptp_active = (g_ptp != NULL) && ptpd_is_running(g_ptp)
		                 && (g_ptp->servo.kP > 0.0);

		/* ptpd servo internals (only valid when active) */
		int32_t offset_ns     = 0;
		double  servo_out_ppb = 0.0;
		double  obs_drift_ppb = 0.0;
		double  kP            = 0.0;
		double  kI            = 0.0;
#ifdef PTPD_STATISTICS
		double  drift_mean    = 0.0;
		double  drift_std     = 0.0;
		double  drift_med     = 0.0;
		int     upd_count     = 0;
#endif
		if (ptp_active) {
			offset_ns     = g_ptp->servo.input;
			servo_out_ppb = g_ptp->servo.output;
			obs_drift_ppb = g_ptp->servo.observedDrift;
			kP            = g_ptp->servo.kP;
			kI            = g_ptp->servo.kI;
#ifdef PTPD_STATISTICS
			drift_mean    = g_ptp->servo.driftMean;
			drift_std     = g_ptp->servo.driftStdDev;
			drift_med     = g_ptp->servo.driftMedian;
			upd_count     = g_ptp->servo.updateCount;
#endif
		}



#ifdef PTPD_USE_SWCLOCK
		long long remaining_phase_ns = 0;
		swclock_metrics_snapshot_t metrics;
		int have_metrics = 0;
		if (ptp_active && g_ptp->swclock) {
			SwClock *sc = (SwClock *)g_ptp->swclock;
			remaining_phase_ns = swclock_get_remaining_phase_ns(sc);
			have_metrics       = (swclock_get_metrics(sc, &metrics) == 0);
		}
#endif

		/* --- Write CSV row --- */
		fprintf(fp, "%s,%.3f,%d,%d,%.3f,%.3f,%.6f,%.6f",
			ts_buf, elapsed, ptp_active,
			(int)offset_ns, servo_out_ppb, obs_drift_ppb,
			kP, kI);

#ifdef PTPD_STATISTICS
		fprintf(fp, ",%.3f,%.3f,%.3f,%d",
			drift_mean, drift_std, drift_med, upd_count);
#endif

#ifdef PTPD_USE_SWCLOCK
		if (have_metrics) {
			fprintf(fp, ",%lld,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f",
				remaining_phase_ns,
				metrics.mean_te_ns,
				metrics.std_te_ns,
				metrics.max_te_ns,
				metrics.mtie_1s_ns,
				metrics.mtie_10s_ns,
				metrics.tdev_1s_ns);
		} else {
			/* remaining_phase_ns filled; 6 metric columns empty (cols 14-19) */
			fprintf(fp, ",%lld,,,,,,", remaining_phase_ns);
		}
#endif

		fprintf(fp, "\n");
		fflush(fp);

		/* Sleep ~1s — implementation in ptpd_app_utils.c (CLOCK_MONOTONIC
		 * deadline, 50 ms slices, wakes within 50 ms of *stop becoming 1). */
		monotonic_sleep_1s(&g_stop);
	} /* while (!g_stop) */

	fclose(fp);
	return NULL;
}

/* ------------------------------------------------------------------ */
/* main                                                                */
/* strip_arg() and monotonic_sleep_1s() live in ptpd_app_utils.c      */
/* ------------------------------------------------------------------ */
int main(int argc, char **argv)
{
	Integer16 ret;
	int i;

	/* Strip our custom flags before forwarding argv to ptpd */
	for (i = 1; i < argc; ) {
		if (strip_arg(&argc, argv, i, "--show-time", 0, NULL, 0)) {
			show_time = 1;
		} else if (strip_arg(&argc, argv, i, "--servo-log", 1,
		                     servo_log_path, sizeof(servo_log_path))) {
			/* consumed */
		} else if (strip_arg(&argc, argv, i, "--swclock-log", 1,
		                     swclock_log_path, sizeof(swclock_log_path))) {
			/* consumed */
		} else if (strip_arg(&argc, argv, i, "--pidfile", 1,
		                     pidfile_path, sizeof(pidfile_path))) {
			/* consumed */
		} else {
			i++;
		}
	}

	signal(SIGINT,  signal_handler);
	signal(SIGTERM, signal_handler);

	clock_gettime(CLOCK_REALTIME,  &g_start_ts);
	clock_gettime(CLOCK_MONOTONIC, &g_start_mono);

	/* Write PID file so parent scripts can send SIGTERM to exactly this process */
	if (pidfile_path[0] != '\0') {
		FILE *pf = fopen(pidfile_path, "w");
		if (pf) { fprintf(pf, "%d\n", (int)getpid()); fclose(pf); }
		else { perror("Cannot write pidfile"); }
	}

	/* Initialize PTP daemon */
	g_ptp = ptpd_init(argc, argv, &ret);
	if (!g_ptp)
		return ret;

	/* ptpd_init() calls signal() for SIGTERM/SIGINT (catchSignals in startup.c),
	 * overriding our earlier registrations.  Re-install our handlers now so
	 * that g_stop is actually set when the script sends SIGTERM. */
	signal(SIGINT,  signal_handler);
	signal(SIGTERM, signal_handler);

	/* Start daemon in background thread */
	if (ptpd_start(g_ptp) != 0) {
		fprintf(stderr, "Failed to start PTP daemon\n");
		return -1;
	}

#ifdef PTPD_USE_SWCLOCK
	/* Enable swclock internal event log if requested */
	if (swclock_log_path[0] != '\0' && g_ptp->swclock) {
		swclock_start_log((SwClock *)g_ptp->swclock, swclock_log_path);
		fprintf(stderr, "swclock event log: %s\n", swclock_log_path);
	}
#endif

	/* Start servo monitoring thread if requested */
	if (servo_log_path[0] != '\0') {
		FILE *fp = fopen(servo_log_path, "w");
		if (!fp) {
			perror("Cannot open servo log");
		} else {
			fprintf(stderr, "Servo log: %s\n", servo_log_path);
			if (pthread_create(&g_monitor_tid, NULL, monitor_thread, fp) != 0) {
				perror("pthread_create monitor_thread");
				fclose(fp);
			}
		}
	}

	/* Main loop — runs until SIGTERM/SIGINT sets g_stop.
	 * We do NOT exit when ptpd_is_running() goes false (e.g. no GM found)
	 * so the script's sleep(RUN_DURATION) controls timing, not ptpd's state. */
	if (show_time) {
		fprintf(stderr, "Displaying time from ptpd (swclock backend if enabled)\n");
		fprintf(stderr, "Press Ctrl+C to exit\n\n");
		while (!g_stop) {
			if (g_ptp) {
				struct timespec ts;
				if (ptpd_gettime(g_ptp, CLOCK_REALTIME, &ts) == 0) {
					struct tm *tm_info = localtime(&ts.tv_sec);
					char time_str[64];
					strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);
					fprintf(stderr, "\r%s.%09ld", time_str, ts.tv_nsec);
					fflush(stderr);
				}
			}
			usleep(100000);
		}
	} else {
		while (!g_stop) {
			sleep(1);
		}
	}

	/* ---- Cleanup ---- */
	g_stop = 1;
	if (servo_log_path[0] != '\0')
		pthread_join(g_monitor_tid, NULL);

#ifdef PTPD_USE_SWCLOCK
	if (swclock_log_path[0] != '\0' && g_ptp && g_ptp->swclock)
		swclock_stop_event_log((SwClock *)g_ptp->swclock);
#endif

	if (g_ptp) {
		ptpd_shutdown(g_ptp);
		g_ptp = NULL;
	}

	if (pidfile_path[0] != '\0')
		unlink(pidfile_path);

	return 0;
}
