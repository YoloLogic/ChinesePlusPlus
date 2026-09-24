// expect: 构造函数不能被重新声明
// expect: 析构函数不能被重新声明
// expect: 转换函数不能被重新声明
// forbid: cannot be redeclared
//
// 同一个 if/else 分支里的三条（SemaDecl.cpp:4165-4172）。C1 只补了 else 那条
//（err_member_redeclared，见 53），这里把三条补齐 —— 只翻一条的话，同一个
// 类别的错会一句中文一句英文。
// 对应诊断：err_constructor_redeclared / err_destructor_redeclared /
//           err_conv_function_redeclared
struct C { C(); C(); };
struct D { ~D(); ~D(); };
struct F { operator int(); operator int(); };
