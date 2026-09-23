// ============================================================================
//  中文 C++ 示例：关键字 vs 名字 —— 为什么 std 不是关键字
//
//  关键字（language keyword）：语言的一部分，编译器认识，一共 86 个，
//                              全部有中文别名（见 docs\使用说明.md 第五节）。
//  名字（identifier）：别人起的一个普通标识符。标准库里的 std / printf /
//                              vector / string，以及程序入口 main，都属于这一类。
//
//  编译运行（小熊猫C++ 里直接按 F11）：
//    E:\Chinese++\build\Release\bin\clang++.exe -std=c++20 keywords_vs_names.cpp -o k.cpp.exe
//
//  本文件必须保存为 UTF-8。
// ============================================================================

#include <cstdio>
#include <vector>
#include <windows.h>

// 「名域」是关键字（= namespace）；「我的名域」这个名字是我们自己起的。
名域 我的名域 {
    整数 甲 = 100;

    类型 盒子 {                      // 「类型」也是关键字（= class）
    公开:
        整数 值 = 0;
    };
}

// 「使用」是关键字（= using）；「std」是库里的名字，写不出中文形式。
使用 名域 std;

整数 main() {
    SetConsoleOutputCP(CP_UTF8);

    std::printf("=== 关键字 vs 名字 ===\n\n");

    // 写全名：std 是名域的名字，:: 是作用域解析运算符（也不是关键字）
    std::printf("① 写全名 std::vector<整数>：%d 个元素\n",
                静态转换<整数>(std::vector<整数>{1, 2, 3}.size()));

    // 上面「使用 名域 std;」之后，就能省掉 std::
    vector<整数> 数 = {3, 1, 2};
    printf("② 省掉 std:: 直接写 vector：%d 个元素\n", 静态转换<整数>(数.size()));

    // 自己起的名域 + 自己起的类型名，一样用 ::
    我的名域::盒子 盒;
    盒.值 = 我的名域::甲;
    std::printf("③ 自己的名域 我的名域::盒子.值 = %d\n", 盒.值);

    std::printf("\n结论：\n");
    std::printf("  关键字  -> 语言的一部分，有中文别名（名域 / 使用 / 类型 …）\n");
    std::printf("  名字    -> 别人起的标识符，保持原样（std / vector / printf / main）\n");

    返回 0;
}
