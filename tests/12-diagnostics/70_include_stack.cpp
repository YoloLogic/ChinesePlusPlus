// expect: 包含自
// forbid: In file included from
//
// 包含链的头一行。同样是没有诊断 ID 的手工正文（TextDiagnostic.cpp:959），
// 中文由同一个开关门控。
// 对应位置：clang/lib/Frontend/TextDiagnostic.cpp:957
#include "70_included.h"
int main(){ return 0; }
