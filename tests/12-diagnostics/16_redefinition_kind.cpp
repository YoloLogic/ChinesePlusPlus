// expect: '甲' 被重定义为另一种符号
// expect: 上一次定义在这里
// forbid: as different kind of symbol
//
// 变量名和函数名撞了 —— 同一条 note 在另一种错误下的用法。
// 对应诊断：err_redefinition_different_kind / note_previous_definition
整数 甲 = 1;
空型 甲() {}
