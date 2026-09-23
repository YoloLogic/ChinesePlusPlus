// expect: 重定义（名字） '甲'
// expect: 上一次定义在这里
// forbid: redefinition of
// forbid: previous definition is here
//
// 同名变量定义两次：主错误 + 配对的 note 都汉化。
// 对应诊断：err_redefinition / note_previous_definition
整数 甲 = 1;
整数 甲 = 2;
