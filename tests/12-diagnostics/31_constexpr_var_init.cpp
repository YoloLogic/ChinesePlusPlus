// expect: 常量表达式 变量（变量名） 'P' 必须用编译期常量初始化
// forbid: must be initialized by a constant expression
//
// 常量表达式变量用了非常量的初值（关键字与概念名撞名的那条）
// 对应诊断：err_constexpr_var_requires_const_init
int f();
constexpr int P = f();
int main() { return P; }
