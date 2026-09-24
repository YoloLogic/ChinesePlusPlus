// expect: 转换函数的声明中不能指定返回类型的任何部分；请用 类型别名 声明到（类型） 'int ()' 的转换
// forbid: cannot specify any part of a return type
//
// 转换函数的声明里写了返回类型（%select 的分支 1）
// 对应诊断：err_conv_function_with_complex_decl
struct S { operator int()(); };
int main() { return 0; }
