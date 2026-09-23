// expect: 转换函数不能转换成函数类型
// forbid: cannot convert to a function type
//
// 转换函数想转换成一个函数类型（同一份代码也会触发 err_conv_function_with_complex_decl）
// 对应诊断：err_conv_function_to_function
struct S { operator int()(); };
int main() { return 0; }
