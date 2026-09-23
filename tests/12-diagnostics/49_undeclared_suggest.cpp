// expect: 使用了未声明的标识符（名字） 'valu'；你是不是想写（名字） 'value'？
// forbid: did you mean
//
// 与 err_undeclared_var_use 是兄弟（那句早就翻了）。
// 对应诊断：err_undeclared_var_use_suggest
整数 value = 0;
整数 main() { 返回 valu; }
