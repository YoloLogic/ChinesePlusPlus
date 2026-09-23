// expect: 顶层声明符之后缺少 ';'
// forbid: after top level declarator
//
// 两个声明之间漏了分号。
// 对应诊断：err_invalid_token_after_toplevel_declarator
整数 x 整数 y;
