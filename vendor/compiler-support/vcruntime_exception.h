// ============================================================================
//  vcruntime_exception.h -- 手写层，类体逐行抄自 MSVC 14.44 的 vcruntime_exception.h
//
//  为什么不整文件照搬：原件 `#include <eh.h>` + `_VCRT_EXPORT_STD` / `_CRT_BEGIN_C_HEADER`
//  / `_In_` 等宏来自真正的 vcruntime.h 与 SDK，我们的 bundled UCRT 地基里没有
//  （第 3 轮实测：整文件搬进来报 _VCRT_EXPORT_STD / _UCRT_DISABLE_CLANG_WARNINGS 未定义）。
//  所以这里只保留【类定义本身】——它是编译器与 ABI 的契约，一个字节都不能改：
//    · exception() / explicit exception(const char*) / exception(const char*, int)
//    · bad_exception / bad_alloc / bad_array_new_length（<stdexcept> 的 _Mybase 依赖这些）
//  原件的 preprocessor 外壳（sal 注解、pragma、_VCRT_EXPORT_STD）全部省掉。
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_EXCEPTION_H
#define _VCRUNTIME_EXCEPTION_H

#include <vcruntime.h>
#include <corecrt_terminate.h>
#include <stddef.h>

#ifndef _ZH_CORE_EXCEPTION_DEFINED
#define _ZH_CORE_EXCEPTION_DEFINED

extern "C" {

struct __std_exception_data {
    char const* _What;
    bool        _DoFree;
};

_VCRTIMP void __cdecl __std_exception_copy(const __std_exception_data* _From, __std_exception_data* _To);
_VCRTIMP void __cdecl __std_exception_destroy(__std_exception_data* _Data);

} // extern "C"

extern "C++" {

namespace std {

class _NODISCARD exception {
public:
    exception() noexcept : _Data() {}

    explicit exception(char const* const _Message) noexcept : _Data() {
        __std_exception_data _InitData = {_Message, true};
        __std_exception_copy(&_InitData, &_Data);
    }

    exception(char const* const _Message, int) noexcept : _Data() {
        _Data._What = _Message;
    }

    exception(exception const& _Other) noexcept : _Data() {
        __std_exception_copy(&_Other._Data, &_Data);
    }

    exception& operator=(exception const& _Other) noexcept {
        if (this == &_Other) {
            return *this;
        }
        __std_exception_destroy(&_Data);
        __std_exception_copy(&_Other._Data, &_Data);
        return *this;
    }

    virtual ~exception() noexcept {
        __std_exception_destroy(&_Data);
    }

    _NODISCARD virtual char const* what() const {
        return _Data._What ? _Data._What : "Unknown exception";
    }

private:
    __std_exception_data _Data;
};

class _NODISCARD bad_exception : public exception {
public:
    bad_exception() noexcept : exception("bad exception", 1) {}
};

class _NODISCARD bad_array_new_length;

class _NODISCARD bad_alloc : public exception {
public:
    bad_alloc() noexcept : exception("bad allocation", 1) {}

private:
    friend bad_array_new_length;
    bad_alloc(char const* const _Message) noexcept : exception(_Message, 1) {}
};

class _NODISCARD bad_array_new_length : public bad_alloc {
public:
    bad_array_new_length() noexcept : bad_alloc("bad array new length") {}
};

} // namespace std

} // extern "C++"

#endif // _ZH_CORE_EXCEPTION_DEFINED

#endif // _VCRUNTIME_EXCEPTION_H
