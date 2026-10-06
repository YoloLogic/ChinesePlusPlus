// ============================================================================
//  startup-extra.cpp -- 静态 CRT 里本该有、但我们顶掉 libcmt 后要自己补的入口胶水
//                      （§18.48 批4）
//
//  WHY
//    MEASURED: `--coverage` 链 clang_rt.profile 时报
//      lld-link: error: undefined symbol: atexit
//    原因：UCRT 导出的是 `_crt_atexit`（ucrtbase.dll），而 C 标准里的 `atexit` 是
//    **静态 CRT 的薄包装**（微软的 libcmt.lib 提供）。我们顶掉了 libcmt ⇒ 自己写。
//
//  为什么 `atexit` 没有出现在 mingw 的 libucrt.a 里（实测 nm）：
//    它只有 `_crt_atexit` / `_o__crt_atexit`；`atexit` 这个名字在 UCRT 里根本不存在
//    （`_onexit` 倒是有，所以这里**不**再定义 `_onexit`，免得和 UCRT 的导出打架）。
//
//  语义（与微软一致）：`atexit(f)` = `_crt_atexit(f)`，注册进 UCRT 自己的退出表，
//    由 ucrtbase 的 `exit()` 按**后进先出**调用 —— crt0 调的就是 ucrtbase 的 `exit`，
//    所以这条链是通的（实测：--coverage 的 .gcda 能在退出时落盘，见 §18.48 批4）。
//
//  另见本文件里的 `_fltused`：同属"微软静态 CRT 里本该有、我们顶掉 libcmt 后必须补"。
//
//  ASCII only.
// ============================================================================

extern "C" {

__declspec(dllimport) int __cdecl _crt_atexit(void (__cdecl* _Function)(void));

int __cdecl atexit(void (__cdecl* _Function)(void)) {
    return _crt_atexit(_Function);
}

//  `_fltused`: clang emits a reference to it in every TU that touches floating
//  point -- including a TU that merely pulls in MSVC's `num_put` facet, whose
//  vftable contains `do_put(double)`.
//
//  MEASURED (18.48 batch 4, found AFTER the first green run -- see the ledger):
//      std::cout << "text" << std::endl;   links fine
//      std::cout << 42;                    lld-link: error: undefined symbol: _fltused
//  So a bundled link used to break on the most ordinary thing a C++ program
//  does: print a number. Microsoft's static CRT defines it; ours must too.
//  The value is Microsoft's sentinel (0x9875); nothing reads it, its only job is
//  to exist so the linker pulls in the float support.
//
//  NOT in any library we ship (checked, 2026-10-06): libcmt / mingwex / ucrt /
//  ucrtbase / oldnames -- and mingw's libmingwex.a does not have it either.
int _fltused = 0x9875;

} // extern "C"

//  `std::nothrow`: declared by <vcruntime_new.h> (ours), and DEFINED by Microsoft's
//  static CRT -- MEASURED 2026-10-06: it is in MSVC's msvcprt.lib, and NOT in any
//  DLL we ship (msvcp140/msvcp140_1/_2/_atomic_wait/_codecvt_ids, vcruntime140,
//  vcruntime140_1, vcruntime140_threads, concrt140, ucrtbase -- all checked as raw
//  export strings), nor in mingw's libraries.
//
//  WHY IT MATTERS: <new> uses it for the nothrow allocation forms, so
//      int* p = new (std::nothrow) int(3);
//  -- ordinary, standard C++ -- fails to link without it. Found by
//  build\_review_own\batch5diag\stl_smoke.cpp.
//
//  <vcruntime_new.h> is one of OUR hand-written compiler-support headers (it is
//  what declares nothrow_t), so including it does not drag in any STL header --
//  which is the rule this file must keep (see the note about max_align_t above).
#include <vcruntime_new.h>

namespace std {

extern const nothrow_t nothrow{};

} // namespace std
