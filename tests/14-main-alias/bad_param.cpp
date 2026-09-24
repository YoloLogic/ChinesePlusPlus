// main 的合法参数形式只有 ()、 (int,char**)、 (int,char**,char**)。
// 第一个形参的类型必须是 int —— 写 double 必须是 error。
//
// 注意：单个 int 形参（整数 主函数(整数 甲)）在 clang 里只是 **warning**
// （warn_main_one_arg），不是 error。所以这里用【类型错】而不是【个数错】，
// 才能得到一个确定的 error 来断言。个数那条由 check.ps1 用"与英文对拍"覆盖。
整数 主函数(双精度 甲) { 返回 0; }
