// ============================================================================
//  stl-internals.cpp -- STL plumbing Microsoft keeps inside msvcprt.lib
//  Chinese++ section 18.48 batch 3
//
//  WHY
//    MEASURED with `dumpbin /exports`: msvcp140.dll (and msvcp140_1/_2/
//    _codecvt_ids, vcruntime140) export many std::_Facet_* symbols but NOT
//    `std::_Facet_Register`. The STL declares it in <xfacet> and calls it from
//    <xlocale> when a locale registers a facet, so its definition lives inside
//    Microsoft's msvcprt.lib, which may not be redistributed. This is our own
//    implementation of the same contract: keep the facets in a table and release
//    one reference on each when the program ends, so facets are destroyed instead
//    of merely leaked.
//
//  DELIBERATELY HEADER-FREE (same reason as newdelete.cpp: including <xlocale>
//  pulls in <cstddef>, which conflicts with the data-import macros the STL's data
//  declarations need -- see the note in vendor\compiler-support\vcruntime.h).
//  `_Facet_base` is declared here with the layout the STL guarantees: a vtable
//  whose first two entries are _Incref and _Decref. Only virtual calls go through
//  that class, so the layout is what matters.
//
//  ASCII only.
// ============================================================================

namespace std {

class _Facet_base {
public:
    virtual void _Incref() = 0;
    virtual void _Decref() = 0;
};

extern "C++" void __cdecl _Facet_Register(_Facet_base* _This);

} // namespace std

namespace {

const int kMaxFacets = 128;
std::_Facet_base* g_facets[kMaxFacets];
int g_count = 0;

} // namespace

//  Called by our own startup object (vendor\crt\crt0.c) just before exit: we own
//  mainCRTStartup, so we do not need the CRT's atexit for this (MEASURED: `atexit`
//  is not among the symbols our import libraries provide).
extern "C" void __cdecl zh_drain_stl_facets(void) {
    for (int i = g_count - 1; i >= 0; --i) {
        if (g_facets[i] != nullptr) {
            g_facets[i]->_Decref();
            g_facets[i] = nullptr;
        }
    }
    g_count = 0;
}

extern "C++" void __cdecl std::_Facet_Register(std::_Facet_base* _This) {
    if (_This == nullptr) {
        return;
    }
    if (g_count < kMaxFacets) {
        g_facets[g_count++] = _This;
    }
    //  Table full: the facet simply lives until the process ends. Never crash here.
}

// ----------------------------------------------------------------------------
//  The STL's out-of-line "trivial" helpers (18.48 batch 4 supplement)
//
//  WHY: MSVC's <xutility> declares these as extern "C" and calls them for
//  byte-sized element types (char / unsigned char). MEASURED 2026-10-06: they
//  live in Microsoft's STATIC STL (msvcprt.lib) and are exported by NO DLL we
//  may ship -- msvcp140 / _1 / _2 / _atomic_wait / _codecvt_ids, vcruntime140*,
//  concrt140, ucrtbase all checked. Without them a bundled link dies with
//  "undefined symbol: __std_search_1" (found by
//  build\_review_own\batch5diag\stl_smoke.cpp).
//
//  They are ordinary byte algorithms, so they are hand-written here. Signatures
//  are copied from vendor\msvc-stl\xutility (lines 75/91/101) so the ABI matches.
//
//  This file still includes NO STL header (see the note at the top).
// ----------------------------------------------------------------------------
extern "C" int __cdecl memcmp(const void*, const void*, unsigned long long);

extern "C" const void* __stdcall __std_find_trivial_1(const void* _First, const void* _Last, unsigned char _Val) noexcept {
    const unsigned char* _F = (const unsigned char*)_First;
    const unsigned char* _L = (const unsigned char*)_Last;
    for (; _F != _L; ++_F) {
        if (*_F == _Val) { return _F; }
    }
    return _L;
}

extern "C" const void* __stdcall __std_search_1(const void* _First1, const void* _Last1,
                                                const void* _First2, unsigned long long _Count2) noexcept {
    const unsigned char* _F1 = (const unsigned char*)_First1;
    const unsigned char* _L1 = (const unsigned char*)_Last1;
    const unsigned char* _F2 = (const unsigned char*)_First2;
    if (_Count2 == 0) { return _F1; }
    if ((unsigned long long)(_L1 - _F1) < _Count2) { return _L1; }
    const unsigned char* _Stop = _L1 - _Count2;
    for (const unsigned char* _P = _F1; _P <= _Stop; ++_P) {
        if (*_P == *_F2 && memcmp(_P, _F2, _Count2) == 0) { return _P; }
    }
    return _L1;
}

extern "C" void __cdecl __std_reverse_trivially_swappable_1(void* _First, void* _Last) noexcept {
    unsigned char* _F = (unsigned char*)_First;
    unsigned char* _L = (unsigned char*)_Last;
    while (_F < _L) {
        --_L;
        if (_F != _L) {
            const unsigned char _T = *_F;
            *_F = *_L;
            *_L = _T;
        }
        ++_F;
    }
}
