// ============================================================================
//  tzdb-extra.cpp -- <chrono> tzdb ABI, implemented on top of Win32
//  Chinese++ section 18.51
//
//  WHY
//    <chrono>'s tzdb support calls these eight functions. They live in
//    Microsoft's static C++ runtime (msvcprt.lib) and are not exported by
//    msvcp140.dll, so they may not be redistributed. This is our own
//    implementation of the same ABI, declared in __msvc_tzdb.hpp.
//
//  DESIGN (deliberate limits -- document these, do not hide them)
//    * The zone list is a BUILT-IN table of common IANA names mapped to the
//      Windows registry zone keys. It is not the full IANA database: Windows
//      does not ship IANA tzdata, and shipping a compiled tzdata blob is a
//      separate project. Zones outside the table fall back to their Windows
//      key name, so they still round-trip through __std_tzdb_get_sys_info.
//    * Leap seconds: Windows has no historical leap-second table, so
//      __std_tzdb_get_leap_seconds returns an empty list. This is a KNOWN
//      DIFFERENCE from MSVC; it affects leap-second-aware conversions only.
//    * __std_tzdb_get_sys_info reports the CURRENT UTC offset for the zone
//      (offset-only), with _Begin/_End set to +/- infinity. Historical DST
//      transitions are not computed.
//
//  ASCII only. Header-free (same reason as the other vendor\crt files).
// ============================================================================

typedef unsigned long  zh_ulong;
typedef int            zh_int;
typedef __SIZE_TYPE__  zh_size_t;

// ---------------------------------------------------------------------------
//  Win32 declarations we need (kept local to avoid pulling in <windows.h>).
// ---------------------------------------------------------------------------
struct zh_systemtime { unsigned short wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds; };

struct zh_time_zone_information {
    zh_int Bias;
    wchar_t StandardName[32];
    zh_systemtime StandardDate;
    zh_int StandardBias;
    wchar_t DaylightName[32];
    zh_systemtime DaylightDate;
    zh_int DaylightBias;
};

extern "C" {
    __declspec(dllimport) zh_ulong __stdcall GetTimeZoneInformation(zh_time_zone_information* _Info);
    __declspec(dllimport) int      __stdcall WideCharToMultiByte(
        unsigned int _CodePage, zh_ulong _Flags, const wchar_t* _Wide, int _WideLen,
        char* _Narrow, int _NarrowLen, const char* _Default, int* _UsedDefault);
    __declspec(dllimport) void* __cdecl malloc(zh_size_t _Size);
    __declspec(dllimport) void  __cdecl free(void* _Ptr);
}

// ---------------------------------------------------------------------------
//  ABI types (must match vendor\msvc-stl\__msvc_tzdb.hpp exactly).
// ---------------------------------------------------------------------------
enum class __std_tzdb_error {
    _Success   = 0,
    _Win_error = 1,
    _Icu_error = 2,
};

struct __std_tzdb_time_zones_info {
    __std_tzdb_error _Err;
    const char* _Version;
    zh_size_t   _Num_time_zones;
    const char** _Names;
    const char** _Links;
};

struct __std_tzdb_current_zone_info {
    __std_tzdb_error _Err;
    const char* _Tz_name;
};

struct __std_tzdb_sys_info {
    __std_tzdb_error _Err;
    double _Begin;
    double _End;
    zh_int _Offset;   // seconds east of UTC
    zh_int _Save;     // seconds of daylight saving in effect
    const char* _Abbrev;
};

struct __std_tzdb_leap_info {
    unsigned short _Year, _Month, _Day, _Hour, _Negative, _Reserved;
};

// ---------------------------------------------------------------------------
//  Built-in zone table: IANA name + the Windows registry key it maps to.
//  Kept small and ordered (get_tzdb() requires the list be sorted by name).
// ---------------------------------------------------------------------------
struct zh_zone_pair { const char* iana; const char* win; };

