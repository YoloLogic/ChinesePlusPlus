// expect: （类型） 'A' 不是 可平凡重定位类型
// expect: （名字） 'A' 在此定义
// forbid: is not trivially relocatable
// forbid: defined here
//
// 类型不满足 trivially relocatable（同时验证 note_unsatisfied_trait 与 note_defined_here）
// 对应诊断：note_unsatisfied_trait / note_defined_here
struct A { int &r; };
static_assert(__builtin_is_cpp_trivially_relocatable(A));
int main() { return 0; }
