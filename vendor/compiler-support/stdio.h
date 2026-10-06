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
