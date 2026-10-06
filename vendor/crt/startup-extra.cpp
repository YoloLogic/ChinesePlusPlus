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
//  ASCII only.
// ============================================================================

extern "C" {

__declspec(dllimport) int __cdecl _crt_atexit(void (__cdecl* _Function)(void));

int __cdecl atexit(void (__cdecl* _Function)(void)) {
    return _crt_atexit(_Function);
}

} // extern "C"
