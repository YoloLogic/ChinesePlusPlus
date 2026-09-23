//===--- 中文控制台.h — 让 Windows 控制台正确显示中文 ----------------------===//
//
//  为什么需要它
//    编译器把中文字符串按 UTF-8 编进程序（clang 的默认行为，也是跨平台一致的
//    唯一选择）。而中文版 Windows 的控制台默认代码页是 GBK(936)，拿 GBK 去解释
//    UTF-8 字节 —— 中文就全变成乱码了。
//
//  用法（任何会打印中文的程序，在 main 开头调用一次）
//
//      #include "中文控制台.h"
//
//      整数 main() {
//        启用中文控制台();
//        printf("圆 面积 = %.4f\n", 3.14159265358979 * 4);
//        返回 0;
//      }
//
//  不依赖程序的两条替代办法
//    · 在终端里先执行 `chcp 65001`，再运行程序
//    · examples\.vscode\settings.json 已把 VS Code 集成终端配成 UTF-8，
//      所以在本项目的 VS Code 里即使忘了调用也不会乱码；
//      但双击 exe、或在小熊猫 C++ / CLion 里运行，就必须有这一行
//
//  本文件刻意只用 ASCII 关键字
//    这样它对任何编译器都成立（stock clang / MSVC / GCC 都能编），也就不会破坏
//    tools\zh_to_en.py 的"无锁定"验证链 —— 那个转换器只处理 .cpp，不翻头文件。
//    函数名仍用中文，所以调用点读起来依然是一句中文。
//===------------------------------------------------------------------------===//

#ifndef ZH_CONSOLE_H
#define ZH_CONSOLE_H

#ifdef _WIN32
#  include <windows.h>
#endif

inline void 启用中文控制台() {
#ifdef _WIN32
  // 输出改成 UTF-8。输入也一并设上，免得以后做交互式程序读中文参数时又乱码。
  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);
#endif
}

#endif // ZH_CONSOLE_H
