// ============================================================================
//  crt0.c -- hand-written C runtime startup for Chinese++ (18.48 batch 3)
//
//  WHY THIS FILE EXISTS
//    Every MSVC-target link adds `-defaultlib:libcmt -defaultlib:oldnames`.
//    Microsoft's libcmt.lib (static CRT + startup) may not be redistributed, so we
//    ship OUR OWN library under that name, and this file is its `mainCRTStartup`.
//    Everything it calls -- GetCommandLineA, ExitProcess, exit -- comes from
//    kernel32.dll / ucrtbase.dll, i.e. from Windows itself.
//
//  WHAT IT DOES (the minimum a C/C++ program needs before main):
//    1. run the C++ initializer table (.CRT$XI*), then the C one (.CRT$XC*);
//       static constructors and the C++ runtime's std::cout initializer live there;
//    2. turn the command line into argc/argv without CRT help;
//    3. call main, then exit() so atexit handlers and destructors run.
//
//  MEASURED TRAP (cost a whole round): the compiler compiles this file as C++,
//  so the declarations MUST be inside `extern "C"` -- otherwise they are name
//  mangled (`__imp_?exit@@YAXH@Z`) and the import libraries, which provide the
//  plain C names, cannot satisfy them ("undefined symbol: __imp_?exit@@YAXH@Z").
//
//  ASCII only (this file ships inside the package).
// ============================================================================

typedef void (__cdecl * _PVFV)(void);
typedef int (__cdecl * _PIFV)(void);

#ifdef __cplusplus
extern "C" {
#endif

//  Bounds of the initializer arrays. MSVC uses these very names; anything that
//  wants to be initialized before main puts itself between them.
#pragma section(".CRT$XCA", long, read)
#pragma section(".CRT$XCZ", long, read)
__declspec(allocate(".CRT$XCA")) _PVFV __xc_a[] = { 0 };
__declspec(allocate(".CRT$XCZ")) _PVFV __xc_z[] = { 0 };

#pragma section(".CRT$XIA", long, read)
#pragma section(".CRT$XIZ", long, read)
__declspec(allocate(".CRT$XIA")) _PIFV __xi_a[] = { 0 };
__declspec(allocate(".CRT$XIZ")) _PIFV __xi_z[] = { 0 };

__declspec(dllimport) char* __cdecl GetCommandLineA(void);
__declspec(dllimport) void  __cdecl ExitProcess(unsigned int);
__declspec(dllimport) void  __cdecl exit(int);

int __cdecl main(int argc, char** argv);
void __cdecl zh_drain_stl_facets(void);   // defined in vendor\crt\stl-internals.cpp

static void run_c_initializers(void) {
    _PVFV* p = __xc_a;
    for (++p; p < __xc_z; ++p) {
        if (*p) { (*p)(); }
    }
}

static void run_cpp_initializers(void) {
    _PIFV* p = __xi_a;
    for (++p; p < __xi_z; ++p) {
        if (*p) { (*p)(); }
    }
}

//  A deliberately small command-line splitter: whitespace separated, double quotes
//  group. Enough for `prog a b "c d"`, which is what the self-test needs.
static int split_command_line(char* cmd, char** argv, int max) {
    int argc = 0;
    char* p = cmd;
    while (*p && argc < max) {
        while (*p == ' ' || *p == '\t') { ++p; }
        if (!*p) { break; }
        if (*p == '"') {
            ++p;
            argv[argc++] = p;
            while (*p && *p != '"') { ++p; }
        } else {
            argv[argc++] = p;
            while (*p && *p != ' ' && *p != '\t') { ++p; }
        }
        if (*p) { *p++ = 0; }
    }
    return argc;
}

void __cdecl mainCRTStartup(void) {
    char* argv[64];
    int argc = split_command_line(GetCommandLineA(), argv, 64);
    run_cpp_initializers();
    run_c_initializers();
    int _Code = main(argc, argv);
    zh_drain_stl_facets();   // release registered locale facets before the CRT exits
    exit(_Code);
    ExitProcess(0);   // not reached; keeps the linker honest if exit looks noreturn
}

#ifdef __cplusplus
}
#endif
