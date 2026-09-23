// expect: 声明末尾缺少 ';'
// forbid: expected ';' at end of declaration
//
// 声明末尾忘了分号 —— 初学者第一个会撞到的错误。
// 对应诊断：err_expected_semi_declaration
整数 main() { 整数 甲 = 1 返回 0; }
