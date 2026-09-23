// expect: 静态断言的表达式不是整型常量表达式
// expect: 在此声明
// forbid: is not an integral constant expression
// forbid: declared here
//
// 静态断言的表达式本身不是整型常量表达式 —— 与 err_static_assert_requirement_failed
// 是兄弟（一条说"要求不满足"，一条说"表达式不是常量"）。
// 同一个用例顺带覆盖 note_declared_at（英文 "declared here"）。
// 对应诊断：err_static_assert_expression_is_not_constant / note_declared_at
整数 甲 = 0;
静态断言(甲);
