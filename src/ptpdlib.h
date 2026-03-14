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

#ifdef PTPD_IOS
/**
 * @brief Register log message callback for iOS integration
 * @param callback Function pointer to receive log messages
 *
 * iOS applications can register a callback to receive all ptpd log messages
 * for display in the UI. The callback receives the formatted message string
 * and priority level (LOG_ERR, LOG_WARNING, LOG_INFO, LOG_DEBUG, etc.).
 *
 * The callback is invoked from the PTP daemon thread and should return quickly
 * to avoid blocking protocol operation. It's recommended to copy the message
 * and dispatch to the main thread for UI updates.
 *
 * Example (Swift bridging):
 *   void log_callback(const char* message, int priority) {
 *       // Marshal to Swift/UI thread
 *       dispatch_async(dispatch_get_main_queue(), ^{
 *           // Update UI with message
 *       });
 *   }
 *   ptpd_set_log_callback(log_callback);
 *
 * @note Only available when build with -DPTPD_IOS
 */
void ptpd_set_log_callback(void (*callback)(const char *message, int priority));
#endif

#ifdef __cplusplus
}
#endif

#endif /* PTPDLIB_H_ */
