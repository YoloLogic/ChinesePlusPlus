//===--- undef_debug.h - 抵消 Dev-C++ 自动加的 -D_DEBUG -----------------===//
//
//  背景
//  ----
//  小熊猫C++（Red Panda Dev-C++）在「生成调试信息」打开时，除了 -g3 之外还会
//  额外塞一个 -D_DEBUG。这个宏是 MSVC 的约定：它会让 MSVC 的 STL 头文件切到
//  「调试版 STL」，而调试版 STL 会引用调试版 C 运行库里的 _CrtDbgReport。
//
//  但 clang 在 MSVC 目标下默认链接的是【发行版】CRT（libcmt / libucrt），
//  里面没有 _CrtDbgReport，于是：
//
//      示例.o : error LNK2019: 无法解析的外部符号 _CrtDbgReport
//      示例.exe : fatal error LNK1120: 1 个无法解析的外部命令
//      clang++: error: linker command failed with exit code 1120
//
//  CLion 之所以没事，是因为 CMake 会同时传 -D_DEBUG -D_DLL -D_MT
//  -Xclang --dependent-lib=msvcrtd，把调试版 CRT 一起链进去；Dev-C++ 只抄了
//  -D_DEBUG，没抄 CRT 选择，所以对不上。
//
//  为什么这个头能生效
//  ----------------
//  -D_DEBUG 由 Dev-C++ 追加在自定义编译参数【之后】，所以 -U_DEBUG 压不住它。
//  但 -include 的文件是在「所有命令行宏处理完成之后、源文件内容之前」展开的，
//  在这里 #undef 就能赶在 <vector> 等标准库头文件之前把 _DEBUG 去掉。
//
//  代价：失去 MSVC 的调试版 STL 检查（迭代器检查等）。对本项目无影响。
//
//===----------------------------------------------------------------------===//

#undef _DEBUG
