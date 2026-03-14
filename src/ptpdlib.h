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

#include <stdint.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque library handle.
 *
 * The concrete layout of struct PtpdHandle is private to the ptpd library.
 * External callers may only hold a PtpdHandle* pointer and pass it to the
 * API functions declared below.  Do NOT include ptpdlib_internal.h unless
 * you are implementing ptpd internals.
 */
typedef struct PtpdHandle PtpdHandle;

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
 * Error codes returned by ptpd_last_error() (A2).
 */
typedef enum {
    PTPD_OK            =  0, /**< No error                                    */
    PTPD_ERR_NULL_ARG  = -1, /**< NULL pointer passed to a library function   */
    PTPD_ERR_INIT      = -2, /**< ptpd_init() failed (see ret code for detail) */
    PTPD_ERR_THREAD    = -3, /**< pthread_create() failed in ptpd_start()      */
    PTPD_ERR_RUNNING   = -4, /**< ptpd_start() called while already running    */
} ptpd_error_t;

/**
 * @brief Return the last error that occurred on this handle (A2)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @return ptpd_error_t code; PTPD_OK (0) if no error has occurred
 *
 * The stored code is set whenever a library API function fails.  It is
 * cleared to PTPD_OK on a successful ptpd_start().
 *
 * Example:
 *   if (ptpd_start(ptp) != 0)
 *       fprintf(stderr, "start failed: %d\n", ptpd_last_error(ptp));
 */
int ptpd_last_error(PtpdHandle *ptpClock);

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
 *   int16_t ret;
 *   PtpdHandle *ptp = ptpd_init(argc, argv, &ret);
 *   if (!ptp) {
 *       fprintf(stderr, "Init failed with code %d\n", ret);
 *       return ret;
 *   }
 */
PtpdHandle *ptpd_init(int argc, char **argv, int16_t *ret);

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
 * @brief Register a state-change callback (A4)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param callback Function called on every port-state transition, or NULL to
 *                 unregister
 * @param user_data Opaque pointer forwarded to the callback unchanged
 *
 * The callback fires from the protocol thread immediately before the new
 * state is applied, so @p from_state is the current state and @p to_state
 * is the state being entered.  It must return quickly.
 *
 * Thread safety: safe to call at any time; the pointer write is atomic.
 *
 * Example:
 *   void on_state(uint8_t from, uint8_t to, void *ud) {
 *       printf("PTP state: %d -> %d\n", from, to);
 *   }
 *   ptpd_set_state_callback(ptp, on_state, NULL);
 */
void ptpd_set_state_callback(PtpdHandle *ptpClock,
    void (*callback)(uint8_t from_state, uint8_t to_state, void *user_data),
    void *user_data);

/**
 * @brief Change the runtime log verbosity level (A5)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param level syslog-style level: LOG_ERR, LOG_WARNING, LOG_INFO, LOG_DEBUG
 *
 * Takes effect immediately without restarting the daemon.  Equivalent to
 * setting ptpengine:log_level in the configuration, but at runtime.
 *
 * Thread safety: the write is atomic on all supported architectures.
 *
 * Example:
 *   ptpd_set_log_level(ptp, LOG_DEBUG);  // enable verbose output
 *   ptpd_set_log_level(ptp, LOG_ERR);    // quiet mode
 */
void ptpd_set_log_level(PtpdHandle *ptpClock, int level);

/**
 * Source of a timestamp returned by ptpd_gettime_ex().
 */
typedef enum {
    PTPD_TIME_SOURCE_SWCLOCK  = 0, /**< swclock, disciplined by PTP servo       */
    PTPD_TIME_SOURCE_SYSCLOCK = 1, /**< kernel clock_gettime() (fallback/no-PTP)*/
} ptpd_time_source_t;

/**
 * ptpdlib-native clock selector (B5).
 *
 * Use these constants with ptpd_gettime_clock() and ptpd_gettime_ex_clock()
 * instead of raw POSIX clockid_t values, which are a kernel-level abstraction
 * that has no meaning outside the OS.
 */
