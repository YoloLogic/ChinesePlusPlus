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
// ============================================================================
//  Second slice: the rest of the __std_fs_* surface (same ABI, same reasons).
//  Enums below are transcribed verbatim from xfilesystem_abi.h.
// ============================================================================

extern "C" {

enum class __std_code_page : unsigned int { _Acp = 0, _Utf8 = 65001 };

struct __std_fs_convert_result {
    int _Len;
    __std_win_error _Err;
};

enum class __std_fs_copy_options {
    _None               = 0x0,
    _Existing_mask      = 0xF,
    _Skip_existing      = 0x1,
    _Overwrite_existing = 0x2,
    _Update_existing    = 0x4,
};

enum class __std_fs_filetime_abi_placeholder { _X = 0 };

struct zh_filetime { unsigned long low; unsigned long high; };

struct zh_win32_find_data {
    unsigned long dwFileAttributes;
    zh_filetime ftCreationTime;
    zh_filetime ftLastAccessTime;
    zh_filetime ftLastWriteTime;
    unsigned long nFileSizeHigh;
    unsigned long nFileSizeLow;
    unsigned long dwReserved0;
    unsigned long dwReserved1;
    wchar_t cFileName[260];
    wchar_t cAlternateFileName[14];
};

struct zh_by_handle_information {
    unsigned long dwFileAttributes;
    zh_filetime ftCreationTime;
    zh_filetime ftLastAccessTime;
    zh_filetime ftLastWriteTime;
    unsigned long dwVolumeSerialNumber;
    unsigned long nFileSizeHigh;
    unsigned long nFileSizeLow;
    unsigned long nNumberOfLinks;
    unsigned long nFileIndexHigh;
    unsigned long nFileIndexLow;
};

__declspec(dllimport) int        __stdcall CopyFileW(const wchar_t*, const wchar_t*, int);
__declspec(dllimport) unsigned long __stdcall GetFileAttributesW(const wchar_t*);
__declspec(dllimport) void*      __stdcall FindFirstFileW(const wchar_t*, zh_win32_find_data*);
__declspec(dllimport) int        __stdcall FindNextFileW(void*, zh_win32_find_data*);
__declspec(dllimport) int        __stdcall FindClose(void*);
__declspec(dllimport) void*      __stdcall CreateFileW(const wchar_t*, unsigned long, unsigned long,
                                    void*, unsigned long, unsigned long, void*);
__declspec(dllimport) int        __stdcall CloseHandle(void*);
__declspec(dllimport) int        __stdcall GetFileInformationByHandle(void*, zh_by_handle_information*);
__declspec(dllimport) int        __stdcall SetFileTime(void*, const void*, const void*, const zh_filetime*);
__declspec(dllimport) int        __stdcall GetDiskFreeSpaceExW(const wchar_t*, unsigned long long*,
                                    unsigned long long*, unsigned long long*);
__declspec(dllimport) unsigned int __stdcall GetACP(void);
__declspec(dllimport) int        __stdcall WideCharToMultiByte(unsigned int, unsigned long,
                                    const wchar_t*, int, char*, int, const char*, int*);

struct __std_fs_copy_file_result { bool _Copied; __std_win_error _Error; };
struct __std_fs_equivalent_result { bool _Equivalent; __std_win_error _Error; };

// ---------------------------------------------------------------------------
//  __std_fs_copy_file  (xfilesystem_abi.h:272-277)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_fs_copy_file_result __stdcall
__std_fs_copy_file(const wchar_t* _Source, const wchar_t* _Target, __std_fs_copy_options _Options) noexcept {
    __std_fs_copy_file_result 结果;
    结果._Copied = false;
    结果._Error  = __std_win_error::_Invalid_parameter;
    if (_Source == nullptr || _Target == nullptr) {
        return 结果;
    }
    if ((static_cast<unsigned long>(_Options) & static_cast<unsigned long>(__std_fs_copy_options::_Skip_existing)) != 0UL) {
        if (GetFileAttributesW(_Target) != 0xFFFFFFFFUL) {
            结果._Error = __std_win_error::_Already_exists;
            return 结果;
        }
    }
    if (CopyFileW(_Source, _Target, 0) != 0) {
        结果._Copied = true;
        结果._Error  = __std_win_error::_Success;
        return 结果;
    }
    结果._Error = static_cast<__std_win_error>(GetLastError());
    return 结果;
}

// ---------------------------------------------------------------------------
//  __std_fs_equivalent  (xfilesystem_abi.h:306-311)
// ---------------------------------------------------------------------------
static int zh_open_for_info(const wchar_t* _Path, zh_by_handle_information* _Info) {
    // GENERIC_READ=0x80000000, FILE_SHARE_READ|WRITE|DELETE=7,
    // OPEN_EXISTING=3, FILE_FLAG_BACKUP_SEMANTICS=0x02000000
    void* h = CreateFileW(_Path, 0x80000000UL, 7UL, nullptr, 3UL, 0x02000000UL, nullptr);
    if (h == (void*)-1 || h == nullptr) {
        return 0;
    }
    const int ok = GetFileInformationByHandle(h, _Info);
    CloseHandle(h);
    return ok;
}

__declspec(dllexport) __std_fs_equivalent_result __stdcall
__std_fs_equivalent(const wchar_t* _Path1, const wchar_t* _Path2) noexcept {
    __std_fs_equivalent_result 结果;
    结果._Equivalent = false;
    结果._Error      = __std_win_error::_Invalid_parameter;
    if (_Path1 == nullptr || _Path2 == nullptr) {
        return 结果;
    }
    zh_by_handle_information 甲, 乙;
    if (zh_open_for_info(_Path1, &甲) == 0) {
        结果._Error = static_cast<__std_win_error>(GetLastError());
        return 结果;
    }
    if (zh_open_for_info(_Path2, &乙) == 0) {
        结果._Error = static_cast<__std_win_error>(GetLastError());
        return 结果;
    }
    const bool 同卷 = 甲.dwVolumeSerialNumber == 乙.dwVolumeSerialNumber;
    const bool 同号 = 甲.nFileIndexHigh == 乙.nFileIndexHigh && 甲.nFileIndexLow == 乙.nFileIndexLow;
    结果._Equivalent = 同卷 && 同号;
    结果._Error      = __std_win_error::_Success;
    return 结果;
}

// ---------------------------------------------------------------------------
//  __std_fs_set_last_write_time  (xfilesystem_abi.h:309-310)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_win_error __stdcall
__std_fs_set_last_write_time(long long _Last_write_filetime, const wchar_t* _Path) noexcept {
    if (_Path == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    // FILE_WRITE_ATTRIBUTES = 0x100
    void* h = CreateFileW(_Path, 0x100UL, 7UL, nullptr, 3UL, 0x02000000UL, nullptr);
    if (h == (void*)-1 || h == nullptr) {
        return static_cast<__std_win_error>(GetLastError());
    }
    zh_filetime ft;
    ft.low  = static_cast<unsigned long>(static_cast<unsigned long long>(_Last_write_filetime) & 0xFFFFFFFFULL);
    ft.high = static_cast<unsigned long>(static_cast<unsigned long long>(_Last_write_filetime) >> 32);
    const int ok = SetFileTime(h, nullptr, nullptr, &ft);
    CloseHandle(h);
    return ok != 0 ? __std_win_error::_Success : static_cast<__std_win_error>(GetLastError());
}

// ---------------------------------------------------------------------------
//  __std_fs_space  (xfilesystem_abi.h:366-368)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_win_error __stdcall
__std_fs_space(const wchar_t* _Target, unsigned long long* _Available,
               unsigned long long* _Total_bytes, unsigned long long* _Free_bytes) noexcept {
    if (_Target == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    unsigned long long 可用 = 0, 总量 = 0, 空闲 = 0;
    if (GetDiskFreeSpaceExW(_Target, &可用, &总量, &空闲) == 0) {
        return static_cast<__std_win_error>(GetLastError());
    }
    if (_Available)   { *_Available   = 可用; }
    if (_Total_bytes) { *_Total_bytes = 总量; }
    if (_Free_bytes)  { *_Free_bytes  = 空闲; }
    return __std_win_error::_Success;
}

// ---------------------------------------------------------------------------
//  __std_fs_get_stats  (xfilesystem_abi.h:286-288)
// ---------------------------------------------------------------------------
struct __std_fs_stats_local {
    long long _Last_write_time;
    unsigned long long _File_size;
    unsigned long _Attributes;
    unsigned long _Reparse_point_tag;
    unsigned long _Link_count;
    unsigned long _Available;
};

__declspec(dllexport) __std_win_error __stdcall
__std_fs_get_stats(const wchar_t* _Path, __std_fs_stats_local* _Stats, unsigned long _Flags,
                   unsigned long _Symlink_attribute_hint) noexcept {
    (void)_Symlink_attribute_hint;
    if (_Path == nullptr || _Stats == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    zh_win32_find_data fd;
    void* h = FindFirstFileW(_Path, &fd);
    if (h == (void*)-1 || h == nullptr) {
        return static_cast<__std_win_error>(GetLastError());
    }
    FindClose(h);
    // FILETIME -> 100ns since 1601; the STL wants milliseconds since that epoch.
    const long long 文件时间 = (static_cast<long long>(fd.ftLastWriteTime.high) << 32)
                             | static_cast<long long>(fd.ftLastWriteTime.low);
    _Stats->_Last_write_time  = 文件时间 / 10000LL;
    _Stats->_File_size        = (static_cast<unsigned long long>(fd.nFileSizeHigh) << 32)
                             | static_cast<unsigned long long>(fd.nFileSizeLow);
    _Stats->_Attributes       = fd.dwFileAttributes;
    _Stats->_Reparse_point_tag = fd.dwReserved0;
    _Stats->_Link_count       = 1;
    // report which fields we filled: attributes | reparse_tag | file_size | link_count | last_write_time
    (void)_Flags;
    _Stats->_Available = 0x02UL | 0x04UL | 0x08UL | 0x10UL | 0x20UL;
    return __std_win_error::_Success;
}

// ---------------------------------------------------------------------------
//  code page + wide->narrow  (xfilesystem_abi.h:287-300)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_code_page __stdcall __std_fs_code_page() noexcept {
    return static_cast<__std_code_page>(GetACP());
}

__declspec(dllexport) __std_fs_convert_result __stdcall
__std_fs_convert_wide_to_narrow_replace_chars(__std_code_page _Code_page, const wchar_t* _Input_str,
                                              int _Input_len, char* _Output_str, int _Output_len) noexcept {
    __std_fs_convert_result 结果;
    结果._Len = 0;
    结果._Err = __std_win_error::_Invalid_parameter;
    if (_Input_str == nullptr || _Output_str == nullptr || _Output_len <= 0) {
        return 结果;
    }
    const unsigned int cp = (static_cast<unsigned int>(_Code_page) == 0u) ? GetACP()
                                                                         : static_cast<unsigned int>(_Code_page);
    const int n = WideCharToMultiByte(cp, 0, _Input_str, _Input_len, _Output_str, _Output_len, nullptr, nullptr);
    if (n == 0) {
        结果._Err = static_cast<__std_win_error>(GetLastError());
        return 结果;
    }
    结果._Len = n;
    结果._Err = __std_win_error::_Success;
    return 结果;
}

// ---------------------------------------------------------------------------
//  directory iterator trio  (xfilesystem_abi.h:275-286)
// ---------------------------------------------------------------------------
__declspec(dllexport) __std_win_error __stdcall
__std_fs_directory_iterator_open(const wchar_t* _Path_spec, void** _Handle, void* _Results) noexcept {
    if (_Path_spec == nullptr || _Handle == nullptr || _Results == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    void* h = FindFirstFileW(_Path_spec, static_cast<zh_win32_find_data*>(_Results));
    if (h == (void*)-1 || h == nullptr) {
        *_Handle = (void*)-1;
        return static_cast<__std_win_error>(GetLastError());
    }
    *_Handle = h;
    return __std_win_error::_Success;
}

__declspec(dllexport) __std_win_error __stdcall
__std_fs_directory_iterator_advance(void* _Handle, void* _Results) noexcept {
    if (_Handle == nullptr || _Handle == (void*)-1 || _Results == nullptr) {
        return __std_win_error::_Invalid_parameter;
    }
    if (FindNextFileW(_Handle, static_cast<zh_win32_find_data*>(_Results)) == 0) {
        return static_cast<__std_win_error>(GetLastError());
    }
    return __std_win_error::_Success;
}

__declspec(dllexport) void __stdcall __std_fs_directory_iterator_close(void* _Handle) noexcept {
    if (_Handle != nullptr && _Handle != (void*)-1) {
        FindClose(_Handle);
    }
}

} // extern "C"