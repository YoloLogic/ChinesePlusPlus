// ============================================================================
//  security-cookie.cpp -- hand-written compiler-support routines
//                         (/GS cookie + __chkstk)  (18.48 batch 3/4)
//
//  WHY
//    MEASURED: linking with --coverage (clang_rt.profile) needs
//    `__security_cookie` and `__security_check_cookie`. Those live in Microsoft's
//    static CRT (libcmt.lib / msvcrt.lib), which may not be redistributed, and we
//    replaced libcmt.lib with our own. So we provide them: a per-process cookie
//    plus the check the compiler's /GS prologue calls.
//
//    MEASURED (batch 4): `-fsanitize=address` additionally needs `__chkstk` --
//    the stack-probe helper every function with a >4 KB frame calls. Microsoft's
//    libcmt.lib has it; mingw-w64's libmingwex.a does NOT (its x64 name is
//    `__chkstk_ms`, for the GNU ABI). So it is hand-written in assembly below.
//
//  The cookie is seeded from the system tick count and the stack address, like the
//  original does; a mismatch calls the CRT's own report routine, which ucrtbase.dll
//  exports (`__report_gsfailure`).
//
//  ASCII only.
// ============================================================================

extern "C" {

__declspec(dllimport) unsigned long __cdecl GetTickCount(void);
__declspec(dllimport) void          __cdecl __report_gsfailure(unsigned long long cookie);

//  The symbol the compiler's prologue loads. It must be a real global: the /GS
//  code reads it directly (not through a pointer).
unsigned long long __security_cookie = 0x00002B992DDFA232ULL;

void __cdecl __security_init_cookie(void) {
    unsigned long long cookie = ((unsigned long long)GetTickCount() << 32) ^ (unsigned long long)&cookie;
    if (cookie == 0x00002B992DDFA232ULL) {
        cookie ^= 0x0000FFFFFFFFFFFFULL;   // never leave the default value in place
    }
    __security_cookie = cookie;
}

void __cdecl __security_check_cookie(unsigned long long cookie) {
    if (cookie != __security_cookie) {
        __report_gsfailure(cookie);
    }
}

} // extern "C"

//  __chkstk: on entry %rax = number of bytes the caller is about to subtract from
//  %rsp. We must touch every 4 KB page on the way down so the OS grows the stack,
//  then return with %rsp untouched (the caller does its own `sub rsp, imm`).
//
//  ⚠ MEASURED 2026-10-06 -- the FIRST version of this file was WRONG and it cost a
//    long hunt: any function with a frame larger than 4 KB (a `std::mt19937` local
//    is 5 KB) died with 0xC0000005 in the PROLOGUE -- before a single statement
//    ran, so the program printed nothing at all and looked like a static-init bug.
//    A 9 KB local array reproduces it in three lines. The lesson is in
//    docs\交接\接手须知.md: `__chkstk` is not "an asm stub", it is ABI.
//
//  What went wrong there: probing started from the WRONG base and the loop tail
//  did not match the loop's own arithmetic, so the walk could step over the guard
//  page instead of into it.
//
//  ⚠ CORRECTION (18.49 supplement, measured 2026-10-06): an earlier version of
//    this comment claimed the code below was "mingw-w64's canonical chkstk.S
//    (public domain), copied verbatim". That claim could NOT be backed up:
//    this machine has no mingw-w64 SOURCE tree to point at, and
//    `nm --defined-only` over mingw's five libraries (libmingwex / libmingw32 /
//    libmsvcrt / libucrt / libucrtbase) finds NO definition of __chkstk -- nor is
//    it in libgcc*.a -- while the compiler-rt libraries we ship only REFERENCE
//    it. What is true, and is what this file is: the canonical implementation of
//    the documented MS x64 stack-probe routine (%rax = size on entry, every page
//    touched on the way down, %rsp untouched on return).
//    Reproducible evidence: tools\check_handwritten_alternatives.ps1
__asm__(
    ".text\n"
    ".globl __chkstk\n"
    ".p2align 4\n"
    "__chkstk:\n"
    "    pushq %rcx\n"
    "    pushq %rax\n"
    "    cmpq  $0x1000, %rax\n"
    "    leaq  24(%rsp), %rcx\n"
    "    jb    2f\n"
    "1:\n"
    "    subq  $0x1000, %rcx\n"
    "    orq   $0, (%rcx)\n"
    "    subq  $0x1000, %rax\n"
    "    cmpq  $0x1000, %rax\n"
    "    ja    1b\n"
    "2:\n"
    "    subq  %rax, %rcx\n"
    "    orq   $0, (%rcx)\n"
    "    popq  %rax\n"
    "    popq  %rcx\n"
    "    retq\n"
);
