// expect: 二元表达式的运算对象无效（表达式 和 表达式）（'甲' 和 '甲'）
// forbid: invalid operands to binary expression
//
// 两个结构体相加，而它没有定义 operator+。
// 对应诊断：err_typecheck_invalid_operands
结构 甲 { 整数 x; };
整数 main() { 甲 a, b; 返回 a + b; }
