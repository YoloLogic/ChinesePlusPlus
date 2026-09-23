// 转译对照（中文版）：与 test_translit_en.cpp 语义完全等价。
// 二者应产出相同的 AST（token 拼写除外）。
//
// 比较方式：
//   clang++ -std=c++20 -Xclang -ast-dump -fsyntax-only test_translit_zh.cpp
//   clang++ -std=c++20 -Xclang -ast-dump -fsyntax-only test_translit_en.cpp

整数 甲 = 1;
整数 乙 = 2;

整数 相加(整数 左, 整数 右) {
    如果 (左 > 右) {
        返回 左 + 右;
    } 否则 {
        返回 左 - 右;
    }
}

整数 丙 = 相加(甲, 乙);
