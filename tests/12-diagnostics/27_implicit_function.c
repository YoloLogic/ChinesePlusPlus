// expect: 调用了未声明的函数（函数名） 'foo'；ISO C99 及以后的版本不支持隐式函数声明
// forbid: call to undeclared function
//
// C 模式下调用了没声明的函数
// 对应诊断：ext_implicit_function_decl_c99
int main(void) { return foo(); }
