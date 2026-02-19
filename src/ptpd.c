/*-
 * Copyright (c) 2012-2013 Wojciech Owczarek,
 * Copyright (c) 2011-2012 George V. Neville-Neil,
 *			   Steven Kreuzer,
 *			   Martin Burnicki,
 *			   Jan Breuer,
 *			   Gael Mace,
 *			   Alexandre Van Kempen,
 *			   Inaqui Delgado,
 *			   Rick Ratzel,
 *			   National Instruments.
 * Copyright (c) 2009-2010 George V. Neville-Neil,
 *			   Steven Kreuzer,
 *			   Martin Burnicki,
 *			   Jan Breuer,
 *			   Gael Mace,
 *			   Alexandre Van Kempen
 *
 * Copyright (c) 2005-2008 Kendall Correll, Aidan Williams
 *
 * All Rights Reserved
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @file   ptpd.c
 * @date   Wed Jun 23 10:13:38 2010
 *
 * @brief  The main() function for the PTP daemon
 *
 * This file contains very little code, as should be obvious,
 * and only serves to tie together the rest of the daemon.
 * All of the default options are set here, but command line
 * arguments and configuration file is processed in the
 * ptpdStartup() routine called
 * below.
 */

/* Include swclock BEFORE ptpd.h to prevent sys/timex.h conflicts */
#ifdef PTPD_USE_SWCLOCK
#include "sw_clock.h"
#endif

#include "ptpd.h"

#ifdef PTPD_LIBRARY_MODE
#include <pthread.h>
#endif

RunTimeOpts rtOpts;	/* statically allocated run-time configuration data */

Boolean startupInProgress;

/*
 * Global variable with the main PTP port. This is used to show the current
 * state in DBG()/message() without having to pass the pointer everytime.
 *
 * if ptpd is extended to handle multiple ports (eg, to instantiate a
 * Boundary Clock), then DBG()/message() needs a per-port pointer argument
 */
PtpClock *G_ptpClock = NULL;

TimingDomain timingDomain;

#ifdef PTPD_LIBRARY_MODE
/* Library mode: threading support */
static pthread_t protocol_thread;
static volatile Boolean thread_running = FALSE;
static PtpClock *library_ptpClock = NULL;
#endif

/* Common initialization function used by both main() and library API */
static PtpClock* ptpd_common_init(int argc, char **argv, Integer16 *ret)
{
	PtpClock       *ptpClock;
	TimingService  *ts;

	startupInProgress = TRUE;

	memset(&timingDomain, 0, sizeof(timingDomain));
	timingDomainSetup(&timingDomain);

	timingDomain.electionLeft = 10;

	/* Initialize run time options with command line arguments */
	if (!(ptpClock = ptpdStartup(argc, argv, ret, &rtOpts))) {
		if (*ret != 0 && !rtOpts.checkConfigOnly)
			ERROR(USER_DESCRIPTION" startup failed\n");
		return NULL;
	}

#ifdef PTPD_USE_SWCLOCK
	/* Create software clock instance */
	ptpClock->swclock = swclock_create();
	if (!ptpClock->swclock) {
		ERROR("Failed to create software clock\n");
		/* Continue with system clock fallback - ptpd_clock.h macros will handle */
	}
#endif

#ifdef PTPD_IOS
	/* Initialize iOS exit flag */
	ptpClock->ios_should_exit = FALSE;
#endif

	timingDomain.electionDelay = rtOpts.electionDelay;

	/* configure PTP TimeService */
	timingDomain.services[0] = &ptpClock->timingService;
	ts = timingDomain.services[0];
	strncpy(ts->id, "PTP0", TIMINGSERVICE_MAX_DESC);
	ts->dataSet.priority1	  = rtOpts.preferNTP;
	ts->dataSet.type	      = TIMINGSERVICE_PTP;
	ts->config		          = &rtOpts;
	ts->controller		      = ptpClock;
	ts->timeout		          = rtOpts.idleTimeout;
	ts->updateInterval	      = 1;
	ts->holdTime		      = rtOpts.ntpOptions.failoverTimeout;
	timingDomain.serviceCount = 1;

	if (rtOpts.ntpOptions.enableEngine) {
		ntpSetup(&rtOpts, ptpClock);
	} else {
	    timingDomain.serviceCount = 1;
	    timingDomain.services[1]  = NULL;
	}

	timingDomain.init(&timingDomain);
	timingDomain.updateInterval = 1;

	startupInProgress = FALSE;

	return ptpClock;
}

