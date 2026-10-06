// ============================================================================
//  vcruntime_string.h -- hand-written shim (18.48 batch 2)
//
//  MEASURED: no header of the 173 vendored MSVC STL headers includes this file.
//  It exists so that user code which includes it explicitly still compiles. In the
//  MSVC world it re-declares the mem*/str*/wc* family with the runtime DLL import
//  decoration; the same declarations already come from <string.h> and <wchar.h>
//  (mingw-w64's UCRT headers in bundled mode, the SDK's in system mode), so this
//  shim simply forwards to them instead of keeping a second copy that could drift.
//
//  ASCII only.
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_STRING_H
#define _VCRUNTIME_STRING_H

#include <vcruntime.h>
#include <string.h>
#include <wchar.h>

#endif // _VCRUNTIME_STRING_H
