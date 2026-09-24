// expect: 从宏 'BAD' 展开
// forbid: expanded from macro
//
// 宏展开里出了诊断，带出的回溯 note。这一条**没有诊断 ID** —— 它是
// DiagnosticRenderer.cpp 手工拼出来的正文，中文内联在那里、由
// -fno-chinese-diagnostics 那个开关同一个字段门控。
// 实测：7 个真实开源项目里这一条占了 799 条实例（57.2%），是真实代码
// 覆盖率上不去的第一大原因。
// 对应位置：clang/lib/Frontend/DiagnosticRenderer.cpp:445
#define BAD(x) ((x) + "字符串")
int a = BAD(1);
