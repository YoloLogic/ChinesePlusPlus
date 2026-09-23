// expect: （变量名） 'x' 这个 lambda 捕获 未被使用
// forbid: lambda capture
//
// lambda 捕获了但没用到
// 对应诊断：warn_unused_lambda_capture
int main() { int x = 1; auto f = [x] { return 0; }; return f(); }
