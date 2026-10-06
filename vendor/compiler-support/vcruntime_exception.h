// ============================================================================
//  vcruntime_exception.h -- hand-written, MSVC-ABI compatible (18.48 batch 2)
//
//  WHAT THE STL NEEDS FROM IT (measured): <exception> includes it and expects
//  std::exception to be DEFINED here (in the MSVC world std::exception lives in
//  this compiler header, not in the STL), plus the two C helpers the runtime DLL
//  exports. The layout below is the documented MSVC ABI: a pointer to the message
//  plus a "must free" flag -- nothing else, so exception objects stay compatible
//  across the DLL boundary.
//
//  ASCII only.
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_EXCEPTION_H
#define _VCRUNTIME_EXCEPTION_H

#include <vcruntime.h>
#include <stddef.h>

#ifndef _EXCEPTION_DEFINED
#define _EXCEPTION_DEFINED

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

class exception {
public:
    exception() noexcept : _Data{} {}

    exception(const exception& _Other) noexcept : _Data{} {
        __std_exception_copy(&_Other._Data, &_Data);
    }

    exception& operator=(const exception& _Other) noexcept {
        if (this != &_Other) {
            __std_exception_destroy(&_Data);
            __std_exception_copy(&_Other._Data, &_Data);
        }
        return *this;
    }

    virtual ~exception() noexcept {
        __std_exception_destroy(&_Data);
    }

    virtual char const* what() const noexcept {
        return _Data._What ? _Data._What : "Unknown exception";
    }

private:
    __std_exception_data _Data;
};

// NOTE: std::bad_exception and std::exception_ptr are the STL's business
// (defined in <exception>), not ours -- MSVC splits it the same way.

} // namespace std

} // extern "C++"

#endif // _EXCEPTION_DEFINED

#endif // _VCRUNTIME_EXCEPTION_H
