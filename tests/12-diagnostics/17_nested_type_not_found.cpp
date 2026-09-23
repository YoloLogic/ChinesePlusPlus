// expect: '点' 中没有名为 '值' 的类型
// forbid: no type named
//
// 访问了结构里没有的嵌套类型。句式与 04_no_member 的「成员」版保持一致。
// 对应诊断：err_typename_nested_not_found
结构 点 { 整数 x; };
点::值 v;
