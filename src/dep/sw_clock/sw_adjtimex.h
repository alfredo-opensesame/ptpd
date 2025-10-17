#pragma once
#include <sys/time.h>
#include <stdint.h>
#include "swclock.h"


/*
 * Portable shim for adjtimex/ntp_adjtime flags across Linux, macOS, BSD.
 * Uses system <sys/timex.h> if available, and normalizes flags.
 */
#if __has_include(<sys/timex.h>)
#  include <sys/timex.h>
#else
  struct timex {
      int   modes;
      long  freq;
      long  offset;
      struct timeval time;
  };
#endif

/* ---- Flag normalization ---- */
#ifndef ADJ_OFFSET
#  ifdef MOD_OFFSET
#    define ADJ_OFFSET MOD_OFFSET
#  else
#    define ADJ_OFFSET 0x0001
#  endif
#endif

#ifndef ADJ_FREQUENCY
#  ifdef MOD_FREQUENCY
#    define ADJ_FREQUENCY MOD_FREQUENCY
#  else
#    define ADJ_FREQUENCY 0x0002
#  endif
#endif

#ifndef ADJ_SETOFFSET
#  define ADJ_SETOFFSET 0
#endif

#ifndef ADJ_NANO
#  define ADJ_NANO 0
#endif

#ifndef TIME_OK
#  define TIME_OK 0
#endif

/*
 * Software implementation of adjtimex()/ntp_adjtime() using SwClock.
 */
int sw_adjtimex(SwClock *sw, struct timex *tx);
#define sw_ntp_adjtime(sw, tx) sw_adjtimex((sw), (tx))
