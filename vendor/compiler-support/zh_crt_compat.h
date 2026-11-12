// ============================================================================
//  zh_crt_compat.h -- bridge between MinGW's C headers and MSVC's STL
//  Chinese++ section 18.52
//
//  WHY
//    vendor\mingw\math.h defines several C99 classification helpers as
//    FUNCTION-LIKE MACROS:
//
//        #define signbit(x)  ...
//        #define fpclassify(x) ...
//        #define isnan(x) / isinf(x) / isfinite(x) / isnormal(x) ...
//
//    MSVC's <cmath> re-exports them into namespace std with
//
//        _EXPORT_STD using _CSTD signbit;
//
//    and a `using ::signbit;` declaration cannot name a function-like macro,
//    so std::signbit never comes into existence. <complex> and <format> then
//    fail with "no matching function for call to 'signbit'".
//
//  FIX
//    This header is force-included (-include) ahead of everything else. It
//    pulls in the MinGW C header once, drops the macro spellings, and declares
//    real overloaded functions in the GLOBAL namespace. `using ::signbit;` then
//    resolves, and <complex>/<format> compile unchanged -- no edits to the
//    vendored MSVC STL and no new requirement on the machine (still no VS).
//
//  ASCII only.
// ============================================================================

#ifndef ZH_CRT_COMPAT_H
#define ZH_CRT_COMPAT_H

// 1) Let MinGW's headers declare their real functions (__signbit, __isnan, ...)
#include <math.h>

// 2) Drop the macro spellings that get in the way of `using ::name;`
#ifdef signbit
#undef signbit
#endif

// 3) Provide real `signbit` overloads in the global namespace, so that the
//    STL's `using ::signbit;` resolves. Only `signbit` is needed here: MSVC's
//    <cmath> has its own constexpr spellings for isnan/isinf/isfinite, and
//    declaring those here would collide with them.
extern "C" {
    int __cdecl __signbit(double);
    int __cdecl __signbitf(float);
    int __cdecl __signbitl(long double);
}

inline bool signbit(double _X) noexcept { return __signbit(_X) != 0; }
inline bool signbit(float _X) noexcept { return __signbitf(_X) != 0; }
inline bool signbit(long double _X) noexcept { return __signbitl(_X) != 0; }

#endif // ZH_CRT_COMPAT_H
