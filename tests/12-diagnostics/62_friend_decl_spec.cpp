// expect: （关键字） 'static' 不能用在友元声明里
// forbid: is invalid in friend declarations
//
// 友元声明里写了存储类说明符。
// 对应诊断：err_friend_decl_spec
struct A { friend static int x; };
