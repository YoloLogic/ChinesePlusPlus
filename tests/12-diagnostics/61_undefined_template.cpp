// expect: 隐式实例化了未定义的模板（类型名） 'S<int>'
// forbid: instantiation of undefined template
//
// 用了只声明没定义（也不完整）的模板。同一个用例顺带覆盖
// note_template_decl_here（已翻：模板在此声明）。
// 对应诊断：err_template_instantiate_undefined
template<class T> struct S;
S<int> s;
