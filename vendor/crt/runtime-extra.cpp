// ============================================================================
//  runtime-extra.cpp -- the remaining "only inside Microsoft static CRT" holes
//  Chinese++ section 18.50
//
//  WHY
//    A wide-angle link test (119 zhstdlib headers + the 4 link probes) showed
//    these symbols referenced by the STL headers but DEFINED only inside
//    Microsoft's static C++ runtime (msvcprt.lib / libcpmt.lib / libcmt.lib),
//    which may not be redistributed. MEASURED with llvm-readobj --coff-exports:
//    none of them is exported by msvcp140.dll / vcruntime140.dll:
//
//      __std_fs_remove                        <- <filesystem>      (xfilesystem_abi.h:359)
//      __std_system_error_allocate_message    <- <system_error>    (__msvc_system_error_abi.hpp:26)
//      __std_system_error_deallocate_message  <- <system_error>    (same header:28)
//      __std_calloc_crt                       <- <chrono> tzdb     (__msvc_tzdb.hpp:92)
//      _Aligned_get_default_resource          <- <memory_resource> (xpolymorphic_allocator.h:168)
//
//    This file is our own implementation of the same contracts.
//
//  DELIBERATELY HEADER-FREE (same reason as stl-internals.cpp / newdelete.cpp:
//  including <cstddef> pulls in declarations that conflict with the data-import
//  macros the STL's declarations need). Everything below is spelled with the
//  layout / calling convention the headers guarantee.
//
//  ASCII only.
// ============================================================================

typedef unsigned long  zh_ulong;
typedef unsigned int   zh_uint;
typedef __SIZE_TYPE__  zh_size_t;
typedef wchar_t        zh_wchar_t;

// ---------------------------------------------------------------------------
//  Win32 entry points we need. Declared here instead of pulling in <windows.h>.
// ---------------------------------------------------------------------------
extern "C" {
    __declspec(dllimport) int  __stdcall DeleteFileW(const zh_wchar_t* _Path);
    __declspec(dllimport) int  __stdcall RemoveDirectoryW(const zh_wchar_t* _Path);
    __declspec(dllimport) zh_ulong __stdcall GetLastError(void);
    __declspec(dllimport) zh_ulong __stdcall FormatMessageA(
        zh_ulong _Flags, const void* _Source, zh_ulong _MessageId, zh_ulong _LanguageId,
        char* _Buffer, zh_ulong _Size, void* _Arguments);
    __declspec(dllimport) void* __cdecl malloc(zh_size_t _Size);
    __declspec(dllimport) void  __cdecl free(void* _Ptr);
    __declspec(dllimport) void* __cdecl calloc(zh_size_t _Count, zh_size_t _Size);
    __declspec(dllimport) void* __cdecl _aligned_malloc(zh_size_t _Size, zh_size_t _Align);
    __declspec(dllimport) void  __cdecl _aligned_free(void* _Ptr);
}

// ---------------------------------------------------------------------------
//  1) <filesystem>: xfilesystem_abi.h:354-359
//
//     enum class __std_win_error : unsigned long { ... };
//     struct __std_fs_remove_result { bool _Removed; __std_win_error _Error; };
//     _NODISCARD extern "C" __std_fs_remove_result __stdcall __std_fs_remove(const wchar_t*) noexcept;
//
//  Semantics: remove a FILE. std::filesystem::remove also accepts an empty
//  directory, so try RemoveDirectoryW when DeleteFileW fails.
// ---------------------------------------------------------------------------
enum class __std_win_error : unsigned long {
    _Success = 0,
};

struct __std_fs_remove_result {
    bool _Removed;
    __std_win_error _Error;
};

static __std_fs_remove_result zh_make_result(bool removed, zh_ulong err) {
    __std_fs_remove_result r;
    r._Removed = removed;
    r._Error   = static_cast<__std_win_error>(removed ? 0UL : err);
    return r;
}

extern "C" __std_fs_remove_result __stdcall __std_fs_remove(const zh_wchar_t* _Target) noexcept {
    if (_Target == nullptr) {
        return zh_make_result(false, 87UL); // ERROR_INVALID_PARAMETER
    }
    if (DeleteFileW(_Target) != 0) {
        return zh_make_result(true, 0);
    }
    const zh_ulong e1 = GetLastError();
    if (RemoveDirectoryW(_Target) != 0) {
        return zh_make_result(true, 0);
    }
    const zh_ulong e2 = GetLastError();
    // Prefer the file error unless it was "path not found / access denied",
    // in which case the directory error is the more informative one.
    if (e1 == 2UL || e1 == 3UL || e1 == 5UL) {
        return zh_make_result(false, e2);
    }
    return zh_make_result(false, e1);
}

