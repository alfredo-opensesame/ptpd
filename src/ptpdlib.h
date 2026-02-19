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

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize PTP daemon for library mode
 * @param argc Argument count (same as main())
 * @param argv Argument vector (same as main())
 * @param ret Return code pointer (set on failure)
 * @return Initialized PtpClock pointer or NULL on failure
 * 
 * This function only initializes the daemon state. The protocol is not
 * started until ptpd_start() is called.
 * 
 * Example:
 *   Integer16 ret;
 *   PtpClock *ptp = ptpd_init(argc, argv, &ret);
 *   if (!ptp) {
 *       fprintf(stderr, "Init failed with code %d\n", ret);
 *       return ret;
 *   }
 */
PtpClock* ptpd_init(int argc, char **argv, Integer16 *ret);

/**
 * @brief Start PTP daemon in a background thread (non-blocking)
 * @param ptpClock Initialized PTP clock from ptpd_init()
 * @return 0 on success, -1 on failure
 * 
 * Starts the protocol engine in a new background thread and returns immediately.
 * The daemon continues running until ptpd_shutdown() is called.
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
int ptpd_start(PtpClock *ptpClock);

/**
 * @brief Check if PTP daemon thread is still running
 * @param ptpClock PTP clock instance
 * @return 1 if running, 0 if stopped
 * 
 * Use this to monitor the daemon state.
 * 
 * Example:
 *   while (ptpd_is_running(ptp)) {
 *       sleep(1);
 *   }
 */
int ptpd_is_running(PtpClock *ptpClock);

/**
 * @brief Shutdown PTP daemon and cleanup resources
 * @param ptpClock PTP clock to shutdown
 * 
 * Signals the protocol thread to stop and waits for it to terminate.
 * All resources are cleaned up automatically. After this call, the
 * PtpClock pointer is invalid and should not be used.
 */
void ptpd_shutdown(PtpClock *ptpClock);

/**
 * @brief Get time from PTP daemon's underlying clock
 * @param ptpClock PTP clock instance
 * @param clk_id Clock ID (CLOCK_REALTIME, CLOCK_MONOTONIC, CLOCK_MONOTONIC_RAW)
 * @param tp Timespec structure to receive the time
 * @return 0 on success, -1 on error
 * 
 * When ptpd is built with swclock support (BUILD_WITH_SWCLOCK=ON), this
 * function returns time from the software clock that is being disciplined
 * by the PTP servo. Otherwise, it returns system clock time.
 * 
 * Applications should use this function instead of clock_gettime() to read
 * the time that PTP is controlling.
 * 
 * Example:
 *   struct timespec ts;
 *   if (ptpd_gettime(ptp, CLOCK_REALTIME, &ts) == 0) {
 *       printf("Time: %ld.%09ld\n", ts.tv_sec, ts.tv_nsec);
 *   }
 */
int ptpd_gettime(PtpClock *ptpClock, clockid_t clk_id, struct timespec *tp);

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
void ptpd_set_log_callback(void (*callback)(const char* message, int priority));
#endif

#ifdef __cplusplus
}
#endif

#endif /* PTPDLIB_H_ */
