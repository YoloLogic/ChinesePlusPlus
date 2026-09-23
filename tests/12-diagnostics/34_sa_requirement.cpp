// expect: 静态断言失败，因为不满足要求（表达式） 'sizeof(int) > 99'
// forbid: static assertion failed due to requirement
//
// 静态断言不满足（%select 的空分支）
// 对应诊断：err_static_assert_requirement_failed
static_assert(sizeof(int) > 99);
int main() { return 0; }
