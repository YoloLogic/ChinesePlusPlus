// expect: 缺少 '}'
// expect: 与这个 '{' 匹配
// forbid: expected '}'
// forbid: to match this
//
// 括号没配平：主错误 + 配对的 note 都汉化了。
// 对应诊断：err_expected / note_matching
整数 main() { 如果 (1) { 返回 0; }
