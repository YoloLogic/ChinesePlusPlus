// expect: 多字符字符常量
// forbid: multicharacter character literal
//
// 英文写法 `'ab'`（两个 ASCII 字节）放进 `char` 字面量是**多字符常量**：
// 实现定义，clang 只**警告**（-Wmultichar，默认开）⇒ 这个文件仍然编得过。
// 对照：汉字 `'中'` 在 UTF-8 里是 **3 个字节**，`char` 放不下 ⇒ **报错**
// （见 81_char_literal_too_large.cpp）。
// 台账「五、观察到的现象」原先记的是"未验证英文 `'ab'` 是否同样报错"——
// 答案：不一样，一个是警告、一个是错误。
整数 甲 = 'ab';
整数 主函数() { 返回 甲; }
