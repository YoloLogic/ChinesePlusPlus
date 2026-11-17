#pragma once
#ifndef _CORECRT_TERMINATE_H
#define _CORECRT_TERMINATE_H

// 手写最小实现：只声明 UCRT（ucrtbase.lib）实际导出的 terminate 家族符号。
// 为什么不用 SDK 原件：SDK 的 corecrt_terminate.h 依赖 _UCRT_DISABLE_CLANG_WARNINGS
// / _CRT_BEGIN_C_HEADER 等宏，我们的 bundled UCRT 地基里没有（第 3 轮实测报错）。

#include <corecrt.h>

#ifndef _ACRTIMP
#define _ACRTIMP __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (__cdecl* terminate_handler)(void);
typedef void (__cdecl* terminate_function)(void);

[[noreturn]] _ACRTIMP void __cdecl terminate(void) noexcept;
_ACRTIMP terminate_handler __cdecl _get_terminate(void) noexcept;
_ACRTIMP terminate_handler __cdecl set_terminate(terminate_handler _Handler) noexcept;

#ifdef __cplusplus
}
#endif

#endif // _CORECRT_TERMINATE_H
