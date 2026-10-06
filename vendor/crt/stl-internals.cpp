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
