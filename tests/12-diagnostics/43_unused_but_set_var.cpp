// expect: 变量（变量名） '甲' 被赋值但未被使用
// forbid: set but not used
//
// 变量赋了值但没再用（本文件单独加 -Wall）。
// 兄弟条目：warn_unused_but_set_variable ——「形参」版早就翻了，变量版一直漏着，
// 于是同一句话在两种情况下中英并排。C1 补的就是这一类洞。
// 对应诊断：warn_unused_but_set_variable
整数 f() { 整数 甲 = 0; 甲 = 1; 返回 0; }
