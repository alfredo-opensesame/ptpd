/**
 * @file   ptpdlib.h
 * @brief  Public API for PTP daemon library mode
 *
 * This header provides the public interface for using ptpd as a library.
 * Library users should include this file instead of ptpd.h to access
 * only the library API functions without exposing internal implementation.
 *
 * The library always runs in a background thread and never blocks the caller.
 */

#ifndef PTPDLIB_H_
#define PTPDLIB_H_

#include "ptpd.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque library handle.  PtpdHandle is a transparent alias for PtpClock
 * so that callers use the public name while internal code continues to
 * use PtpClock*.  Field access via the pointer still compiles; the alias
 * exists to give the public API a stable name independent of internals.
 */
typedef PtpClock PtpdHandle;

/**
 * ── Thread-safety contract ───────────────────────────────────────────────────
 *
 * The PTP daemon always runs in a single background thread created by
 * ptpd_start().  The rules below apply to calls made from *other* threads.
 *
 * Safe to call concurrently with the protocol thread (no external lock needed):
 *   ptpd_is_running()   — reads a volatile Boolean, effectively atomic.
 *   ptpd_get_status()   — reads individual pointer-size fields; each load is
 *                         atomic on all supported arches, but the snapshot as
 *                         a whole is not transactional.
 *   ptpd_gettime() / ptpd_gettime_ex()
 *                       — delegates to swclock_gettime() which holds its own
 *                         internal read-lock.
 *   ptpd_set_log_callback()
 *                       — pointer store;  set this before ptpd_start() or
 *                         while the thread is not in logMessage().
 *
 * Must NOT be called concurrently with each other or with ptpd_start():
 *   ptpd_stop()         — joins the protocol thread; serialise with start.
 *   ptpd_shutdown()     — joins the protocol thread; do not call from two
 *                         threads simultaneously.
 *
 * Not safe to call from a signal handler (they use pthread_join internally).
 * ─────────────────────────────────────────────────────────────────────────────
 */

/**
 * @brief Initialize PTP daemon for library mode
 * @param argc Argument count (same as main())
 * @param argv Argument vector (same as main())
 * @param ret Return code pointer (set on failure)
 * @return Initialized PtpdHandle pointer or NULL on failure
 *
 * This function only initializes the daemon state. The protocol is not
 * started until ptpd_start() is called.
 *
 * Example:
 *   Integer16 ret;
 *   PtpdHandle *ptp = ptpd_init(argc, argv, &ret);
 *   if (!ptp) {
 *       fprintf(stderr, "Init failed with code %d\n", ret);
 *       return ret;
 *   }
 */
PtpdHandle *ptpd_init(int argc, char **argv, Integer16 *ret);

/**
 * @brief Start PTP daemon in a background thread (non-blocking)
 * @param ptpClock Initialized PTP clock from ptpd_init()
 * @return 0 on success, -1 on failure
 *
 * Starts the protocol engine in a new background thread and returns
 * immediately. The daemon continues running until ptpd_shutdown() is called.
 *
 * Example:
 *   if (ptpd_start(ptp) != 0) {
 *       fprintf(stderr, "Failed to start daemon\n");
 *       return -1;
 *   }
 *   // Daemon is now running in background
 *   // ... do other work ...
 *   ptpd_shutdown(ptp);
 */
int ptpd_start(PtpdHandle *ptpClock);

/**
 * @brief Check if PTP daemon thread is still running
 * @param ptpClock PtpdHandle from ptpd_init()
 * @return 1 if running, 0 if stopped
 *
 * Use this to monitor the daemon state.
 *
 * Example:
 *   while (ptpd_is_running(ptp)) {
 *       sleep(1);
 *   }
 */
int ptpd_is_running(PtpdHandle *ptpClock);

/**
 * @brief Shutdown PTP daemon and cleanup resources
 * @param ptpClock PtpdHandle from ptpd_init()
 *
 * Signals the protocol thread to stop and waits for it to terminate.
 * All resources are cleaned up automatically. After this call, the
 * PtpdHandle pointer is invalid and should not be used.
 */
void ptpd_shutdown(PtpdHandle *ptpClock);

/**
 * @brief Stop the PTP protocol thread, preserving servo state for restart (A3)
 * @param ptpClock PtpdHandle from ptpd_init()
 *
 * Signals the protocol thread to exit and waits for it to finish, but does
 * NOT free any resources or reset the servo.  ptpd_start() may be called
 * again afterwards; the daemon resumes with drift and statistics intact so
 * re-lock is faster than a cold start.
 *
 * This is the correct stop primitive for iOS background/foreground
 * transitions: stop on backgrounding, restart on foregrounding.
 *
 * If the daemon is not running, this is a no-op.
 *
 * Thread safety: must not be called concurrently with ptpd_start() or
 * ptpd_shutdown().
 *
 * Example:
 *   ptpd_stop(ptp);    // background — thread exits, servo state kept
 *   // ... time passes ...
 *   ptpd_start(ptp);   // foreground — resumes with preserved drift
 */
void ptpd_stop(PtpdHandle *ptpClock);

/**
 * Source of a timestamp returned by ptpd_gettime_ex().
 */
