// expect: 不能给常量限定类型 'const int' 的变量 '甲' 赋值
// expect: 变量 '甲' 在此被声明为常量
// forbid: cannot assign to variable
// forbid: declared const here
//
// 给常量赋值。这是本批里最复杂的一条：中文表里是一个 5 分支的 %select，
// 分支内还嵌了两层 %select。本文件触发的是第 2 个分支与对应的 note。
// 对应诊断：err_typecheck_assign_const / note_typecheck_assign_const
整数 main() { 常量 整数 甲 = 1; 甲 = 2; 返回 0; }
