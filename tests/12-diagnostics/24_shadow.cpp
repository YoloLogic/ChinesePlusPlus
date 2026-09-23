// expect: 上一次声明在这里
// forbid: previous declaration is here
//
// 内层变量遮蔽外层同名变量（本文件加 -Wshadow）。
// 主警告 warn_shadow 本批没翻，所以英文还在 —— 这正好演示"部分翻译"：
// 同一次编译里，中文 note 和英文 warning 并排出现，互不影响。
// 对应诊断：note_previous_declaration
整数 main() {
  整数 甲 = 1;
  { 整数 甲 = 2; }
  返回 甲;
}
