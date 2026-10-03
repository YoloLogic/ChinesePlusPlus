// expect: 匿名函数捕获列表里缺少变量名或（关键字） 自身
// forbid: expected variable name
//
// 捕获列表里写了一个不是变量名的东西。
// 对应诊断：err_expected_capture
//
// 2026-10-04 §18.8（决策 D-07 = 匿名函数）：期望值里原本记的是
//   「lambda 捕获列表里缺少变量名或（关键字） 自身」—— 那是**旧行为**。
void f(){ auto g = [1](){}; }
