// expect: lambda 捕获列表里缺少变量名或（关键字） 自身
// forbid: expected variable name
//
// 捕获列表里写了一个不是变量名的东西。
// 对应诊断：err_expected_capture
void f(){ auto g = [1](){}; }