typedef enum {
    PTPD_CLOCK_WALL      = 0, /**< Disciplined wall clock   (→ CLOCK_REALTIME)       */
    PTPD_CLOCK_MONOTONIC = 1, /**< Monotonic from swclock   (→ CLOCK_MONOTONIC)      */
    PTPD_CLOCK_TAI       = 2, /**< TAI (= WALL + TAI offset). Uses ptpd_gettime_tai()*/
    PTPD_CLOCK_RAW       = 3, /**< Kernel uptime passthrough(→ CLOCK_MONOTONIC_RAW)  */
} ptpd_clock_id_t;

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
 * @brief Get time using a ptpdlib-native clock selector (B5)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param clk     ptpd_clock_id_t — PTPD_CLOCK_WALL/MONOTONIC/TAI/RAW
 * @param tp      Timespec to fill
 * @return 0 on success, -1 on error
 *
 * Convenience alternative to ptpd_gettime() that avoids exposing POSIX
 * clockid_t values in the caller.  PTPD_CLOCK_TAI delegates to
 * ptpd_gettime_tai() and returns -1 if the TAI offset is not yet set.
 *
 * Example:
 *   struct timespec ts;
 *   ptpd_gettime_clock(ptp, PTPD_CLOCK_WALL, &ts);
 */
int ptpd_gettime_clock(PtpdHandle *ptpClock, ptpd_clock_id_t clk,
                       struct timespec *tp);

/**
 * @brief Get time with quality metadata using a ptpdlib-native clock (B5)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param clk     ptpd_clock_id_t — PTPD_CLOCK_WALL/MONOTONIC/TAI/RAW
 * @param out     Extended result to fill
 * @return 0 on success, -1 on error
 *
 * Same as ptpd_gettime_ex() but accepts ptpd_clock_id_t.  For
 * PTPD_CLOCK_TAI the ts field already includes the TAI offset;
 * source, is_synchronized, offset_ns, and uncertainty_ns are
 * populated identically to ptpd_gettime_ex(CLOCK_REALTIME).
 *
 * Example:
 *   ptpd_time_t t;
 *   ptpd_gettime_ex_clock(ptp, PTPD_CLOCK_WALL, &t);
 *   if (t.is_synchronized) use_time(&t.ts);
 */
int ptpd_gettime_ex_clock(PtpdHandle *ptpClock, ptpd_clock_id_t clk,
                          ptpd_time_t *out);

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
 * @brief Return a human-readable name for a PTP port state value (A1)
 * @param state  uint8_t state from ptpd_status_t::state
 * @return       A static string, e.g. "SLAVE", "LISTENING", "MASTER"; returns
 *               "UNKNOWN" for unrecognised values. The pointer is valid for
 *               the lifetime of the process.
 *
 * Use this instead of the internal portState_getName() function, which is
 * not available in opaque-handle builds.
 *
 * Example:
 *   ptpd_status_t s;
 *   ptpd_get_status(ptp, &s);
 *   printf("state: %s\n", ptpd_state_name(s.state));
 */
const char *ptpd_state_name(uint8_t state);

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

/**
 * @brief Get TAI time from the PTP-disciplined clock (B3)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param tp Timespec to fill with TAI time
 * @return 0 on success; -1 if swclock unavailable or TAI offset unknown (0)
 *
 * Returns CLOCK_REALTIME + the TAI-UTC offset maintained by swclock (set by
 * the PTP servo via ADJ_TAI).  The result is safe to use across leap seconds
 * because the offset is applied atomically with the timestamp read (both under
 * the swclock read-lock).
 *
 * Returns -1 if swclock is not available or if the TAI offset has never been
 * set (i.e. is still 0 — indistinguishable from an uninitialised offset).
 *
 * Example:
 *   struct timespec tai;
 *   if (ptpd_gettime_tai(ptp, &tai) == 0)
 *       printf("TAI: %ld.%09ld\n", tai.tv_sec, tai.tv_nsec);
 */
int ptpd_gettime_tai(PtpdHandle *ptpClock, struct timespec *tp);

/**
 * @brief Atomically timestamp an external event with the disciplined clock (B6)
 * @param ptpClock PtpdHandle from ptpd_init()
 * @param out Extended timestamp result (same as ptpd_gettime_ex)
 * @return 0 on success, -1 if either argument is NULL
 *
 * Equivalent to ptpd_gettime_ex(handle, CLOCK_REALTIME, out) but documents
 * the atomicity guarantee explicitly: the swclock read-lock is held for the
 * duration of the call, so the timestamp is consistent with the servo state
 * at the exact moment of the call.  No concurrent servo step or drift
 * correction can interleave.
 *
 * Use this instead of calling ptpd_gettime() manually when timestamping
 * external events (hardware interrupts, audio frames, etc.).
 *
 * Example:
 *   ptpd_time_t ts;
 *   ptpd_timestamp_event(ptp, &ts);
 *   record_event(event_id, &ts.ts, ts.is_synchronized);
 */
int ptpd_timestamp_event(PtpdHandle *ptpClock, ptpd_time_t *out);

#ifdef __cplusplus
}
#endif

#endif /* PTPDLIB_H_ */
