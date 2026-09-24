// Guard: a Chinese directive spelling is still an ordinary identifier in
// ordinary C++ code.
//
// `getPPKeywordID()` has no call site in Lexer.cpp -- every caller is behind a
// '#' (or in module context) -- so naming a variable `包含` / `定义` / `错误`
// must keep working. This test exists because that claim is easy to assert and
// easy to get wrong.
//
// The values are checked at run time AND in a static_assert, so a silent
// mis-parse cannot pass. `常量 整数` (const int) so the static_assert is a valid
// constant expression -- a plain non-const global would not be.
常量 整数 包含 = 1;
常量 整数 定义 = 2;
常量 整数 错误 = 3;
常量 整数 警告 = 4;
常量 整数 断言 = 5;

static_assert(包含 == 1);
static_assert(定义 == 2);
static_assert(断言 == 5);

整数 main() {
  返回 (包含 == 1 && 定义 == 2 && 错误 == 3 && 警告 == 4 && 断言 == 5) ? 0 : 1;
}
