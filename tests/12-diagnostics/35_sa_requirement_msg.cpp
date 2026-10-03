// expect: 静态断言失败，因为不满足要求（表达式） '大小(整数) > 99'：整数太小了
// forbid: static assertion failed due to requirement
//
// 静态断言不满足（%select 的带消息分支）
// 对应诊断：err_static_assert_requirement_failed
static_assert(sizeof(int) > 99, "整数太小了");
int main() { return 0; }