/* Common cleanup function */
static void ptpd_common_cleanup(void)
{
#ifdef PTPD_USE_SWCLOCK
	/* Destroy software clock instance if it was created */
	if (G_ptpClock && G_ptpClock->swclock) {
		swclock_destroy((SwClock*)G_ptpClock->swclock);
		G_ptpClock->swclock = NULL;
	}
#endif

	/* this also calls ptpd shutdown */
	timingDomain.shutdown(&timingDomain);

	NOTIFY("Self shutdown\n");
}

#ifdef PTPD_LIBRARY_MODE

/**
 * @brief Initialize PTP daemon for library mode
 * @param argc Argument count
 * @param argv Argument vector
 * @param ret Return code pointer
 * @return Initialized PtpClock pointer or NULL on failure
 */
PtpClock* ptpd_init(int argc, char **argv, Integer16 *ret)
{
	PtpClock *ptpClock;

	ptpClock = ptpd_common_init(argc, argv, ret);
	if (ptpClock) {
		library_ptpClock = ptpClock;
	}

	return ptpClock;
}

/**
 * @brief Thread function that runs the protocol engine
 */
static void* ptpd_protocol_thread(void *arg)
{
	PtpClock *ptpClock = (PtpClock *)arg;

	/* global variable for message(), please see comment on top of this file */
	G_ptpClock = ptpClock;

	/* do the protocol engine - this is a forever loop */
	protocol(&rtOpts, ptpClock);

	thread_running = FALSE;
	return NULL;
}

/**
 * @brief Start PTP daemon in a background thread (non-blocking)
 * @param ptpClock Initialized PTP clock
 * @return 0 on success, -1 on failure
 */
int ptpd_start(PtpClock *ptpClock)
{
	int ret;

	if (!ptpClock) {
		ERROR("ptpd_start: NULL PtpClock pointer\n");
		return -1;
	}

	if (thread_running) {
		ERROR("ptpd_start: Protocol thread already running\n");
		return -1;
	}

	thread_running = TRUE;

	ret = pthread_create(&protocol_thread, NULL, ptpd_protocol_thread, ptpClock);
	if (ret != 0) {
		ERROR("ptpd_start: Failed to create protocol thread: %s\n", strerror(ret));
		thread_running = FALSE;
		return -1;
	}

	return 0;
}

/**
 * @brief Check if daemon is running
 * @param ptpClock PTP clock instance
 * @return 1 if running, 0 if stopped
 */
int ptpd_is_running(PtpClock *ptpClock)
{
	(void)ptpClock;  /* unused */
	return thread_running ? 1 : 0;
}

/**
 * @brief Shutdown PTP daemon and cleanup resources
 * @param ptpClock PTP clock to shutdown
 */
void ptpd_shutdown(PtpClock *ptpClock)
{
	if (!ptpClock) {
		return;
	}

	if (thread_running) {
		/* Signal the protocol to stop */
		/* The protocol() function will check for shutdown conditions */
		/* and exit its loop, which will terminate the thread */
		
		/* Wait for thread to finish */
		pthread_join(protocol_thread, NULL);
		thread_running = FALSE;
	}

	/* cleanup */
	ptpd_common_cleanup();

	library_ptpClock = NULL;
}

/**
 * @brief Get time from PTP daemon's underlying clock
 * @param ptpClock PTP clock instance
 * @param clk_id Clock ID (CLOCK_REALTIME, CLOCK_MONOTONIC, etc.)
 * @param tp Timespec structure to receive the time
 * @return 0 on success, -1 on error
 */
int ptpd_gettime(PtpClock *ptpClock, clockid_t clk_id, struct timespec *tp)
{
	if (!ptpClock || !tp) {
		return -1;
	}

#ifdef PTPD_USE_SWCLOCK
	/* Get time from swclock if available */
	if (ptpClock->swclock) {
		return swclock_gettime((SwClock*)ptpClock->swclock, clk_id, tp);
	}
#endif

	/* Fall back to system clock */
	return clock_gettime(clk_id, tp);
}

#endif /* PTPD_LIBRARY_MODE */

#ifndef PTPD_LIBRARY_MODE

int main(int argc, char **argv)
{
	PtpClock       *ptpClock;
	Integer16      ret;

	/* Use common initialization */
	ptpClock = ptpd_common_init(argc, argv, &ret);
	if (!ptpClock) {
		return ret;
	}

	/* global variable for message(), please see comment on top of this file */
	G_ptpClock = ptpClock;

	/* do the protocol engine */
	protocol(&rtOpts, ptpClock);
	/* forever loop.. */

	/* cleanup */
	ptpd_common_cleanup();

	return 1;
}

#endif /* !PTPD_LIBRARY_MODE */
