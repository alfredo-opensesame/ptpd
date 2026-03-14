/**
 * @file   ptpdlib_internal.h
 * @brief  Private struct layout of PtpdHandle — for ptpd internals ONLY
 *
 * External library consumers MUST NOT include this header.  They should only
 * include ptpdlib.h, which forward-declares PtpdHandle as an opaque type.
 *
 * Include this header only in translation units that need to DEREFERENCE the
 * handle (currently: ptpd.c, ptpd-app.c).
 */

#ifndef PTPDLIB_INTERNAL_H_
#define PTPDLIB_INTERNAL_H_

/* Public API forward-declares PtpdHandle; we must see it before defining it. */
#include "ptpdlib.h"

/* ptpd.h pulls in the full internal type chain (constants.h, datatypes.h,
 * ptp_datatypes.h, etc.) that datatypes.h alone cannot satisfy. */
#include "ptpd.h"

/**
 * Concrete definition of the opaque PtpdHandle.
 *
 * The handle is a thin wrapper around a heap-allocated PtpClock.  Separating
 * the two allows ptpdlib.h to remain free of any internal type dependencies
 * while still permitting the protocol engine to live in its own allocation.
 */
struct PtpdHandle {
    PtpClock *clock; /**< Pointer to the PTP engine state */
};

#endif /* PTPDLIB_INTERNAL_H_ */
