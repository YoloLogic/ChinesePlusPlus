// ============================================================================
//  vcruntime.h -- hand-written, MSVC-compatible compiler support header
//  Chinese++ section 18.48, batch 2 ("what cannot be copied is imitated by hand")
//
//  WHY THIS FILE EXISTS
//    The MSVC STL headers include <vcruntime.h>. That file belongs to the MSVC
//    toolset (closed source, no SPDX licence line), so we may not ship it. This is
//    OUR OWN text implementing the same *interface*: macros only. No code lives
//    here -- the code is in vcruntime140.dll (shipped with this package) and in
//    ucrtbase.dll (part of Windows since Windows 10).
//
//  MEASURED SURFACE (2026-10-06, over the 173 vendored MSVC STL headers):
//    _CRTIMP 172 uses, _CRT_GUARDOVERFLOW 72, _CRT_SATELLITE_2 44, _ACRTIMP 11,
//    _CRT_BLOCK 8, _CRT_SATELLITE_1 7, _CRT_MSVCP_CURRENT 7, _CRT_WIDE 6,
//    __vcrt_* : ZERO uses. So nothing has to be declared here.
//
//  ASCII ONLY on purpose: this file ships inside the package and is read by both
//  clang and (potentially) MSVC, whose default source charset is the ANSI code page.
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_H
#define _VCRUNTIME_H

// --- the pieces that are legitimately free / already ours -------------------
//  sal.h        : annotation macros (mingw-w64, public domain) -- they expand to
//                 nothing meaningful for us, exactly like the /analyze-off case.
//  vadefs.h     : va_list plumbing (clang's own builtin header).
//  stddef.h     : size_t / ptrdiff_t (clang's own).
//  stdint.h     : uintptr_t and friends (clang's own).
#include <sal.h>
#include <vadefs.h>
#include <stddef.h>
#include <stdint.h>

// --- packing ---------------------------------------------------------------
//  MSVC STL writes `#pragma pack(push, _CRT_PACKING)`. mingw-w64's corecrt.h
//  already defines it as 8; define it only if nobody did (defensive).
#ifndef _CRT_PACKING
#define _CRT_PACKING 8
#endif

// --- calling convention / linkage -----------------------------------------
//  The CRT lives in DLLs (ucrtbase.dll, vcruntime140.dll, msvcp140.dll), so the
//  declarations are dllimport. The SAL-style prefixes are no-ops.
#ifndef _CRTIMP
#define _CRTIMP __declspec(dllimport)
#endif
#ifndef _ACRTIMP
#define _ACRTIMP __declspec(dllimport)
#endif
#ifndef _VCRTIMP
#define _VCRTIMP __declspec(dllimport)
#endif
#ifndef __CRTDECL
#define __CRTDECL __cdecl
#endif

// --- SAL-ish prefixes used by the STL -------------------------------------
//  These annotate parameters for static analysis only; with analysis off they
//  must expand to nothing, which is what the shipped MSVC headers do too.
#define _CRT_GUARDOVERFLOW
#define _CRT_SATELLITE_1
#define _CRT_SATELLITE_2
//  MEASURED: <xlocale> uses _CRT_SATELLITE_CODECVT_IDS_NOIMPORT (codecvt ids live in
//  msvcp140_codecvt_ids.dll, which we ship); the macro only controls import spelling.
#ifndef _CRT_SATELLITE_CODECVT_IDS
#define _CRT_SATELLITE_CODECVT_IDS
#endif
#ifndef _CRT_SATELLITE_CODECVT_IDS_NOIMPORT
#define _CRT_SATELLITE_CODECVT_IDS_NOIMPORT
#endif
#ifndef _CRT_SATELLITE_CODECVT_IDS_IMPORT
#define _CRT_SATELLITE_CODECVT_IDS_IMPORT
#endif
#define _CRT_BLOCK
#define _CRT_SECURE_CPP_NOTHROW noexcept

//  Measured (batch 2 judge TU): MSVC STL uses _NODISCARD in 100+ places and
//  mingw-w64's sal.h does not define it, so we do. The rest are defensive
//  fallbacks for the same family -- if mingw's sal.h already defined them, these
//  #ifndef guards leave its definitions alone.
#ifndef _NODISCARD
#define _NODISCARD [[nodiscard]]
#endif
#ifndef _CONST_RETURN
#define _CONST_RETURN
#endif
#ifndef _Check_return_
#define _Check_return_
#endif
#ifndef _Ret_maybenull_
#define _Ret_maybenull_
#endif
#ifndef _Ret_notnull_
#define _Ret_notnull_
#endif
#ifndef _Post_writable_byte_size_
#define _Post_writable_byte_size_(x)
#endif
//  Some MSVC-flavoured headers bracket their C declarations with these two.
//  mingw-w64's corecrt.h does not define them; define them as no-ops so that any
//  header written for the MSVC world still parses.
#ifndef _CRT_BEGIN_C_HEADER
#define _CRT_BEGIN_C_HEADER extern "C" {
#define _CRT_END_C_HEADER }
#endif

