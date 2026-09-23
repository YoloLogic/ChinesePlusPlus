// expect: 模板在此声明
// expect: 这里要求实例化类模板（类型名） '盒子<int>'
// forbid: template is declared here
// forbid: in instantiation of template class
//
// 模板出错时最常看到的两条 note：
//   1) 模板参数给少了 -> "template is declared here"
//   2) 类模板内部出错 -> "in instantiation of template class ... requested here"
// 注意 %q0 保留了限定名（盒子<int> 而不是 盒子）。
// 对应诊断：note_template_decl_here / note_template_class_instantiation_here
模板 <类型名 T, 类型名 U> 结构 甲 {};
甲<整数> a;

模板 <类型名 T> 结构 盒子 { 类型名 T::某类型 成员; };
整数 main() { 盒子<整数> b; 返回 0; }
