// expect: '点' 中没有名为 'y' 的成员
// forbid: no member named
//
// 访问了结构里没有的成员。中文语序与英文相反（no B in A -> A 中没有 B），
// 这条同时验证「占位符可以换位置，但不能换参数」。
// 对应诊断：err_no_member
结构 点 { 整数 x; };
整数 main() { 点 p; p.y = 1; 返回 0; }
