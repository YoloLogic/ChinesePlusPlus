// expect: 重写函数的异常规范比基类版本更宽松
// expect: 被重写的虚函数在这里
// forbid: more lax than base version
// forbid: overridden virtual function is here
//
// 重写函数的异常规范更宽松 —— 警告和它配对的 note 在源码里紧挨着发射，
// 必须一起翻，否则中文 warning 顶着英文 note。
// 本文件加 -Wall（实测默认也出，-Wmicrosoft-exception-spec）。
// 对应诊断：err_override_exception_spec / ext_override_exception_spec
//           note_overridden_virtual_function
struct B { virtual void f() noexcept; };
struct D : B { void f(); };
