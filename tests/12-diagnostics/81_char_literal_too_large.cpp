// expect: 字符对于所在的字符字面量类型来说太大
// forbid: character too large for enclosing character literal type
//
// 汉字在 UTF-8 里是 3 个字节，`char` 字面量放不下 ⇒ **报错**。
// 对照 80_multichar_constant.cpp：英文 `'ab'` 只有 2 个字节，是"多字符常量"⇒ 只警告。
// 要装下一个汉字得用 `u8'中'`/`u'中'`/`U'中'` 或宽字符类型（见 docs\使用说明.md）。
整数 乙 = '中';
整数 主函数() { 返回 乙; }
