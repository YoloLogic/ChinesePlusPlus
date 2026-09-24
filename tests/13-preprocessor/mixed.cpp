// Mixed English + Chinese directive spellings in ONE file, inside ONE
// conditional chain. This is the property the user asked for explicitly:
//
//     "我需要可以混合使用且不影响"
//
// Both spellings resolve to the same tok::pp_* enum, so HandleDirective cannot
// tell them apart -- there is no mode, no flag, and no per-file restriction.
// Chinese keywords are used for the C++ body so this file is end-to-end Chinese
// apart from the directives that are deliberately left English.
#include "inc_a.h"

#定义 LEVEL 2

#if LEVEL == 1
#  定义 PICK 10
#否则若 LEVEL == 2
#  定义 PICK 20
#否则
#  定义 PICK 30
#结束如果

#如果已定义 LEVEL
#  定义 HAVE 1
#else
#  定义 HAVE 0
#endif

整数 main() {
  返回 (PICK == 20 && HAVE == 1 && FROM_HEADER == 7) ? 0 : 1;
}
