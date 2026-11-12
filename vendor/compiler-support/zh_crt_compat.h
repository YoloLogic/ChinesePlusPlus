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


// ---------------------------------------------------------------------------
//  setjmp: lib/stl/csetjmp:23 does `using ::setjmp;`, but vendor\mingw\setjmp.h
//  defines it as a function-like macro:  #define setjmp(BUF) _setjmp3((BUF), NULL)
//  A using-declaration cannot name a macro. Drop the macro and expose a real
//  function (defined in vendor\crt\runtime-extra.cpp, forwarding to _setjmp).
//    MEASURED (llvm-readobj --coff-exports): ucrtbase.dll / vcruntime140.dll /
//    msvcrt.dll export _setjmp and _setjmpex, but NOT _setjmp3 -- the earlier
//    attempt forwarding to _setjmp3 therefore broke every link.
// ---------------------------------------------------------------------------
#include <setjmp.h>
#ifdef setjmp
#undef setjmp
#endif
extern "C" int __cdecl setjmp(jmp_buf) noexcept;
#endif // ZH_CRT_COMPAT_H
