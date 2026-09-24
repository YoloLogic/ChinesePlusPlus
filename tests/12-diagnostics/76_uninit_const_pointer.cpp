// expect: 变量（变量名） 'x' 在这里作为常量指针实参传入时尚未初始化
// forbid: is uninitialized when passed as a const pointer argument
//
// 本文件加 -Wall。
// 对应诊断：warn_uninit_const_pointer
void f(const int *);
void g(){ int x; f(&x); }
