// expect: 这里要求实例化静态数据成员（成员名） 'S<NoDef>::v'
// forbid: in instantiation of static data member
//
// 静态数据成员的初始化式里出错，带出实例化位置。
// 对应诊断：note_template_static_data_member_def_here
template<class T> struct S { static T v; };
template<class T> T S<T>::v;
struct NoDef { NoDef() = delete; };
NoDef x = S<NoDef>::v;