static const zh_zone_pair zh_zone_table[] = {
    {"Africa/Cairo",                 "Egypt Standard Time"},
    {"Africa/Johannesburg",          "South Africa Standard Time"},
    {"Africa/Nairobi",               "E. Africa Standard Time"},
    {"America/Anchorage",            "Alaskan Standard Time"},
    {"America/Argentina/Buenos_Aires","Argentina Standard Time"},
    {"America/Bogota",               "SA Pacific Standard Time"},
    {"America/Chicago",              "Central Standard Time"},
    {"America/Denver",               "Mountain Standard Time"},
    {"America/Los_Angeles",          "Pacific Standard Time"},
    {"America/Mexico_City",          "Central Standard Time (Mexico)"},
    {"America/New_York",             "Eastern Standard Time"},
    {"America/Phoenix",              "US Mountain Standard Time"},
    {"America/Sao_Paulo",            "E. South America Standard Time"},
    {"America/Toronto",              "Eastern Standard Time"},
    {"America/Vancouver",            "Pacific Standard Time"},
    {"Asia/Bangkok",                 "SE Asia Standard Time"},
    {"Asia/Dubai",                   "Arabian Standard Time"},
    {"Asia/Hong_Kong",               "China Standard Time"},
    {"Asia/Jakarta",                 "SE Asia Standard Time"},
    {"Asia/Jerusalem",               "Israel Standard Time"},
    {"Asia/Kolkata",                 "India Standard Time"},
    {"Asia/Seoul",                   "Korea Standard Time"},
    {"Asia/Shanghai",                "China Standard Time"},
    {"Asia/Singapore",               "Singapore Standard Time"},
    {"Asia/Taipei",                  "Taipei Standard Time"},
    {"Asia/Tokyo",                   "Tokyo Standard Time"},
    {"Australia/Perth",              "W. Australia Standard Time"},
    {"Australia/Sydney",             "AUS Eastern Standard Time"},
    {"Europe/Amsterdam",             "W. Europe Standard Time"},
    {"Europe/Berlin",                "W. Europe Standard Time"},
    {"Europe/Istanbul",              "Turkey Standard Time"},
    {"Europe/London",                "GMT Standard Time"},
    {"Europe/Madrid",                "Romance Standard Time"},
    {"Europe/Moscow",                "Russian Standard Time"},
    {"Europe/Paris",                 "Romance Standard Time"},
    {"Europe/Rome",                  "W. Europe Standard Time"},
    {"Pacific/Auckland",             "New Zealand Standard Time"},
    {"Pacific/Honolulu",             "Hawaiian Standard Time"},
    {"UTC",                          "UTC"},
};

static const zh_size_t zh_zone_count = sizeof(zh_zone_table) / sizeof(zh_zone_table[0]);

// Stable arrays of name pointers (the STL keeps these past our return).
static const char* zh_zone_names[sizeof(zh_zone_table) / sizeof(zh_zone_table[0])];
static const char* zh_zone_links[sizeof(zh_zone_table) / sizeof(zh_zone_table[0])];

static void zh_ensure_names() {
    static bool done = false;
    if (done) {
        return;
    }
    for (zh_size_t i = 0; i < zh_zone_count; ++i) {
        zh_zone_names[i] = zh_zone_table[i].iana;
        zh_zone_links[i] = nullptr;
    }
    done = true;
}

// Map IANA -> Windows key. Returns nullptr when unknown.
static const char* zh_win_key_for(const char* _Iana, zh_size_t _Len) {
    for (zh_size_t i = 0; i < zh_zone_count; ++i) {
        const char* a = zh_zone_table[i].iana;
        zh_size_t n = 0;
        while (a[n] != '\0') {
            ++n;
        }
        if (n != _Len) {
            continue;
        }
        bool same = true;
        for (zh_size_t k = 0; k < n; ++k) {
            if (a[k] != _Iana[k]) {
                same = false;
                break;
            }
        }
        if (same) {
            return zh_zone_table[i].win;
        }
    }
    return nullptr;
}

// Current zone's Windows key -> IANA name. nullptr when unknown.
static const char* zh_iana_for_win(const wchar_t* _Win, int _WinChars) {
    // Narrow the Windows name first.
    char narrow[64];
    const int n = WideCharToMultiByte(0 /*CP_ACP*/, 0, _Win, _WinChars, narrow, 63, nullptr, nullptr);
    if (n <= 0) {
        return nullptr;
    }
    narrow[n] = '\0';
    for (zh_size_t i = 0; i < zh_zone_count; ++i) {
        const char* w = zh_zone_table[i].win;
        int k = 0;
        while (w[k] != '\0' && narrow[k] != '\0' && w[k] == narrow[k]) {
            ++k;
        }
        if (w[k] == '\0' && narrow[k] == '\0') {
            return zh_zone_table[i].iana;
        }
    }
    return nullptr;
}

