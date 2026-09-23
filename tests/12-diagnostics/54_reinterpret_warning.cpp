// expect: 'reinterpret_cast' 到类（类型） 'B *'，来源是它的 虚基类（类型） 'A *'，行为与 'static_cast' 不同
// forbid: behaves differently from
//
// reinterpret_cast 在类与虚基类之间转（%select 的 downcasting 分支）。
// 源码与 36_reinterpret_updown.cpp 相同：两条诊断在 SemaCast.cpp 里紧挨着发射
// （1136 / 1139），只翻后一条就会"中文 note 顶着英文 warning"。
// 本文件加 -Wall。
// 对应诊断：warn_reinterpret_different_from_static
struct A { int x; };
struct B : virtual A {};
int main() { B b; A *p = &b; B *q = reinterpret_cast<B *>(p); return q->x; }
