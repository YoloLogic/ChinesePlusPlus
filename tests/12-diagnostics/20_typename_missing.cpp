// expect: 依赖类型名（名字） 'T::某名字' 之前缺少（关键字） 类型名
// forbid: missing 'typename' prior to
//
// 依赖名前面漏了 typename。
// 这一句在 clang 里有三个变体（错误 / 扩展警告 / 兼容性警告），正文开头一样，
// 中文表里三个一起翻 —— 否则用户会在同一句话上看到中英混排。
// 实测：必须用 -std=c++17 才会报 —— C++20 起隐式 typename 合法，警告根本不触发。
// 触发的 ID 正是 compat_pre_cxx20_implicit_typename（"pre cxx20" 名副其实）。
// 这里断言的是三个变体共有的前缀。
模板 <类型名 T> 结构 盒子 { T::某名字 x; };
整数 main() { 盒子<整数> b; 返回 0; }