// ---------------------------------------------------------------------------
//  2) <system_error>: __msvc_system_error_abi.hpp:26-28
//
//     _NODISCARD size_t __stdcall __std_system_error_allocate_message(
//         unsigned long _Message_id, char** _Ptr_str) noexcept;
//     void __stdcall __std_system_error_deallocate_message(char* _Str) noexcept;
//
//  The returned buffer is owned by the caller and released through the
//  deallocate entry, so both use the CRT heap.
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) zh_size_t __stdcall __std_system_error_allocate_message(
    zh_ulong _Message_id, char** _Ptr_str) noexcept {
    if (_Ptr_str != nullptr) {
        *_Ptr_str = nullptr;
    }
    char local[512];
    local[0] = '\0';
    const zh_ulong n = FormatMessageA(
        0x00000100UL | 0x00000200UL, // FORMAT_MESSAGE_FROM_SYSTEM | IGNORE_INSERTS
        nullptr, _Message_id, 0, local, (zh_ulong)sizeof local, nullptr);
    if (n == 0) {
        return 0;
    }
    zh_size_t len = (zh_size_t)n;
    while (len > 0 && (local[len - 1] == '\n' || local[len - 1] == '\r')) {
        --len;
    }
    char* out = static_cast<char*>(malloc(len + 1));
    if (out == nullptr) {
        return 0;
    }
    for (zh_size_t i = 0; i < len; ++i) {
        out[i] = local[i];
    }
    out[len] = '\0';
    if (_Ptr_str != nullptr) {
        *_Ptr_str = out;
    }
    return len;
}

extern "C" __declspec(dllexport) void __stdcall __std_system_error_deallocate_message(char* _Str) noexcept {
    if (_Str != nullptr) {
        free(_Str);
    }
}

// ---------------------------------------------------------------------------
//  3) <chrono> tzdb: __msvc_tzdb.hpp:92
//
//     _NODISCARD void* __stdcall __std_calloc_crt(size_t _Count, size_t _Size) noexcept;
//
//  Uses the CRT heap so the STL's matching free() is valid.
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) void* __stdcall __std_calloc_crt(zh_size_t _Count, zh_size_t _Size) noexcept {
    return calloc(_Count, _Size);
}

// ---------------------------------------------------------------------------
//  4) <memory_resource>: xpolymorphic_allocator.h:168
//
//     extern "C" _CRT_SATELLITE_1 memory_resource* __cdecl
//         _Aligned_get_default_resource() noexcept;
//
//  Used by the pmr-backed aligned operator new. We hand the STL a resource
//  whose vtable matches memory_resource's declaration order:
//      ~memory_resource (deleting dtor), do_allocate, do_deallocate, do_is_equal
//  Every virtual is declared here in exactly that order; no extra virtuals are
//  added, so the layout is what the STL expects.
// ---------------------------------------------------------------------------
namespace std {
namespace pmr {

class memory_resource {
public:
    virtual ~memory_resource() = default;

    virtual void* do_allocate(zh_size_t _Bytes, zh_size_t _Align) = 0;
    virtual void  do_deallocate(void* _Ptr, zh_size_t _Bytes, zh_size_t _Align) = 0;
    virtual bool  do_is_equal(const memory_resource& _That) const noexcept = 0;
};

}  // namespace pmr
}  // namespace std

namespace {

class zh_aligned_resource final : public std::pmr::memory_resource {
public:
    void* do_allocate(zh_size_t _Bytes, zh_size_t _Align) override {
        return _aligned_malloc(_Bytes, _Align < sizeof(void*) ? sizeof(void*) : _Align);
    }
    void do_deallocate(void* _Ptr, zh_size_t, zh_size_t) override {
        _aligned_free(_Ptr);
    }
    bool do_is_equal(const std::pmr::memory_resource& _That) const noexcept override {
        return this == &_That;
    }
};

zh_aligned_resource& zh_aligned_instance() {
    static zh_aligned_resource s_instance;
    return s_instance;
}

}  // namespace

extern "C" __declspec(dllexport) std::pmr::memory_resource* __cdecl
_Aligned_get_default_resource() noexcept {
    return &zh_aligned_instance();
}
