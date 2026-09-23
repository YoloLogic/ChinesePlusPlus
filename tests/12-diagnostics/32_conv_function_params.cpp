// expect: 转换函数不能带有任何形参
// forbid: cannot have any parameters
//
// 转换函数带了形参
// 对应诊断：err_conv_function_with_params
struct S { operator int(int); };
int main() { return 0; }
