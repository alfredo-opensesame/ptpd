#ifndef PTP_PRIMITIVES_H_
#define PTP_PRIMITIVES_H_

/* On iOS/macOS, Boolean is already defined in MacTypes.h */
#if !defined(__APPLE__) || !defined(PTPD_IOS)
typedef enum {FALSE=0, TRUE} Boolean;
#else
/* Use the system Boolean from MacTypes.h, but ensure TRUE/FALSE are defined */
#include <MacTypes.h>
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif
#endif

typedef char Octet;
typedef int8_t Integer8;
typedef int16_t Integer16;
typedef int32_t Integer32;
typedef uint8_t  UInteger8;
typedef uint16_t UInteger16;
typedef uint32_t UInteger32;
typedef uint16_t Enumeration16;
typedef unsigned char Enumeration8;
typedef unsigned char Enumeration4;
typedef unsigned char Enumeration4Upper;
typedef unsigned char Enumeration4Lower;
typedef unsigned char UInteger4;
typedef unsigned char UInteger4Upper;
typedef unsigned char UInteger4Lower;
typedef unsigned char Nibble;
typedef unsigned char NibbleUpper;
typedef unsigned char NibbleLower;

/**
* \brief Implementation specific of UInteger48 type
 */
typedef struct {
	uint32_t lsb;
	uint16_t msb;
} UInteger48;

/**
* \brief Implementation specific of Integer64 type
 */
typedef struct {
	uint32_t lsb;
	int32_t msb;
} Integer64;

#endif /*PTP_PRIMITIVES_H_*/
