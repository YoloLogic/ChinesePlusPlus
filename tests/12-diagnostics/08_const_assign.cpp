// expect: 不能给常量限定类型（类型） '常量 整数' 的变量（变量名） '甲' 赋值
// expect: 变量（变量名） '甲' 在此被声明为常量
// forbid: cannot assign to variable
// forbid: declared const here
//
// 给常量赋值。这是本批里最复杂的一条：中文表里是一个 5 分支的 %select，
// 分支内还嵌了两层 %select。本文件触发的是第 2 个分支与对应的 note。
// 对应诊断：err_typecheck_assign_const / note_typecheck_assign_const
//
// ⚠ 期望值 2026-10-04 由 `'const int'` 改成 `'常量 整数'`：原文记的是【旧行为】——
//   类型名与限定符都走 TypePrinter，过去打英文。大检查 P-09 / §18.8 起，
//   中文诊断下内建类型名用中文、限定符也用中文（与消息正文同一个开关）。
//   英文模式（-fno-chinese-diagnostics）仍然打 `'const int'`，两侧都对拍过。
整数 main() { 常量 整数 甲 = 1; 甲 = 2; 返回 0; }
