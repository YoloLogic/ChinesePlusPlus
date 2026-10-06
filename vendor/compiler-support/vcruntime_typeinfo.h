// ============================================================================
//  vcruntime_typeinfo.h -- hand-written, MSVC-ABI compatible (18.48 batch 2)
//
//  WHAT THE STL NEEDS FROM IT (measured): <typeinfo> includes it and expects
//  std::type_info to be DEFINED here, laid out exactly the way the compiler's
//  RTTI emits it: a vftable pointer (implicit, from the virtual destructor)
//  followed by the decorated-name bytes. The three helpers below are exported by
//  vcruntime140.dll. We declare them and define the class; we implement nothing.
//
//  WHY THE LAYOUT MATTERS: clang in MS-compatibility mode emits `??_7type_info@@6B@`
//  vftable references and stores the decorated name right after the object, so a
//  hand-written class MUST match Microsoft's layout byte for byte -- otherwise
//  typeid/dynamic_cast would read garbage. This is verified at run time in batch 4
//  (throw/catch, typeid, dynamic_cast), not merely compiled.
//
//  ASCII only.
// ============================================================================
#pragma once
#ifndef _VCRUNTIME_TYPEINFO_H
#define _VCRUNTIME_TYPEINFO_H

#include <vcruntime.h>
#include <vcruntime_exception.h>
#include <stddef.h>

extern "C" {

struct __std_type_info_data {
    const char* _UndecoratedName;
    const char  _DecoratedName[1];
};

// Root of the (legacy) type_info linked list; the runtime DLL owns it.
struct __type_info_node {
    void* _MemPtr;
    __type_info_node* _Next;
};
extern __type_info_node __type_info_root_node;

_VCRTIMP int __cdecl __std_type_info_compare(const __std_type_info_data* _Lhs, const __std_type_info_data* _Rhs);
_VCRTIMP size_t __cdecl __std_type_info_hash(const __std_type_info_data* _Data);
_VCRTIMP const char* __cdecl __std_type_info_name(__std_type_info_data* _Data, __type_info_node* _RootNode);

} // extern "C"

extern "C++" {

namespace std {

class type_info {
public:
    virtual ~type_info() noexcept {}

    type_info(const type_info&) = delete;
    type_info& operator=(const type_info&) = delete;

    [[nodiscard]] size_t hash_code() const noexcept {
        return __std_type_info_hash(&_Data);
    }

    [[nodiscard]] bool operator==(const type_info& _Other) const noexcept {
        return __std_type_info_compare(&_Data, &_Other._Data) == 0;
    }

    [[nodiscard]] bool operator!=(const type_info& _Other) const noexcept {
        return __std_type_info_compare(&_Data, &_Other._Data) != 0;
    }

    [[nodiscard]] bool before(const type_info& _Other) const noexcept {
        return __std_type_info_compare(&_Data, &_Other._Data) < 0;
    }

    [[nodiscard]] const char* name() const noexcept {
        return __std_type_info_name(&_Data, &__type_info_root_node);
    }

    [[nodiscard]] const char* raw_name() const noexcept {
        return _Data._DecoratedName;
    }

private:
    mutable __std_type_info_data _Data;
};

// NOTE: std::__non_rtti_object is defined by the STL's own <typeinfo>
// (measured: defining it here as well gives "redefinition of '__non_rtti_object'").

} // namespace std

} // extern "C++"

#endif // _VCRUNTIME_TYPEINFO_H
