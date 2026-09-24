// Chinese directive spelling -- must produce the SAME diagnostic text as
// elifdef_en.cpp. If these two ever diverge, the directive spelling policy has
// regressed to "echo what the user typed", which contradicts the keyword policy.
#define A 1
#如果 0
#否则若已定义 A
#结束如果
int x;
