// expect: 声明列表末尾缺少 ';'
// forbid: at end of declaration list
//
// 成员声明列表末尾少了分号。与 err_expected_semi_declaration
// （已翻：声明末尾缺少 ';'）是兄弟 —— 那句早就翻了，这句一直漏着。
// 对应诊断：err_expected_semi_decl_list
结构 甲 { 整数 乙 = 1 }
