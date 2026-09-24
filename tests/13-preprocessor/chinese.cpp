// All-Chinese counterpart of english.cpp.
//
// Every directive here is the Chinese spelling. The C++ body is deliberately
// kept in the SAME (English) keyword spelling as english.cpp, so that the
// byte-for-byte comparison of preprocessed output isolates ONE variable: the
// directive spelling. (Keyword spelling is a separate axis, covered by
// tests\01-keywords and tests\06-parity.)
#include "inc_a.h"

#定义 VALUE 2
#取消定义 VALUE
#定义 VALUE 3

#如果 VALUE == 1
#  定义 PICK 10
#否则若 VALUE == 2
#  定义 PICK 20
#否则若已定义 NEVER_DEFINED
#  定义 PICK 30
#否则若未定义 NEVER_DEFINED
#  定义 PICK 40
#否则
#  定义 PICK 50
#结束如果

#如果已定义 VALUE
#  定义 A 1
#否则
#  定义 A 0
#结束如果

#如果未定义 NOPE
#  定义 B 1
#否则
#  定义 B 0
#结束如果

#如果 defined(VALUE) && VALUE == 3
#  定义 C 1
#否则
#  定义 C 0
#结束如果

#包含 "inc_b.h"

int main() {
  return (PICK == 40 && A == 1 && B == 1 && C == 1 &&
          FROM_HEADER == 7 && FROM_B == 11) ? 0 : 1;
}
