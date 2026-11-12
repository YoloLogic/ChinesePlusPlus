/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */

/* ISO C1x Unicode utilities
 * Based on ISO/IEC SC22/WG14 9899 TR 19769 (SC22 N1326)
 *
 *  THIS SOFTWARE IS NOT COPYRIGHTED
 *
 *  This source code is offered for use in the public domain. You may
 *  use, modify or distribute it freely.
 *
 *  This code is distributed in the hope that it will be useful but
 *  WITHOUT ANY WARRANTY. ALL WARRANTIES, EXPRESS OR IMPLIED ARE HEREBY
 *  DISCLAIMED. This includes but is not limited to warranties of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 *  Date: 2011-09-27
 */

#ifndef __UCHAR_H
#define __UCHAR_H

#include <stddef.h>	/* size_t */
#include <stdint.h>	/* uint_leastXX_t */
#include <wchar.h>	/* mbstate_t */

/* Chinese++ §18.55 -- vendored patch.
   The stock condition below typedefs char16_t/char32_t whenever
   __GXX_EXPERIMENTAL_CXX0X__ is absent. clang defines __GNUC__ but NOT
   __GXX_EXPERIMENTAL_CXX0X__, so the condition held in C++ mode and the
   typedefs collided with the language's own keywords:
       error: cannot combine with previous 'type-name' declaration specifier
   In C++11 and later char16_t/char32_t are builtin, so only typedef them
   for C. (C still needs them: they are not C keywords.) */
#if !defined(__cplusplus)
typedef uint_least16_t char16_t;
typedef uint_least32_t char32_t;
#endif

#ifndef __STDC_UTF_16__
#define __STDC_UTF_16__ 1
#endif

#ifndef __STDC_UTF_32__
#define __STDC_UTF_32__ 1
#endif

#ifdef __cplusplus
extern "C" {
#endif

size_t mbrtoc16 (char16_t *__restrict__ pc16,
		 const char *__restrict__ s,
		 size_t n,
		 mbstate_t *__restrict__ ps);

size_t c16rtomb (char *__restrict__ s,
		 char16_t c16,
		 mbstate_t *__restrict__ ps);

size_t mbrtoc32 (char32_t *__restrict__ pc32,
		 const char *__restrict__ s,
		 size_t n,
		 mbstate_t *__restrict__ ps);

size_t c32rtomb (char *__restrict__ s,
		 char32_t c32,
		 mbstate_t *__restrict__ ps);

#ifdef __cplusplus
}
#endif

#endif /* __UCHAR_H */