// ---------------------------------------------------------------------------
//  time zones
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) __std_tzdb_time_zones_info* __stdcall
__std_tzdb_get_time_zones() noexcept {
    zh_ensure_names();
    __std_tzdb_time_zones_info* info =
        static_cast<__std_tzdb_time_zones_info*>(malloc(sizeof(__std_tzdb_time_zones_info)));
    if (info == nullptr) {
        return nullptr;
    }
    info->_Err           = __std_tzdb_error::_Success;
    info->_Version       = "win32-builtin-1";
    info->_Num_time_zones = zh_zone_count;
    info->_Names         = zh_zone_names;
    info->_Links         = zh_zone_links;
    return info;
}

extern "C" __declspec(dllexport) void __stdcall
__std_tzdb_delete_time_zones(__std_tzdb_time_zones_info* _Info) noexcept {
    // _Names/_Links point at static tables; only the info struct is heap.
    if (_Info != nullptr) {
        free(_Info);
    }
}

// ---------------------------------------------------------------------------
//  current zone
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) __std_tzdb_current_zone_info* __stdcall
__std_tzdb_get_current_zone() noexcept {
    __std_tzdb_current_zone_info* info =
        static_cast<__std_tzdb_current_zone_info*>(malloc(sizeof(__std_tzdb_current_zone_info)));
    if (info == nullptr) {
        return nullptr;
    }
    info->_Err     = __std_tzdb_error::_Win_error;
    info->_Tz_name = nullptr;

    zh_time_zone_information tzi;
    const zh_ulong kind = GetTimeZoneInformation(&tzi);
    if (kind == 0xFFFFFFFFUL) {
        return info; // error, keep _Win_error
    }
    // StandardName is a fixed 32-wide string; find its length.
    int chars = 0;
    while (chars < 32 && tzi.StandardName[chars] != L'\0') {
        ++chars;
    }
    const char* iana = zh_iana_for_win(tzi.StandardName, chars);
    if (iana != nullptr) {
        info->_Tz_name = iana;
        info->_Err     = __std_tzdb_error::_Success;
    }
    return info;
}

extern "C" __declspec(dllexport) void __stdcall
__std_tzdb_delete_current_zone(__std_tzdb_current_zone_info* _Info) noexcept {
    if (_Info != nullptr) {
        free(_Info);
    }
}

// ---------------------------------------------------------------------------
//  sys info: current UTC offset for a zone (offset-only approximation)
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) __std_tzdb_sys_info* __stdcall
__std_tzdb_get_sys_info(const char* _Tz, zh_size_t _Tz_len, double /*_Local*/) noexcept {
    __std_tzdb_sys_info* info =
        static_cast<__std_tzdb_sys_info*>(malloc(sizeof(__std_tzdb_sys_info)));
    if (info == nullptr) {
        return nullptr;
    }
    info->_Err    = __std_tzdb_error::_Win_error;
    info->_Begin  = -1e30;
    info->_End    = 1e30;
    info->_Offset = 0;
    info->_Save   = 0;
    info->_Abbrev = "";

    if (_Tz == nullptr) {
        return info;
    }
    const char* win = zh_win_key_for(_Tz, _Tz_len);
    if (win == nullptr) {
        return info;
    }

    zh_time_zone_information tzi;
    const zh_ulong kind = GetTimeZoneInformation(&tzi);
    if (kind == 0xFFFFFFFFUL) {
        return info;
    }
    // Bias is minutes west of UTC; negate for "east of UTC" seconds.
    const zh_int base = -tzi.Bias * 60;
    info->_Offset = base;
    if (kind == 2 /*TIME_ZONE_ID_DAYLIGHT*/) {
        info->_Offset = base + (-tzi.DaylightBias * 60);
        info->_Save   = -tzi.DaylightBias * 60;
    }
    info->_Abbrev = win;
    info->_Err    = __std_tzdb_error::_Success;
    return info;
}

extern "C" __declspec(dllexport) void __stdcall
__std_tzdb_delete_sys_info(__std_tzdb_sys_info* _Info) noexcept {
    if (_Info != nullptr) {
        free(_Info);
    }
}

// ---------------------------------------------------------------------------
//  leap seconds: Windows provides no historical table -> empty list
// ---------------------------------------------------------------------------
extern "C" __declspec(dllexport) __std_tzdb_leap_info* __stdcall
__std_tzdb_get_leap_seconds(zh_size_t _Prev_ls_size, zh_size_t* _Current_ls_size) noexcept {
    if (_Current_ls_size != nullptr) {
        *_Current_ls_size = 0;
    }
    (void)_Prev_ls_size;
    return nullptr;
}

extern "C" __declspec(dllexport) void __stdcall
__std_tzdb_delete_leap_seconds(__std_tzdb_leap_info* _Info) noexcept {
    if (_Info != nullptr) {
        free(_Info);
    }
}
