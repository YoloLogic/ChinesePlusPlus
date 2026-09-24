// 单个 int 形参：clang 给的是 warning（warn_main_one_arg），不是 error。
// 用来和英文版 parity_one_arg_en.cpp 对拍 —— 判据是"与 main 行为完全一致"，
// 而不是我猜的严重级别。
整数 主函数(整数 甲) { 返回 0; }
