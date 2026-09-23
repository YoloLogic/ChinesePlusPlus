// expect: 表达式的结果未被使用
// forbid: expression result unused
//
// 算了个结果又扔掉（本文件加 -Wall）。
// 对应诊断：warn_unused_expr
整数 main() { 1 + 1; 返回 0; }
