// English-only baseline for tests\13-preprocessor.
// Keep this file and chinese.cpp logically IDENTICAL: check.ps1 compares their
// preprocessed output byte for byte.
#include "inc_a.h"

#define VALUE 2
#undef VALUE
#define VALUE 3

#if VALUE == 1
#  define PICK 10
#elif VALUE == 2
#  define PICK 20
#elifdef NEVER_DEFINED
#  define PICK 30
#elifndef NEVER_DEFINED
#  define PICK 40
#else
#  define PICK 50
#endif

#ifdef VALUE
#  define A 1
#else
#  define A 0
#endif

#ifndef NOPE
#  define B 1
#else
#  define B 0
#endif

#if defined(VALUE) && VALUE == 3
#  define C 1
#else
#  define C 0
#endif

#include "inc_b.h"

int main() {
  return (PICK == 40 && A == 1 && B == 1 && C == 1 &&
          FROM_HEADER == 7 && FROM_B == 11) ? 0 : 1;
}
