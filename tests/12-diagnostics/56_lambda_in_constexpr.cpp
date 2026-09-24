// expect: lambda 表达式不能出现在常量表达式内部
// forbid: may not appear inside of a constant expression
//
// lambda 出现在常量表达式里 —— 只在 C++17 以前是错（源码条件是
// !getLangOpts().CPlusPlus17），所以本文件加 -std=c++14。
// 对应诊断：err_lambda_in_constant_expression
enum E { X = []{ return 0; }() };