typedef enum {
    PTPD_TIME_SOURCE_SWCLOCK  = 0, /**< swclock, disciplined by PTP servo       */
    PTPD_TIME_SOURCE_SYSCLOCK = 1, /**< kernel clock_gettime() (fallback/no-PTP)*/
} ptpd_time_source_t;

/**
 * Extended timestamp result returned by ptpd_gettime_ex().
 *
 * The timestamp in @c ts is always valid when ptpd_gettime_ex() returns 0.
 * The remaining fields describe the quality of that timestamp.
 */
typedef struct {
    struct timespec    ts;              /**< The timestamp                              */
    ptpd_time_source_t source;          /**< Where the timestamp came from              */
    int                is_synchronized; /**< 1 iff state == PTP_SLAVE and servo settled */
    int64_t            offset_ns;       /**< Last known offset from master (ns)         */
    int64_t            uncertainty_ns;  /**< swclock maxerror in ns; INT64_MAX when
                                             unknown (sysclock path or no data yet)      */
} ptpd_time_t;

/**
 * @brief Get time with full quality metadata (preferred over ptpd_gettime)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param clk_id Clock ID (CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_MONOTONIC_RAW)
 * @param out Extended result structure to fill
 * @return 0 on success, -1 if ptpClock or out is NULL
 *
 * Always fills *out and returns 0 (unless arguments are NULL).  On the swclock
 * path the timestamp is PTP-disciplined; on the SYSCLOCK fallback path it is
 * plain clock_gettime().  Inspect out->source to distinguish.
 *
 * Example:
 *   ptpd_time_t t;
 *   ptpd_gettime_ex(ptp, CLOCK_REALTIME, &t);
 *   if (!t.is_synchronized)
 *       fprintf(stderr, "PTP not locked (uncertainty ±%lld ns)\n", t.uncertainty_ns);
 *   use_time(&t.ts);
 */
int ptpd_gettime_ex(PtpdHandle *ptpClock, clockid_t clk_id, ptpd_time_t *out);

/**
 * @brief Get time from PTP daemon's underlying clock
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param clk_id Clock ID (CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_MONOTONIC_RAW)
 * @param tp Timespec structure to receive the time
 * @return 0 on success, -1 on error
 *
 * Convenience wrapper around ptpd_gettime_ex().  When built with swclock
 * (BUILD_WITH_SWCLOCK=ON) returns 0 only if the swclock path succeeded;
 * returns -1 if swclock is unavailable so the caller is never silently given
 * undisciplined kernel time.  Use ptpd_gettime_ex() when you need quality
 * metadata or want to handle the sysclock fallback yourself.
 *
 * Example:
 *   struct timespec ts;
 *   if (ptpd_gettime(ptp, CLOCK_REALTIME, &ts) == 0) {
 *       printf("Time: %ld.%09ld\n", ts.tv_sec, ts.tv_nsec);
 *   }
 */
int ptpd_gettime(PtpdHandle *ptpClock, clockid_t clk_id, struct timespec *tp);

/**
 * Current PTP daemon status snapshot (A7).
 * All fields reflect the state at the moment of the ptpd_get_status() call.
 */
typedef struct {
    uint8_t  state;           /**< Port state (PTP_SLAVE, PTP_LISTENING, …)  */
    int64_t  offset_ns;       /**< Current offsetFromMaster (nanoseconds)     */
    int64_t  delay_ns;        /**< Current meanPathDelay (nanoseconds)        */
    int32_t  drift_ppb;       /**< Servo observedDrift (parts per billion)    */
    int      is_synchronized; /**< 1 when state == PTP_SLAVE                  */
} ptpd_status_t;

/**
 * @brief Read a snapshot of current PTP status (A7 + B4)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param out Status snapshot to fill
 * @return 0 on success, -1 if either argument is NULL
 *
 * Returns offset, delay, servo drift, and port state without requiring direct
 * access to internal ptpClock fields (covers B4 for drift/uncertainty).
 *
 * Thread safety: see contract comment above — individual field reads are
 * atomic but the snapshot is not transactional.
 *
 * Example:
 *   ptpd_status_t s;
 *   ptpd_get_status(ptp, &s);
 *   printf("state=%d offset=%lld ns drift=%d ppb\n",
 *          s.state, (long long)s.offset_ns, s.drift_ppb);
 */
int ptpd_get_status(PtpdHandle *ptpClock, ptpd_status_t *out);

/**
 * @brief Register log message callback (available on all library-mode builds) (A6)
 * @param callback Function pointer to receive log messages
 *
 * Register a callback to receive all ptpd log messages for display or
 * forwarding.  The callback receives the formatted message string and a
 * syslog-style priority level (LOG_ERR, LOG_WARNING, LOG_INFO, LOG_DEBUG).
 *
 * The callback is invoked from the PTP daemon thread and must return quickly.
 * Copy the message and dispatch to another thread for any UI updates.
 *
 * Thread safety: safe to register before ptpd_start() or during normal
 * operation — the pointer store is effectively atomic.
 *
 * Example:
 *   void log_cb(const char *msg, int priority) {
 *       fprintf(stderr, "[ptp] %s", msg);
 *   }
 *   ptpd_set_log_callback(log_cb);
 */
void ptpd_set_log_callback(void (*callback)(const char *message, int priority));

#ifdef __cplusplus
}
#endif

#endif /* PTPDLIB_H_ */
