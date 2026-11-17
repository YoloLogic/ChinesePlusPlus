// ============================================================================
//  compat_symbols.cpp -- 补齐 bundled UCRT 地基里缺失的 UCRT/mingw 符号
//
//  实测（2026-11-16，lld-link 报错）：
//    · undefined symbol: __mingw_module_is_dll   ← ucrtbase.lib/ucrt.lib 的 .refptr 要它
//    · undefined symbol: _fpreset                ← mingwex.lib 直接调用它
//    · undefined symbol: timespec_get            ← 所有 vendor/crt 库里都没有定义
//  这三个都由本文件提供，编译成 vendor\crt\compat.lib 后由 cfg 链接。
// ============================================================================

#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

// mingw 的导入库用这个标志判断"当前模块是不是 DLL"。对静态链进 EXE 的场景，0 即可。
int __mingw_module_is_dll = 0;

// mingwex 调用 _fpreset；UCRT 导出的是函数指针 __imp__fpreset。
// 这里把数据导入符号转成函数调用（__imp__fpreset 由 ucrtbase.lib 提供）。
extern void (*__imp__fpreset)(void);
void _fpreset(void) {
    if (__imp__fpreset) {
        __imp__fpreset();
    }
}

// timespec_get：UCRT 导入库里没有这个符号，用 Win32 时间 API 自己实现（TIME_UTC）。
// 声明 Win32 API 的最小原型，避免依赖 windows.h 的宏污染。
__declspec(dllimport) void __stdcall GetSystemTimePreciseAsFileTime(void* _Ft);

// 头文件把 timespec_get 声明成 dllimport，调用点要的是导入指针 __imp_timespec_get。
// 这里提供一个指向我们自己实现的导入指针，两种引用方式都能解。
extern int (*__imp_timespec_get)(struct timespec*, int);

int timespec_get(struct timespec* _Ts, int _Base) {
    (void)_Base;
    if (!_Ts) {
        return 0;
    }
    // FILETIME：1601-01-01 起的 100ns 计数
    struct {
        unsigned int dwLowDateTime;
        unsigned int dwHighDateTime;
    } _Ft = {0, 0};
    GetSystemTimePreciseAsFileTime(&_Ft);
    unsigned long long _Ticks =
        ((unsigned long long)_Ft.dwHighDateTime << 32) | _Ft.dwLowDateTime;
    // 1601 -> 1970：11644473600 秒
    const unsigned long long _EpochDiff = 11644473600ULL * 10000000ULL;
    if (_Ticks < _EpochDiff) {
        return 0;
    }
    unsigned long long _Since1970 = _Ticks - _EpochDiff;
    _Ts->tv_sec = (long long)(_Since1970 / 10000000ULL);
    _Ts->tv_nsec = (long)((_Since1970 % 10000000ULL) * 100);
    return 1;
}

#ifdef __cplusplus
}
#endif

extern "C" int (*__imp_timespec_get)(struct timespec*, int) = &timespec_get;
