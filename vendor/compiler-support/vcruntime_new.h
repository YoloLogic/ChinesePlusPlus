// ============================================================================
//  vcruntime_new.h -- hand-written, MSVC-ABI compatible (Chinese++ 18.48 batch 2)
//
//  WHAT THE STL NEEDS FROM IT (measured): <new> and <concepts> include it, and
//  expect (a) std::nothrow_t / std::nothrow, (b) the GLOBAL operator new/delete
//  overloads that the C++ runtime DLL implements. We declare them; we implement
//  nothing. The actual code is in msvcp140.dll / vcruntime140.dll (shipped).
//
//  ASCII only (this file is read by clang and possibly by MSVC, whose default
//  source charset is the ANSI code page).
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_NEW_H
#define _VCRUNTIME_NEW_H

#include <vcruntime.h>
#include <stddef.h>

#ifdef __cpp_aligned_new
namespace std {
    enum class align_val_t : size_t {};
}
#endif // __cpp_aligned_new
#ifndef __NOTHROW_T_DEFINED
#define __NOTHROW_T_DEFINED
extern "C++" {
namespace std {
    struct nothrow_t {
        explicit nothrow_t() = default;
    };
    extern const nothrow_t nothrow;
}
}
#endif // __NOTHROW_T_DEFINED

extern "C++" {

// --- throwing forms (declared, implemented in the C++ runtime DLL) ---------
void* __cdecl operator new(size_t _Size);
void* __cdecl operator new[](size_t _Size);
void  __cdecl operator delete(void* _Block) noexcept;
void  __cdecl operator delete[](void* _Block) noexcept;
void  __cdecl operator delete(void* _Block, size_t _Size) noexcept;
void  __cdecl operator delete[](void* _Block, size_t _Size) noexcept;

// --- nothrow forms --------------------------------------------------------
void* __cdecl operator new(size_t _Size, const std::nothrow_t&) noexcept;
void* __cdecl operator new[](size_t _Size, const std::nothrow_t&) noexcept;
void  __cdecl operator delete(void* _Block, const std::nothrow_t&) noexcept;
void  __cdecl operator delete[](void* _Block, const std::nothrow_t&) noexcept;
#ifdef __cpp_aligned_new
//  Aligned overloads (__cpp_aligned_new). MISSING in the first pass: <execution>
//  line 296 calls `::operator new(_Bytes, align_val_t{_Align}, nothrow)` and the
//  overload set was empty, so overload resolution failed at COMPILE time.
//  Definitions live in vendor\crt\newdelete.cpp.
void* __cdecl operator new(size_t _Size, ::std::align_val_t _Al);
void* __cdecl operator new(size_t _Size, ::std::align_val_t _Al, ::std::nothrow_t const&) noexcept;
void* __cdecl operator new[](size_t _Size, ::std::align_val_t _Al);
void* __cdecl operator new[](size_t _Size, ::std::align_val_t _Al, ::std::nothrow_t const&) noexcept;

void __cdecl operator delete(void* _Block, ::std::align_val_t _Al) noexcept;
void __cdecl operator delete(void* _Block, ::std::align_val_t _Al, ::std::nothrow_t const&) noexcept;
void __cdecl operator delete[](void* _Block, ::std::align_val_t _Al) noexcept;
void __cdecl operator delete[](void* _Block, ::std::align_val_t _Al, ::std::nothrow_t const&) noexcept;

void __cdecl operator delete(void* _Block, size_t _Size, ::std::align_val_t _Al) noexcept;
void __cdecl operator delete[](void* _Block, size_t _Size, ::std::align_val_t _Al) noexcept;
#endif // __cpp_aligned_new

// --- placement forms ------------------------------------------------------
//  MEASURED: <xutility> (pulled in by <vector>) uses a placement new expression
//  without including <new>, and clang then says "no matching operator new ...
//  include <new>". In the MSVC world these inline forms carry the very guards
//  below, so whichever header comes first defines them and the other stays quiet.
#ifndef __PLACEMENT_NEW_INLINE
#define __PLACEMENT_NEW_INLINE
inline void* __cdecl operator new(size_t, void* _Where) noexcept {
    return _Where;
}
inline void __cdecl operator delete(void*, void*) noexcept {
}
#endif // __PLACEMENT_NEW_INLINE

#ifndef __PLACEMENT_VEC_NEW_INLINE
#define __PLACEMENT_VEC_NEW_INLINE
inline void* __cdecl operator new[](size_t, void* _Where) noexcept {
    return _Where;
}
inline void __cdecl operator delete[](void*, void*) noexcept {
}
#endif // __PLACEMENT_VEC_NEW_INLINE

} // extern "C++"

#endif // _VCRUNTIME_NEW_H
