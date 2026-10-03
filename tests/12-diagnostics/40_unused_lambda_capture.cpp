// expect: （变量名） 'x' 这个匿名函数捕获 未被使用
// forbid: lambda capture
//
// lambda 捕获了但没用到
// 对应诊断：warn_unused_lambda_capture
//
// 2026-10-04 §18.8（决策 D-07 = 匿名函数）：期望值里原本记的是
//   「（变量名） 'x' 这个 lambda 捕获 未被使用」
// —— 那是**旧行为**（诊断表里 lambda 一直没译）。按 D-07 把全表 lambda
// 译成 匿名函数 之后，正文变成上面那一行（诊断仍是 warn_unused_lambda_capture）。
int main() { int x = 1; auto f = [x] { return 0; }; return f(); }
