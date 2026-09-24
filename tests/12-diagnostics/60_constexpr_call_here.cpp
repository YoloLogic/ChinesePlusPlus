// expect: 在调用（表达式） 'g(1)' 时
// forbid: in call to
//
// 常量求值失败时打印的调用栈。本文件加 -std=c++14。
// 对应诊断：note_constexpr_call_here
constexpr int g(int x) { return x / 0; }
constexpr int f() { return g(1); }
constexpr int y = f();
