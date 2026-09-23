// expect: 所有声明都必须有类型说明符
// forbid: a type specifier is required
//
// 声明里没写类型（这里连 constexpr 也没给类型）。
// 对应诊断：err_missing_type_specifier
整数 main() { constexpr 甲 = 1; 返回 甲; }
