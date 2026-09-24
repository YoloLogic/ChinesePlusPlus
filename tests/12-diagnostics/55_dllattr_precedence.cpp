// expect: （属性名） 'dllexport' 被忽略；（属性名） 'exclude_from_explicit_instantiation' 优先
// forbid: takes precedence
//
// 两个属性抢同一个声明时，一个被忽略。未覆盖排名第 2（49 次）。
// 对应诊断：warn_dllattr_ignored_exclusion_takes_precedence
__attribute__((exclude_from_explicit_instantiation)) __declspec(dllexport) void f();
