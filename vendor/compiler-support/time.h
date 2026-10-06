// ============================================================================
//  time.h -- shim that adds the C11 entry points MSVC STL expects (18.48 b2)
//
//  MEASURED: MSVC STL's <ctime> does `using ::timespec_get;` and mingw-w64's
//  time.h does not declare it for our configuration, so the STL header fails with
//  "the global namespace has no member 'timespec_get'". The function is exported by
//  ucrtbase.dll (a Windows component) -- a declaration is all that is needed.
//
//  ASCII only.
// ============================================================================
#ifndef _INC_TIME
#include_next <time.h>
#endif

#include <vcruntime.h>

#if defined(__cplusplus) && !defined(_ChinesePP_TIMESPEC_GET_DECLARED)
#define _ChinesePP_TIMESPEC_GET_DECLARED
extern "C" {
// C11 7.27.2.5: fills *ts for the given base, returns base on success, 0 on failure.
_ACRTIMP int __cdecl timespec_get(struct timespec* _Ts, int _Base);
}
#endif
