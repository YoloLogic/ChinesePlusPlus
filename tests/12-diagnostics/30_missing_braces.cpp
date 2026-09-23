// expect: 建议给子对象的初始化加上花括号
// forbid: suggest braces
//
// 嵌套数组初始化没写内层花括号
// 对应诊断：warn_missing_braces
int a[2][2] = {1, 2, 3, 4};
int main() { return a[0][0]; }