// --- language-mode switches the STL reads on every other line --------------
//  MEASURED: after `#include <vector>` nothing had defined _HAS_CXX17, yet the STL
//  uses it 1391x (_HAS_CXX20), 647x (_HAS_CXX23), 535x (_HAS_CXX17). Microsoft
//  defines them here, from the language level the compiler reports. Without them
//  the STL headers fail with "use of undeclared identifier '_HAS_CXX17'".
#ifdef _MSVC_LANG
#define _ChinesePP_LANG _MSVC_LANG
#else
#define _ChinesePP_LANG __cplusplus
#endif
#ifndef _HAS_CXX14
#define _HAS_CXX14 (_ChinesePP_LANG > 201402L)
#endif
#ifndef _HAS_CXX17
#define _HAS_CXX17 (_ChinesePP_LANG > 201402L)
#endif
#ifndef _HAS_CXX20
#define _HAS_CXX20 (_ChinesePP_LANG > 201703L)
#endif
#ifndef _HAS_CXX23
#define _HAS_CXX23 (_ChinesePP_LANG > 202002L)
#endif

// --- MSVC-flavoured qualifier macros the STL uses -------------------------
//  MEASURED over the vendored STL: _MSVC_CONSTEXPR, _MSVC_LIFETIMEBOUND,
//  _MSVC_INTRINSIC, _MSVC_KNOWN_SEMANTICS, _MSVC_WARNING_LEVEL, _MSVC_NOOP_DTOR.
//  Microsoft defines them here. With the default (non-analyzed, non-hardened)
//  settings they are trivial: a qualifier or nothing at all.
#ifndef _MSVC_CONSTEXPR
//  MEASURED: must be EMPTY. The STL writes _MSVC_CONSTEXPR return ...; inside a
//  function body (xutility:463, memory:544), where constexpr would be a syntax error.
#define _MSVC_CONSTEXPR
#endif
#ifndef _MSVC_LIFETIMEBOUND
#define _MSVC_LIFETIMEBOUND
#endif
#ifndef _MSVC_INTRINSIC
#define _MSVC_INTRINSIC
#endif
#ifndef _MSVC_KNOWN_SEMANTICS
#define _MSVC_KNOWN_SEMANTICS
#endif
//  NOTE (measured): _MSVC_WARNING_LEVEL must NOT be defined here. The STL does
//  `#if defined(_MSVC_WARNING_LEVEL) && _MSVC_WARNING_LEVEL >= 4`, so defining it
//  empty yields "invalid token at the start of a preprocessor expression"
//  (yvals_core.h:537). Microsoft's compiler only defines it when /W4 is given.
#ifndef _MSVC_NOOP_DTOR
#define _MSVC_NOOP_DTOR
#endif
#ifndef _MSVC_EXECUTION_CHARACTER_SET
#define _MSVC_EXECUTION_CHARACTER_SET 65001   /* UTF-8, the charset we compile with */
#endif

// --- calling-convention macros the STL relies on --------------------------
//  MEASURED over the 173 vendored STL headers: __CLR_OR_THIS_CALL x774,
//  __CLRCALL_PURE_OR_CDECL x90, __CLRCALL_OR_CDECL x75, __CLRCALL_PURE_OR_STDCALL x5.
//  Microsoft defines them in this header to switch between the CLR flavours and
//  the plain ones. We have no CLR, so they mean exactly what the plain spelling
//  means -- which is also what MSVC does when /clr is off.
#ifndef __CLRCALL_OR_CDECL
#define __CLRCALL_OR_CDECL __cdecl
#endif
#ifndef __CLRCALL_PURE_OR_CDECL
#define __CLRCALL_PURE_OR_CDECL __cdecl
#endif
#ifndef __CLRCALL_PURE_OR_STDCALL
#define __CLRCALL_PURE_OR_STDCALL __stdcall
#endif
#ifndef __CLR_OR_THIS_CALL
#define __CLR_OR_THIS_CALL
#endif

// --- stringizing helpers used by STL headers -------------------------------
#ifndef _CRT_STRINGIZE_
#define _CRT_STRINGIZE_(x) #x
#endif
#ifndef _CRT_STRINGIZE
#define _CRT_STRINGIZE(x) _CRT_STRINGIZE_(x)
#endif

// --- string literals ------------------------------------------------------
//  _CRT_WIDE("x") widens a narrow literal; _CRT_MSVCP_CURRENT is the name of the
//  C++ runtime DLL the STL talks to (used for error reporting only).
#ifndef _CRT_WIDE
#define _CRT_WIDE_(s) L##s
#define _CRT_WIDE(s) _CRT_WIDE_(s)
#endif
#ifndef _CRT_MSVCP_CURRENT
#define _CRT_MSVCP_CURRENT "msvcp140.dll"
#endif

// --- compiler feature switches the MSVC world expects ---------------------
#ifndef _CRT_USE_BUILTIN_OFFSETOF
#define _CRT_USE_BUILTIN_OFFSETOF
#endif
#ifndef _HAS_MSVC_STL
#define _HAS_MSVC_STL 1
#endif

#endif // _VCRUNTIME_H

// --- SAL annotation macros the STL uses that mingw's sal.h lacks -----------
//  Added ONE BY ONE, driven by the compiler's own error messages (a bulk sweep was
//  tried first and was WRONG: identifiers such as _Count_ / _File_ / _do_ also match
//  the SAL shape but are real names in some STL headers, so emptying them broke
//  <xmemory>). SAL is analysis-only => the correct expansion is empty.
#ifndef _Deref_post_opt_valid_
#define _Deref_post_opt_valid_
#endif