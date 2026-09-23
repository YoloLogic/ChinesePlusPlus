// expect: 变量（变量名） '甲' 被赋值但未被使用
// forbid: set but not used
//
// 全局变量赋了值但没用。英文与 warn_unused_but_set_variable【逐字相同】，
// 却是另一个 ID —— 只翻一个就会中英并排。
// 本文件加 -Wall -Wunused-but-set-global。
// 对应诊断：warn_unused_but_set_global
static 整数 甲 = 0;
整数 f() { 甲 = 1; 返回 0; }
