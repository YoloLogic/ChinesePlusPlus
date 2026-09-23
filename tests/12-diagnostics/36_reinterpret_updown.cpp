// expect: 在 向下转换 时，请用（关键字） 静态转换 正确调整指针
// forbid: while downcasting
//
// reinterpret_cast 从虚基类向下转（%select 的 downcasting 分支）
// 对应诊断：note_reinterpret_updowncast_use_static
struct A { int x; };
struct B : virtual A {};
int main() { B b; A *p = &b; B *q = reinterpret_cast<B *>(p); return q->x; }
