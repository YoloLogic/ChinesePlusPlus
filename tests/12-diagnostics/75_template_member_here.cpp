// expect: 这里要求实例化成员函数（函数名） 'S<整数>::f'
// forbid: in instantiation of member function
//
// 与已翻的三条模板 note 句式一致。
// 对应诊断：note_template_member_function_here
template<class T> struct S { void f(); };
template<class T> void S<T>::f() { T::nope = 1; }
template struct S<int>;
