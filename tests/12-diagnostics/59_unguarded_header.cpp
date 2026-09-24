// expect: 这个头文件没有包含守卫；建议用 #如果已定义 守卫或者 #pragma once
// forbid: consider using #ifdef guards
//
// 同一个没有守卫的头被包含两次，重定义之后带出的建议。
// 对应诊断：note_use_ifdef_guards
//
// ⚠ 2026-09-24：`#ifdef` → `#如果已定义`，`#pragma once` 保持英文。
//   按「诊断正文里的指令拼写恒为中文」的方针（与关键字方针一致：写英文
//   static_assert 也输出 静态断言）。`#pragma` 的子名字层有意不译，见
//   docs\预处理指令汉化\预处理指令汉化.md 第七节。
#include "59_noguard.h"
#include "59_noguard.h"
int main(){ return 0; }
