// ============================================================================
//  newdelete.cpp -- hand-written operator new / operator delete (18.48 batch 3)
//
//  WHY THIS FILE EXISTS
//    MEASURED with `dumpbin /exports`: `??2@YAPEAX_K@Z` (operator new) and
//    `??3@YAXPEAX_K@Z` (operator delete) are NOT exported by any runtime DLL we may
//    ship or that Windows provides (checked msvcp140, msvcp140_1/_2/_atomic_wait/
//    _codecvt_ids, vcruntime140, vcruntime140_1, concrt140, ucrtbase). They are code
//    inside Microsoft's msvcprt.lib, which may not be redistributed. This is our own
//    equivalent: a thin layer over ucrtbase's malloc/free (what the original is),
//    and it throws std::bad_alloc through the STL's own helper `std::_Xbad_alloc`,
//    which msvcp140.dll *does* export.
//
//  DELIBERATELY HEADER-FREE
//    MEASURED: including <new> here made the STL's <cstddef> emit
//    `using std::max_align_t;` at global scope while clang's own <stddef.h> had
//    already put max_align_t in the global namespace -> "using-declaration conflicts
//    with an existing declaration". Because the data-import macros
//    (_CRTIMP2_IMPORT / _CRTIMP2_PURE) that the STL's data declarations need are
//    defined in vendor\compiler-support\vcruntime.h, any TU that also pulls in
//    <cstddef> hits that conflict. This file therefore declares exactly what it
//    needs, so the definitions can be compiled while those macros are defined.
//
//  ASCII only.
// ============================================================================

extern "C" {
typedef unsigned long long zh_size_t;                     // same width as size_t here
__declspec(dllimport) void* __cdecl malloc(zh_size_t);
__declspec(dllimport) void  __cdecl free(void*);
}

namespace std {
struct nothrow_t;                                        // declared fully in <vcruntime_new.h>
extern "C++" __declspec(dllimport) void __cdecl _Xbad_alloc(void);   // msvcp140.dll export
}

void* __cdecl operator new(zh_size_t _Size) {
    void* _Ptr = malloc(_Size ? _Size : 1);
    if (!_Ptr) {
        std::_Xbad_alloc();
    }
    return _Ptr;
}

void* __cdecl operator new[](zh_size_t _Size) {
    return ::operator new(_Size);
}

void __cdecl operator delete(void* _Ptr) noexcept {
    free(_Ptr);
}

void __cdecl operator delete[](void* _Ptr) noexcept {
    free(_Ptr);
}

void __cdecl operator delete(void* _Ptr, zh_size_t) noexcept {
    free(_Ptr);
}

void __cdecl operator delete[](void* _Ptr, zh_size_t) noexcept {
    free(_Ptr);
}

void* __cdecl operator new(zh_size_t _Size, const std::nothrow_t&) noexcept {
    return malloc(_Size ? _Size : 1);
}

void* __cdecl operator new[](zh_size_t _Size, const std::nothrow_t&) noexcept {
    return malloc(_Size ? _Size : 1);
}

void __cdecl operator delete(void* _Ptr, const std::nothrow_t&) noexcept {
    free(_Ptr);
}

void __cdecl operator delete[](void* _Ptr, const std::nothrow_t&) noexcept {
    free(_Ptr);
}

// ---------------------------------------------------------------------------
//  Aligned allocation (__cpp_aligned_new). Missing in the first pass; surfaced
//  by <execution>:296, which calls
//      ::operator new(_Bytes, align_val_t{_Align}, nothrow)
//  Same reason as the unaligned ones: the definitions live in Microsoft's
//  static C++ runtime, which may not be redistributed.
//
//  align_val_t is passed by value and is size_t-wide, so declaring it here with
//  the same underlying type keeps the ABI identical. This file stays
//  header-free, so there is no other declaration to collide with.
// ---------------------------------------------------------------------------
extern "C" {
__declspec(dllimport) void* __cdecl _aligned_malloc(zh_size_t, zh_size_t);
__declspec(dllimport) void  __cdecl _aligned_free(void*);
}

namespace std {
enum class align_val_t : zh_size_t {};
}

static void* zh_aligned_alloc_or_throw(zh_size_t _Size, zh_size_t _Align) {
    void* _Ptr = _aligned_malloc(_Size ? _Size : 1, _Align);
    if (!_Ptr) {
        std::_Xbad_alloc();
    }
    return _Ptr;
}

void* __cdecl operator new(zh_size_t _Size, std::align_val_t _Align) {
    return zh_aligned_alloc_or_throw(_Size, (zh_size_t)_Align);
}

void* __cdecl operator new[](zh_size_t _Size, std::align_val_t _Align) {
    return zh_aligned_alloc_or_throw(_Size, (zh_size_t)_Align);
}

void __cdecl operator delete(void* _Ptr, std::align_val_t) noexcept {
    if (_Ptr) {
        _aligned_free(_Ptr);
    }
}

void __cdecl operator delete[](void* _Ptr, std::align_val_t) noexcept {
    if (_Ptr) {
        _aligned_free(_Ptr);
    }
}

void __cdecl operator delete(void* _Ptr, zh_size_t, std::align_val_t) noexcept {
    if (_Ptr) {
        _aligned_free(_Ptr);
    }
}

void __cdecl operator delete[](void* _Ptr, zh_size_t, std::align_val_t) noexcept {
    if (_Ptr) {
        _aligned_free(_Ptr);
    }
}

void* __cdecl operator new(zh_size_t _Size, std::align_val_t _Align, const std::nothrow_t&) noexcept {
    return _aligned_malloc(_Size ? _Size : 1, (zh_size_t)_Align);
}

void* __cdecl operator new[](zh_size_t _Size, std::align_val_t _Align, const std::nothrow_t&) noexcept {
    return _aligned_malloc(_Size ? _Size : 1, (zh_size_t)_Align);
}

void __cdecl operator delete(void* _Ptr, std::align_val_t, const std::nothrow_t&) noexcept {
    if (_Ptr) {
        _aligned_free(_Ptr);
    }
}

void __cdecl operator delete[](void* _Ptr, std::align_val_t, const std::nothrow_t&) noexcept {
    if (_Ptr) {
        _aligned_free(_Ptr);
    }
}