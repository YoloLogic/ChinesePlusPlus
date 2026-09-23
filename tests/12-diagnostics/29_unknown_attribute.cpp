// expect: 未知的属性（属性名） 'nonsense' 被忽略
// forbid: unknown attribute
//
// 用了编译器不认识的属性
// 对应诊断：warn_unknown_attribute_ignored
__attribute__((nonsense)) int x;
int main() { return x; }
