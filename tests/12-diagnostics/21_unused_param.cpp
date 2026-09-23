// expect: 未使用的形参 'a'
// expect: 形参 'b' 被赋值但未被使用
// forbid: unused parameter
// forbid: set but not used
//
// 形参没用 / 形参赋了值但没用（本文件加 -Wall -Wextra）。
// 这两条是真实代码里出现频率最高的警告之一。
// 对应诊断：warn_unused_parameter / warn_unused_but_set_parameter
整数 f(整数 a) { 返回 1; }
整数 g(整数 b) { b = 2; 返回 3; }
整数 main() { 返回 f(1) + g(2); }
