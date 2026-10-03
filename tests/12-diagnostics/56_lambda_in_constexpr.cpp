// expect: 匿名函数不能出现在常量表达式内部
// forbid: may not appear inside of a constant expression
//
// lambda 出现在常量表达式里 —— 只在 C++17 以前是错（源码条件是
// !getLangOpts().CPlusPlus17），所以本文件加 -std=c++14。
// 对应诊断：err_lambda_in_constant_expression
//
// 2026-10-04 §18.8（决策 D-07 = 匿名函数）：期望值里原本记的是
//   「lambda 表达式不能出现在常量表达式内部」—— 那是**旧行为**。
enum E { X = []{ return 0; }() };
