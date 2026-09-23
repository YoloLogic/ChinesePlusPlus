// expect: （类型名） 'S' 中没有名为（名字） 'valuetype' 的类型；你是不是想写（类型名） 'value_type'？
// forbid: did you mean
//
// 与 err_typename_nested_not_found 是兄弟（那句早就翻了）。
// 对应诊断：err_unknown_nested_typename_suggest
结构 S { 类型别名 整数 value_type; };
S::valuetype 甲;
