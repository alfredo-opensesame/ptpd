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

#ifdef __cplusplus
}
#endif

#endif /* PTPDLIB_H_ */
