// expect: 没有与（函数名） 'f' 匹配的函数
// forbid: no matching function for call to
// expect: no known conversion from
//
// 重载决议失败。这里一次验证两件事：
//   1) 主错误 err_ovl_no_viable_function_in_call 已汉化
//   2) 候选函数的 note（note_ovl_candidate_bad_conv）【没有】汉化，
//      仍然原样显示英文 —— 这就是「查不到就回退英文」的证据。
整数 f(整数);
整数 f(双精度);
整数 main() { 返回 f("x"); }
