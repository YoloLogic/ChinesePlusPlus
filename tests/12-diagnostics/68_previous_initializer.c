// expect: 上一次初始化在这里
// forbid: previous initialization
//
// 同一个子对象被初始化两次。本文件加 -x c -Winitializer-overrides。
// 对应诊断：note_previous_initializer
struct S { int a; };
struct S s = { .a = 1, .a = 2 };
