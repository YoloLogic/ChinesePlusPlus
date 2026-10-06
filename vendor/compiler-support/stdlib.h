// ============================================================================
//  stdlib.h -- shim that declares the CRT internals + C++ overloads MSVC STL
//  expects (Chinese++ 18.48 batch 2)
//
//  WHY (measured, two separate gaps):
//   1. MSVC STL's <exception> calls the CRT internal `_invoke_watson` (the invalid
//      parameter handler) and expects Microsoft's stdlib.h to have declared it.
//      mingw-w64's stdlib.h does not. The symbol is exported by ucrtbase.dll.
//   2. MSVC STL's <xlocnum> calls `_STD abs(...)` on a non-int argument. The UCRT's
//      stdlib.h declares `abs`/`labs`/`llabs` AND, for C++, inline `abs(long)` /
//      `abs(long long)` overloads; mingw-w64's stdlib.h only has `int abs(int)`,
//      so overload resolution against std::abs(double) becomes ambiguous
//      (measured: "call to 'abs' is ambiguous" at xlocnum:1058).
//
//  ASCII only.
// ============================================================================
#ifndef _INC_STDLIB
#include_next <stdlib.h>
#endif

#include <vcruntime.h>

#ifndef _ChinesePP_INVOKE_WATSON_DECLARED
#define _ChinesePP_INVOKE_WATSON_DECLARED
extern "C" {
// Microsoft's spelling: (expression, function, file, line, reserved)
_ACRTIMP void __cdecl _invoke_watson(
    const wchar_t* _Expression,
    const wchar_t* _FunctionName,
    const wchar_t* _FileName,
    unsigned int   _LineNo,
    uintptr_t      _Reserved);
}
#endif

#if defined(__cplusplus) && !defined(_ChinesePP_ABS_OVERLOADS)
#define _ChinesePP_ABS_OVERLOADS
extern "C++" {
// Same trick the UCRT uses (its stdlib.h lines 360-372): make the long / long long
// forms visible in C++ so `abs` is never ambiguous against the floating overloads.
inline long abs(long const _X) noexcept {
    return _X < 0 ? -_X : _X;
}
inline long long abs(long long const _X) noexcept {
    return _X < 0 ? -_X : _X;
}
}
#endif
