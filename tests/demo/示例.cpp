// 最小中文示例：编译并运行它，确认你的环境可用。
//
// 编译（在 cmd 或 PowerShell 里执行）：
//   E:\Chinese++\build\Release\bin\clang++.exe -std=c++20 示例.cpp -o 示例.exe
//   示例.exe

#include <cstdio>

整数 求平方(整数 甲) {
    返回 甲 * 甲;
}

整数 main() {
    对于 (整数 甲 = 1; 甲 <= 5; ++甲) {
        如果 (甲 == 3) { 跳过; }
        std::printf("%d 的平方是 %d\n", 甲, 求平方(甲));
    }
    返回 0;
}
