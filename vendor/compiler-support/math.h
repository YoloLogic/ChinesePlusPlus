// ============================================================================
//  math.h -- shim that keeps the C99 classification macros out of C++ (18.48 b2)
//
//  WHY (measured): mingw-w64's math.h defines the type-generic C99 macros
//      #define isfinite(x) ((fpclassify(x) & FP_NAN) == 0)   ... and friends.
//  MSVC STL's <cmath> has a clang-only block that uses those names as FUNCTIONS:
//      #define _CLANG_BUILTIN1(NAME) _CLANG_BUILTIN1_ARG(NAME, float) ...
//      _CLANG_BUILTIN1(isfinite)
//  so the function-like macro swallows the generated declaration and the compiler
//  reports "missing ')'" at cmath:672 (and a cascade of nonsense).
//  Microsoft's own math.h does not expose these macros to C++ either -- MSVC STL's
//  <cmath> provides proper overloads -- so we drop them for C++ only.
//
//  ASCII only.
// ============================================================================
#ifndef _INC_MATH
#include_next <math.h>
#endif

#if defined(__cplusplus)
#undef fpclassify
#undef isfinite
#undef isinf
#undef isnan
#undef isnormal
#undef signbit
#undef isgreater
#undef isgreaterequal
#undef isless
#undef islessequal
#undef islessgreater
#undef isunordered
#endif
