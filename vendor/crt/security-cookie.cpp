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
//  Only %rcx and %r11 are touched, and both are saved/restored; %rax is used as the
//  count-down register, which is safe because clang emits the frame size as an
//  immediate in the following `sub rsp, imm` (verified with -S).
__asm__(
    ".text\n"
    ".globl __chkstk\n"
    ".p2align 4\n"
    "__chkstk:\n"
    "    pushq %rcx\n"
    "    pushq %r11\n"
    "    movq  %rsp, %r11\n"
    "1:\n"
    "    subq  $0x1000, %r11\n"
    "    testl %r11d, (%r11)\n"
    "    cmpq  $0x1000, %rax\n"
    "    jbe   2f\n"
    "    subq  $0x1000, %rax\n"
    "    jmp   1b\n"
    "2:\n"
    "    subq  %rax, %r11\n"
    "    testl %r11d, (%r11)\n"
    "    popq  %r11\n"
    "    popq  %rcx\n"
    "    retq\n"
);
