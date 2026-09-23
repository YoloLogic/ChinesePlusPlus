// expect: 未使用的私有字段（成员名） 'x'
// forbid: private field
//
// 私有字段没被用到
// 对应诊断：warn_unused_private_field
class A { private: int x; };
int main() { return 0; }
