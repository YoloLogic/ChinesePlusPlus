// expect: 这里要求实例化函数模板特化（函数名） 'g<整数>'
// forbid: in instantiation of function template specialization
//
// 函数模板内部出错时的实例化 note。
// 对应诊断：note_function_template_spec_here
模板 <类型名 T> 空型 g(T) { T::某名字 x; }
整数 main() { g(1); 返回 0; }
