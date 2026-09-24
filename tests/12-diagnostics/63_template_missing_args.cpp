// expect: 使用类模板（名字） 'S' 需要模板实参
// forbid: requires template arguments
//
// 用了类模板却没给模板实参。本文件加 -std=c++14
//（C++17 起 CTAD 会把它变成合法）。
// 对应诊断：err_template_missing_args
template<class T> struct S {};
S s;
