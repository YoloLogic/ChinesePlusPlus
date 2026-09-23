// 中文 C++ 示例项目
//
// 用 CLion 打开本目录（即 CMakeLists.txt 所在的文件夹），
// CLion 会自动调用 E:/Chinese++/build/Release/bin/clang++.exe 来编译。
//
// 注意：本文件必须保存为 UTF-8。

#include <cstdio>
#include <vector>
#include <windows.h>

类型 学生 {
公开:
    常量 字符* 姓名;
    整数 分数;

    学生(常量 字符* 姓名值, 整数 分数值) : 姓名(姓名值), 分数(分数值) {}

    布尔 及格() 常量 { 返回 分数 >= 60; }
};

整数 main() {
    // 让控制台按 UTF-8 解码，否则中文会显示成乱码。
    // 原因：本编译器用 UTF-8 作执行字符集，程序里的中文字符串是 UTF-8 字节，
    //       而中文 Windows 的控制台默认按 GBK(936) 解码。
    SetConsoleOutputCP(CP_UTF8);

    std::vector<学生> 班级 = {
        学生("甲", 85),
        学生("乙", 42),
        学生("丙", 67),
    };

    整数 及格人数 = 0;
    对于 (自动& 某人 : 班级) {
        如果 (某人.及格()) {
            ++及格人数;
            std::printf("%s 及格，分数 %d\n", 某人.姓名, 某人.分数);
        } 否则 {
            std::printf("%s 不及格，分数 %d\n", 某人.姓名, 某人.分数);
        }
    }

    std::printf("共 %d 人及格\n", 及格人数);
    返回 0;
}
