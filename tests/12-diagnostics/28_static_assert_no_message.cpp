// expect: 不带消息的（关键字） 静态断言 是 C++17 扩展
// forbid: with no message
//
// static_assert 没写消息（C++17 扩展）
// 对应诊断：ext_cxx_static_assert_no_message
static_assert(true);
int main() { return 0; }
