// expect: （名字） 'f' 已被弃用
// expect: （名字） 'f' 在此被明确标记为已弃用
// forbid: is deprecated
//
// 弃用属性。真实项目语料里这一族占了近三分之一（MSVC CRT 大量使用）。
// 本文件加 -Wall。同一个用例覆盖两条：warn_deprecated + note_availability_specified_here。
// 对应诊断：warn_deprecated / note_availability_specified_here
__attribute__((deprecated)) void f();
void g(){ f(); }
