// expect: 使用了未声明的标识符（名字） '甲'
// forbid: use of undeclared identifier
//
// 用了没声明过的变量。
// 注意：这里最容易踩的坑是「返回甲」被切成一个标识符（见 tests\09-diagnostics）。
// 对应诊断：err_undeclared_var_use
整数 main() { 返回 甲; }
