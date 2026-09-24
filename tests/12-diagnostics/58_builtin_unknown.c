// expect: 使用了未知的内建（名字） '__builtin_zzz'
// forbid: use of unknown builtin
//
// C 模式下调用一个以 __builtin_ 开头、又没有声明的名字。
// （名字以 __builtin_ 开头时走 warn_builtin_unknown，不是普通的隐式声明警告。）
// 本文件加 -x c。
// 对应诊断：warn_builtin_unknown
int f(){ return __builtin_zzz(); }
