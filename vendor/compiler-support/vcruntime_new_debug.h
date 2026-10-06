// ============================================================================
//  vcruntime_new_debug.h -- hand-written shim (18.48 batch 2)
//
//  MEASURED: no header of the 173 vendored MSVC STL headers includes this file.
//  In the MSVC world it declares the debug-heap operator new/delete overloads
//  (the ones taking __FILE__/__LINE__) that the debug CRT implements. We ship the
//  RELEASE runtime, so there is nothing to declare against: including this header
//  is legal and a no-op, exactly like building with NDEBUG but asking for it.
//
//  ASCII only.
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_NEW_DEBUG_H
#define _VCRUNTIME_NEW_DEBUG_H

#include <vcruntime.h>
#include <vcruntime_new.h>

#endif // _VCRUNTIME_NEW_DEBUG_H
