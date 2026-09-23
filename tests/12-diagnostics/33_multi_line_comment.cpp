// expect: 多行的 // 注释
// forbid: multi-line // comment
//
// 行尾续行符把 // 注释拉成了多行
// 对应诊断：ext_multi_line_line_comment
// 第一行 \
   还是同一个注释
int main() { return 0; }
