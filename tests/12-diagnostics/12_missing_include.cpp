// expect: 找不到文件（名字） '这个头文件不存在.h'
// forbid: file not found
//
// 包含了一个不存在的头文件（拼错名字 / 忘了装依赖）。
// 注意前缀仍然是 fatal error:（前缀故意不翻，见 docs\诊断汉化\诊断汉化清单.md）。
// 对应诊断：err_pp_file_not_found
#include "这个头文件不存在.h"
整数 main() { 返回 0; }
