// expect: （名字） 'f' 已被弃用：用 g 代替
// forbid: is deprecated:
//
// 带消息的弃用。%1 是属性里的自由文本，中文表原样带过来（不给它标角色表）。
// 本文件加 -Wall。
// 对应诊断：warn_deprecated_message
__attribute__((deprecated("用 g 代替"))) void f();
void g(){ f(); }
