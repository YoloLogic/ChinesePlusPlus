// expect: 被下标访问的值不是数组、指针或向量
// forbid: subscripted value is not an array
//
// 对一个整数用了下标。
// 对应诊断：err_typecheck_subscript_value
整数 main() { 整数 x = 1; 返回 x[0]; }
