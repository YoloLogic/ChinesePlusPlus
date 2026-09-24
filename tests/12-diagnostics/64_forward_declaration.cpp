// expect: （名字） 'A' 的前向声明
// forbid: forward declaration of
//
// 用了只有前向声明的类型来定义变量。
// 对应诊断：note_forward_declaration
struct A;
A a;
