// ============================================================================
//  stdio.h -- shim that adds the one piece MSVC STL needs (18.48 batch 2)
//
//  WHY: MSVC STL's <cstdio> does `using ::_Mbstatet;` at line 33. In the MSVC world
//  `_Mbstatet` is declared by Microsoft's own stdio.h; mingw-w64 declares it in
//  wchar.h instead (under `_UCRT`). MEASURED (first attempt): defining the struct
//  here and guarding wchar.h made wchar.h take its "#else" branch and typedef
//  mbstate_t as int -> conflict. The simple, correct fix is to pull wchar.h in
//  first: it declares both _Mbstatet and mbstate_t exactly once.
//
//  ASCII only.
// ============================================================================
#ifndef _INC_STDIO
#include_next <stdio.h>
#endif
#include <wchar.h>

// ----------------------------------------------------------------------------
//  `_get_stream_buffer_pointers` -- declared by the WINDOWS SDK but NOT by
//  mingw-w64's stdio.h (measured 2026-10-06).
//
//  WHY IT MATTERS: MSVC STL's <__msvc_filebuf.hpp> calls it (line 693) when
//  <fstream> builds its buffer, so without the declaration ANY use of <fstream>
//  fails in bundled mode with
//      error: no member named '_get_stream_buffer_pointers' in the global namespace
//  (found by build\_review_own\batch5diag\stl_smoke.cpp, which deliberately
//   pulls in a wide slice of the standard library).
//
//  Only the DECLARATION is missing: ucrtbase.dll exports the symbol, and it is
//  already in our ship-with import libraries (ucrt.lib / ucrtbase.lib), both
//  measured. `errno_t` is `int`; the SDK spells the return type that way.
//
//  ⚠ Do NOT spell the return type with `_ACRTIMP` here: MEASURED 2026-10-06 --
//    a plain C translation unit that includes only <stdio.h> does not have that
//    macro defined, and the file then dies with
//        error: unknown type name '_ACRTIMP'
//    (the C case of build\_review_own\batch4_judge.ps1 caught it). A bare
//    declaration is enough: the import library supplies the thunk.
//
//  ASCII only.
// ----------------------------------------------------------------------------
#ifndef _ZH_HAVE_GET_STREAM_BUFFER_POINTERS
#define _ZH_HAVE_GET_STREAM_BUFFER_POINTERS
#ifdef __cplusplus
extern "C" {
#endif
int __cdecl _get_stream_buffer_pointers(FILE* _Stream, char*** _Base, char*** _Pointer, int** _Count);
#ifdef __cplusplus
}
#endif
#endif
