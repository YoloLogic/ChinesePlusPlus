// expect: 缺少 表达式
// forbid: expected expression
//
// 该有表达式的地方没有。err_expected（"expected %0"）早就翻了，但这一条
//【没有占位符】，是独立 ID，不是同一条的另一个参数值。
// 对应诊断：err_expected_expression
整数 甲 = ;
