// ============================================================================
//  fs-extra.cpp -- <filesystem> ABI, first slice (Chinese++ section 18.59)
//
//  WHY
//    <filesystem>'s __std_fs_* entry points live in Microsoft's static C++
//    runtime (msvcprt.lib) and are not exported by msvcp140.dll. We implement
//    the same ABI from Win32, declared in lib\stl\xfilesystem_abi.h.
//
//  THIS SLICE
//    Only the three functions whose ABI needs nothing but __std_win_error.
//    copy_file / get_stats / the directory-iterator trio / space / equivalent /
//    the code-page pair come next -- they need __std_fs_copy_options,
//    __std_fs_stats and __std_code_page, which are being transcribed first
//    (docs\开发\§18.59-...).
//
//  ASCII only. Header-free (vendor\crt convention).
// ============================================================================

extern "C" {

enum class __std_win_error : unsigned long {
    _Success         = 0,
    _File_not_found  = 2,
    _Path_not_found  = 3,
    _Access_denied   = 5,
    _File_exists     = 80,
    _Invalid_parameter = 87,
    _Already_exists  = 183,
};

// --- Win32 declarations (no <windows.h> here) ------------------------------
__declspec(dllimport) int        __stdcall CreateDirectoryW(const wchar_t* _Path, void* _Security);
__declspec(dllimport) int        __stdcall MoveFileExW(const wchar_t* _Old, const wchar_t* _New, unsigned long _Flags);
__declspec(dllimport) int        __stdcall SetCurrentDirectoryW(const wchar_t* _Path);
__declspec(dllimport) unsigned long __stdcall GetLastError(void);

// --- results --------------------------------------------------------------
struct __std_fs_create_directory_result {
    bool _Created;
    __std_win_error _Error;
};

static __std_win_error zh_last_error() {
    return static_cast<__std_win_error>(GetLastError());
}

// ---------------------------------------------------------------------------
//  __std_fs_create_directory  (xfilesystem_abi.h:351-353)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_fs_create_directory_result __stdcall
__std_fs_create_directory(const wchar_t* _New_directory) noexcept {
    __std_fs_create_directory_result 结果;
    结果._Created = false;
    结果._Error   = __std_win_error::_Invalid_parameter;
    if (_New_directory == nullptr) {
        return 结果;
    }
    if (CreateDirectoryW(_New_directory, nullptr) != 0) {
        结果._Created = true;
        结果._Error   = __std_win_error::_Success;
        return 结果;
    }
    const __std_win_error e = zh_last_error();
    // "Already exists" is reported as a failure by the STL, which then checks
    // whether the existing entry is a directory.
    结果._Error = e;
    return 结果;
}

// ---------------------------------------------------------------------------
//  __std_fs_rename  (xfilesystem_abi.h:362-363)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_win_error __stdcall
__std_fs_rename(const wchar_t* _Source, const wchar_t* _Target) noexcept {
    if (_Source == nullptr || _Target == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    // MOVEFILE_COPY_ALLOWED = 0x2, MOVEFILE_REPLACE_EXISTING = 0x1
    if (MoveFileExW(_Source, _Target, 0x1UL | 0x2UL) != 0) {
        return __std_win_error::_Success;
    }
    return zh_last_error();
}

// ---------------------------------------------------------------------------
//  __std_fs_set_current_path  (xfilesystem_abi.h:324)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_win_error __stdcall
__std_fs_set_current_path(const wchar_t* _Target) noexcept {
    if (_Target == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    if (SetCurrentDirectoryW(_Target) != 0) {
        return __std_win_error::_Success;
    }
    return zh_last_error();
}

} // extern "C"