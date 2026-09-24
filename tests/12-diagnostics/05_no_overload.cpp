// expect: 没有与（函数名） 'f' 匹配的函数
// forbid: no matching function for call to
// expect: 没有已知的转换从
// forbid: no known conversion from
//
// 重载决议失败。一次验证三件事：
//   1) 主错误 err_ovl_no_viable_function_in_call 已汉化；
//   2) 候选函数的 note（note_ovl_candidate_bad_conv）**也**已汉化；
//   3) 英文原句两种模式下都不得出现（-fno-chinese-diagnostics 那一支由
//      check.ps1 的开关断言覆盖）。
//
// 历史：第 2 条原来是「这个 note 【没有】汉化，是回退英文的证据」。
// 2026-09-24 全表覆盖后它也被翻掉了，于是本条从「回退证据」变成「已汉化证据」。
// 回退路径本身已经没有真实诊断可观测（凡有英文正文者都已进表），
// 那条保证改由 tools\diag_id_lookup.py --check-table 的表级断言承担。
整数 f(整数);
整数 f(双精度);
整数 main() { 返回 f("x"); }
