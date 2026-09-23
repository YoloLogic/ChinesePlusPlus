// expect: 未使用的变量 '甲'
// forbid: unused variable
//
// 定义了没用过的变量（本文件单独加 -Wall）。同时验证：
//   1) 正文变中文
//   2) 前缀 warning: 和选项名 [-Wunused-variable] 保持原样
//      （脚本里按 ASCII 断言 [-Wunused-variable] 仍在）
// 对应诊断：warn_unused_variable
整数 main() { 整数 甲 = 1; 返回 0; }
