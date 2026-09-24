// expect: 未使用的函数（函数名） 'f'
// forbid: unused function
//
// 与「未使用的变量（变量名）」「未使用的形参（变量名）」句式一致。
// 本文件加 -Wall。
// 对应诊断：warn_unused_function
static void f(){}
int main(){ return 0; }
