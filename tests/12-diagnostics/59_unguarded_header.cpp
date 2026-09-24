// expect: 这个头文件没有包含守卫；建议用 #ifdef 守卫或者 #pragma once
// forbid: consider using #ifdef guards
//
// 同一个没有守卫的头被包含两次，重定义之后带出的建议。
// 对应诊断：note_use_ifdef_guards
#include "59_noguard.h"
#include "59_noguard.h"
int main(){ return 0; }
