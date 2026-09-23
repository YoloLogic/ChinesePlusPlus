// expect: 未知的属性（属性名） 'noretun' 被忽略；你是不是想写（属性名） 'noreturn'？
// forbid: did you mean
//
// 与 warn_unknown_attribute_ignored 是兄弟（那句早就翻了）。
// 本文件加 -Wall。
// 对应诊断：warn_unknown_attribute_ignored_suggestion
void f() __attribute__((noretun));
