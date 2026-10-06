// ============================================================================
//  stdint.h -- hand-written, MSVC-compatible (Chinese++ 18.48 batch 2)
//
//  WHY WE MUST WRITE THIS OURSELVES
//    clang's own <stdint.h> is a *forwarding shell*: on a Microsoft target it does
//    `#include_next <stdint.h>` because Microsoft's stdint.h is the authority. That
//    file belongs to the MSVC toolset (closed source) so we may not ship it. We
//    first tried mingw-w64's stdint.h instead, and MEASURED that it breaks clang's
//    intrinsic headers (with mingw's stdint.h in front, clang's mmintrin.h fails at
//    line 83: "functional cast to a builtin type takes only one argument") -- so the
//    real fix is to provide the header clang's shell was written to find.
//
//  HOW: every type and limit comes from clang's own predefined macros
//  (__INT8_TYPE__, __UINT64_MAX__, ...), which is exactly what Microsoft's header
//  does for the MSVC compiler. Nothing is implemented here; these are types.
//
//  ASCII only.
// ============================================================================
#ifndef _STDINT_H
#define _STDINT_H

// --- exact-width integers ---------------------------------------------------
typedef __INT8_TYPE__   int8_t;
typedef __INT16_TYPE__  int16_t;
typedef __INT32_TYPE__  int32_t;
typedef __INT64_TYPE__  int64_t;
typedef __UINT8_TYPE__  uint8_t;
typedef __UINT16_TYPE__ uint16_t;
typedef __UINT32_TYPE__ uint32_t;
typedef __UINT64_TYPE__ uint64_t;

// --- least / fast variants (MSVC aliases them to the exact types) -----------
typedef int8_t   int_least8_t;
typedef int16_t  int_least16_t;
typedef int32_t  int_least32_t;
typedef int64_t  int_least64_t;
typedef uint8_t  uint_least8_t;
typedef uint16_t uint_least16_t;
typedef uint32_t uint_least32_t;
typedef uint64_t uint_least64_t;

typedef int8_t   int_fast8_t;
typedef int16_t  int_fast16_t;
typedef int32_t  int_fast32_t;
typedef int64_t  int_fast64_t;
typedef uint8_t  uint_fast8_t;
typedef uint16_t uint_fast16_t;
typedef uint32_t uint_fast32_t;
typedef uint64_t uint_fast64_t;

// --- pointer-sized, widest --------------------------------------------------
typedef __INTPTR_TYPE__  intptr_t;
typedef __UINTPTR_TYPE__ uintptr_t;
typedef __INTMAX_TYPE__  intmax_t;
typedef __UINTMAX_TYPE__ uintmax_t;

// --- limits -----------------------------------------------------------------
#define INT8_MIN    (-127 - 1)
#define INT16_MIN   (-32767 - 1)
#define INT32_MIN   (-2147483647 - 1)
#define INT64_MIN   (-9223372036854775807LL - 1)
#define INT8_MAX    127
#define INT16_MAX   32767
#define INT32_MAX   2147483647
#define INT64_MAX   9223372036854775807LL
#define UINT8_MAX   0xffU
#define UINT16_MAX  0xffffU
#define UINT32_MAX  0xffffffffU
#define UINT64_MAX  0xffffffffffffffffULL

#define INT_LEAST8_MIN   INT8_MIN
#define INT_LEAST16_MIN  INT16_MIN
#define INT_LEAST32_MIN  INT32_MIN
#define INT_LEAST64_MIN  INT64_MIN
#define INT_LEAST8_MAX   INT8_MAX
#define INT_LEAST16_MAX  INT16_MAX
#define INT_LEAST32_MAX  INT32_MAX
#define INT_LEAST64_MAX  INT64_MAX
#define UINT_LEAST8_MAX  UINT8_MAX
#define UINT_LEAST16_MAX UINT16_MAX
#define UINT_LEAST32_MAX UINT32_MAX
#define UINT_LEAST64_MAX UINT64_MAX

#define INT_FAST8_MIN    INT8_MIN
#define INT_FAST16_MIN   INT16_MIN
#define INT_FAST32_MIN   INT32_MIN
#define INT_FAST64_MIN   INT64_MIN
#define INT_FAST8_MAX    INT8_MAX
#define INT_FAST16_MAX   INT16_MAX
#define INT_FAST32_MAX   INT32_MAX
#define INT_FAST64_MAX   INT64_MAX
#define UINT_FAST8_MAX   UINT8_MAX
#define UINT_FAST16_MAX  UINT16_MAX
#define UINT_FAST32_MAX  UINT32_MAX
#define UINT_FAST64_MAX  UINT64_MAX

#define INTPTR_MIN   (-9223372036854775807LL - 1)
#define INTPTR_MAX   9223372036854775807LL
#define UINTPTR_MAX  0xffffffffffffffffULL
#define INTMAX_MIN   (-9223372036854775807LL - 1)
#define INTMAX_MAX   9223372036854775807LL
#define UINTMAX_MAX  0xffffffffffffffffULL
#define PTRDIFF_MIN  (-9223372036854775807LL - 1)
#define PTRDIFF_MAX  9223372036854775807LL
#define SIZE_MAX     0xffffffffffffffffULL

// --- constant-forming macros ------------------------------------------------
#define INT8_C(x)    (x)
#define INT16_C(x)   (x)
#define INT32_C(x)   (x)
#define INT64_C(x)   (x##LL)
#define UINT8_C(x)   (x)
#define UINT16_C(x)  (x)
#define UINT32_C(x)  (x##U)
#define UINT64_C(x)  (x##ULL)
#define INTMAX_C(x)  (x##LL)
#define UINTMAX_C(x) (x##ULL)

// --- wide-character / other limits the C standard puts here ----------------
#ifndef WCHAR_MIN
#define WCHAR_MIN 0
#endif
#ifndef WCHAR_MAX
#define WCHAR_MAX 0xffff
#endif
#ifndef WINT_MIN
#define WINT_MIN 0
#endif
#ifndef WINT_MAX
#define WINT_MAX 0xffff
#endif
#ifndef SIG_ATOMIC_MIN
#define SIG_ATOMIC_MIN INT32_MIN
#endif
#ifndef SIG_ATOMIC_MAX
#define SIG_ATOMIC_MAX INT32_MAX
#endif

// MSVC's header also defines these guards so that other headers stay quiet.
#ifndef _SIZE_T_DEFINED
#define _SIZE_T_DEFINED
#endif
#ifndef _INTPTR_T_DEFINED
#define _INTPTR_T_DEFINED
#endif
#ifndef _UINTPTR_T_DEFINED
#define _UINTPTR_T_DEFINED
#endif

#endif // _STDINT_H
