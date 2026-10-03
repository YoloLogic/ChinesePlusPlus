// expect: （关键字） '静态' 不能用在友元声明里
// forbid: is invalid in friend declarations
//
// 友元声明里写了存储类说明符。
// 对应诊断：err_friend_decl_spec
//
// ⚠ 期望值 2026-10-03 由 `'static'` 改成 `'静态'`：原文记的是【旧缺陷】——
//   说明符名走的是 DeclSpec::getSpecifierName() 那张硬编码英文表，是**实参**
//   不是正文，所以中文诊断表够不着它（大检查 P-04 / §18.3 修好）。
//   现在：中文模式显示 `静态`（本行），英文模式（-fno-chinese-diagnostics）
//   仍然显示 `'static' is invalid in friend declarations` —— 两侧都对拍过。
struct A { friend static int x; };
