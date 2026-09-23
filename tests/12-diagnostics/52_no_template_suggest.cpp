// expect: 没有名为（名字） 'Boxx' 的模板；你是不是想写（名字） 'Box'？
// forbid: did you mean
//
// "no template named" 的建议变体。
// 对应诊断：err_no_template_suggest
模板<类型名 T> 结构 Box { };
void f() { Boxx<整数> 甲; }
