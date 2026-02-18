/*-
 * Copyright (c) 2025-2026 PTPd Contributors
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
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @file   ptpd_clock.h
 * @date   Feb 2026
 *
 * @brief  Clock abstraction layer for ptpd
 *
 * This header provides a clean abstraction over system clock vs. swclock,
 * allowing ptpd to be compiled with either backend via BUILD_WITH_SWCLOCK.
 */

#ifndef PTPD_CLOCK_H_
#define PTPD_CLOCK_H_

#include <time.h>

/* 
 * Global PtpClock instance - defined in ptpd.c 
 * PtpClock typedef is in datatypes.h - must be includded before this header
 */
#ifndef PTPD_H_
#error "ptpd_clock.h must be included after ptpd.h (or datatypes.h)"
#endif

extern PtpClock *G_ptpClock;

#ifdef PTPD_USE_SWCLOCK
/* Include swclock header when using software clock backend */
#include "sw_clock.h"

/* Add missing STA_* constants not defined by swclock */
#ifndef STA_INS
#define STA_INS         0x0010  /* insert (add) leap second */
#endif
#ifndef STA_DEL
#define STA_DEL         0x0020  /* delete (remove) leap second */
#endif

/**
 * Get time from swclock instance
 * @param ptpClock PtpClock instance containing swclock
 * @param clk_id Clock ID (CLOCK_REALTIME, CLOCK_MONOTONIC, etc.)
 * @param tp Timespec to receive time
 */
#define ptpd_clock_gettime(ptpClock, clk_id, tp) \
    swclock_gettime((ptpClock)->swclock, (clk_id), (tp))

/**
 * Set time on swclock instance
 * @param ptpClock PtpClock instance containing swclock
 * @param clk_id Clock ID
 * @param tp Timespec with new time
 */
#define ptpd_clock_settime(ptpClock, clk_id, tp) \
    swclock_settime((ptpClock)->swclock, (clk_id), (tp))

/**
 * Adjust swclock via timex structure
 * @param ptpClock PtpClock instance containing swclock
 * @param tx Timex structure with adjustment parameters
 */
#define ptpd_clock_adjtime(ptpClock, tx) \
    swclock_adjtime((ptpClock)->swclock, (tx))

/**
 * Standalone adjtime for leap second management (without PtpClock context)
 * Used by functions like unsetTimexFlags, getTimexFlags, etc.
 * Routes to swclock or system based on G_ptpClock availability
 */
#define ptpd_adjtime(tx) \
    ((G_ptpClock && G_ptpClock->swclock) ? \
     swclock_adjtime((SwClock*)G_ptpClock->swclock, (tx)) : \
     -1)

/* Replace all adjtimex/ntp_adjtime calls to use swclock */
#ifdef adjtimex
#undef adjtimex
#endif
#ifdef ntp_adjtime
#undef ntp_adjtime
#endif
#define adjtimex(tx) ptpd_adjtime(tx)
#define ntp_adjtime(tx) ptpd_adjtime(tx)

/* Additional timex constants not defined by swclock but needed by ptpd */
#ifndef TIME_INS
#define TIME_INS    1    /* insert leap second */
#endif
#ifndef TIME_DEL
#define TIME_DEL    2    /* delete leap second */
#endif
#ifndef TIME_OOP
#define TIME_OOP    3    /* leap second in progress */
#endif
#ifndef TIME_WAIT
#define TIME_WAIT   4    /* leap second has occurred */
#endif
#ifndef MOD_STATUS
#define MOD_STATUS  0x0010
#endif
#ifndef MOD_FREQUENCY
#define MOD_FREQUENCY 0x0002
#endif
#ifndef MOD_MAXERROR
#define MOD_MAXERROR 0x0004
#endif
#ifndef MOD_ESTERROR
#define MOD_ESTERROR 0x0008
#endif
#ifndef STA_RONLY
#define STA_RONLY 0xff00  /* read-only bits */
#endif
#ifndef STA_FREQHOLD
#define STA_FREQHOLD 0x0080
#endif

#else
/* Use system clock calls when swclock not enabled */

/**
 * Get time from system clock
 * @param ptpClock PtpClock instance (unused)
 * @param clk_id Clock ID
 * @param tp Timespec to receive time
 */
#define ptpd_clock_gettime(ptpClock, clk_id, tp) \
    clock_gettime((clk_id), (tp))

/**
 * Set time on system clock
 * @param ptpClock PtpClock instance (unused)
 * @param clk_id Clock ID
 * @param tp Timespec with new time
 */
#define ptpd_clock_settime(ptpClock, clk_id, tp) \
    clock_settime((clk_id), (tp))

/**
 * Adjust system clock via adjtimex/ntp_adjtime
 * Note: This macro is not directly usable for system clock as the API varies
 * by platform. Use adjFreq_wrapper() or platform-specific calls instead.
 * @param ptpClock PtpClock instance (unused)
 * @param tx Timex structure (unused for system - use adjfreq instead)
 */
#define ptpd_clock_adjtime(ptpClock, tx) \
    (-1) /* Not directly supported - use adjFreq_wrapper() */

/* For system clock, use native adjtimex/ntp_adjtime - no redefinition */

#endif /* PTPD_USE_SWCLOCK */

#endif /* PTPD_CLOCK_H_ */
