# ---------------------------------------------------------------------------
# build_runtimes.ps1 -- build the compiler-rt runtime libraries for Chinese++.
#
# WHAT THIS PRODUCES
#   clang_rt.asan*      -fsanitize=address
#   clang_rt.ubsan*     -fsanitize=undefined
#   clang_rt.profile*   --coverage / -fprofile-instr-generate
#   (clang_rt.builtins* only if the target needs them; the MSVC target does not)
#
# WHY THIS IS A SEPARATE SCRIPT
#   tools\rebuild_clang.ps1 does NOT build compiler-rt. LLVM_ENABLE_RUNTIMES is a
#   different configure, and the runtimes are compiled BY THE FRESHLY BUILT
#   Chinese++ COMPILER, so that their ABI matches the compiler exactly.
#
# WHY NINJA AND NOT THE "Visual Studio 17 2022" GENERATOR  (measured 2026-09-26)
#   Under the Visual Studio generator the nested runtimes build IGNORES
#   -DCMAKE_C_COMPILER=clang-cl.exe and silently falls back to the default MSVC
#   toolset. Hard evidence collected from build\runtimes\runtimes-bins:
#       * "cl : warning D9002: ignoring unknown option '-fms-extensions'"
#         -- that is MSVC cl.exe complaining about a clang switch.
#       * CMakeCache.txt holds "CMAKE_C_COMPILER:UNINITIALIZED=...clang-cl.exe",
#         i.e. the value was recorded but never used to select a toolset.
#       * Diagnostics came out as MSVC's "error C2065", not clang's.
#       * Consequence: COMPILER_RT_HAS_SANITIZER_COMMON evaluated to FALSE
#         (compiler-rt\cmake\config-ix.cmake:773), so asan/ubsan were dropped
#         entirely and only profile+orc were built.
#   Ninja has no toolset concept, so -DCMAKE_C_COMPILER is honoured verbatim.
#
# HOW TO RUN
#   powershell -ExecutionPolicy Bypass -File tools\build_runtimes.ps1
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$bin  = Join-Path $root 'build\Release\bin'
$crt  = Join-Path $bin 'clang-cl.exe'
$out  = Join-Path $root 'build\_crt_ninja'

$cmake = 'E:\CLion 2026.1.2\bin\cmake\win\x64\bin\cmake.exe'
$ninjaDir = 'E:\CLion 2026.1.2\bin\ninja\win\x64'

if (-not (Test-Path $crt)) {
    throw "no clang-cl.exe at $crt -- build the compiler first (tools\rebuild_clang.ps1)"
}
if (-not (Test-Path $cmake)) { throw "cmake not found at $cmake" }
if (Test-Path (Join-Path $ninjaDir 'ninja.exe')) { $env:PATH = "$ninjaDir;$env:PATH" }
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) { throw "ninja not found on PATH" }

# CMake's vs_link_exe helper needs the Windows SDK resource compiler rc.exe and
# the manifest tool mt.exe. Outside a "Developer Command Prompt" neither is on
# PATH, and then the very first "is this compiler usable?" test dies with:
#     RC Pass 1: command "rc /fo ...manifest.res ...manifest.rc" failed
#         no such file or directory
#     --mt=CMAKE_MT-NOTFOUND
# That looks like a broken compiler but it is only a missing tool, so locate
# them explicitly and hand the full paths to CMake. (Observed 2026-09-26.)
$sdkRoot = 'C:\Program Files (x86)\Windows Kits\10\bin'
$sdkVer = Get-ChildItem $sdkRoot -Directory -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -match '^10\.' } | Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdkVer) { throw "no Windows SDK bin directory under $sdkRoot" }
$rcExe = Join-Path $sdkVer.FullName 'x64\rc.exe'
$mtExe = Join-Path $sdkVer.FullName 'x64\mt.exe'
if (-not (Test-Path $rcExe)) { throw "rc.exe not found at $rcExe" }
if (-not (Test-Path $mtExe)) { throw "mt.exe not found at $mtExe" }
Write-Host "  Windows SDK tools: $($sdkVer.Name)"

# The documented standalone-runtimes entry point is <llvm-project>\runtimes.
$runtimesSrc = Join-Path $root 'LLVM-main\runtimes'
if (-not (Test-Path (Join-Path $runtimesSrc 'CMakeLists.txt'))) {
    throw "no runtimes source at $runtimesSrc"
}

Write-Host "=== configure compiler-rt (Ninja, built by $crt) ===" -ForegroundColor Cyan

# NOTE: every -D argument below MUST be quoted.
#   PowerShell passes a bare token that starts with '-' VERBATIM to a native
#   command: no variable expansion happens inside it. So
#       -DCMAKE_C_COMPILER=$crt
#   reaches cmake as the literal 5-character string "$crt" and the configure
#   dies with "The CMAKE_C_COMPILER: $crt is not a full path and was not found
#   in the PATH". Quoting the whole argument turns expansion back on.
#   Observed 2026-09-26.
#
# NOTE: paths must use FORWARD slashes.
#   CMake writes what it is given straight into CMakeFiles\<ver>\
#   CMakeRCCompiler.cmake. A backslash there is an escape character, so
#   "C:\Program Files (x86)\Windows Kits\10\bin\...\rc.exe" corrupts the file:
#       Syntax error in cmake code at .../CMakeRCCompiler.cmake:1 (set)
#   Observed 2026-09-26.
function ToCmakePath([string]$p) { return ($p -replace '\\', '/') }

# COMPILER_RT_HAS_VERSION_SCRIPT must be forced OFF.
#   compiler-rt\cmake\config-ix.cmake:228 probes the linker for --version-script.
#   Our clang-cl prefers lld-link, which DOES support it, so the probe succeeds
#   and compiler-rt takes a path that is only self-consistent on ELF:
#     lib\asan\CMakeLists.txt:320   "if (NOT WIN32)" skips the static runtime
#     lib\asan\CMakeLists.txt:360   "if(WIN32)" pulls clang_rt.asan-${arch} in
#                                   anyway and feeds that nonexistent target to
#                                   add_sanitizer_rt_version_list, giving
#                                       No target "clang_rt.asan-x86_64"
#   With MSVC's link.exe the probe fails and the whole branch is skipped, which
#   is why upstream never sees this on Windows. A version script is an ELF
#   concept and means nothing on Windows, so forcing it OFF is semantically
#   correct rather than a workaround; it also covers lib\ubsan and lib\nsan.
#   Observed 2026-09-26.

& $cmake -S (ToCmakePath $runtimesSrc) -B (ToCmakePath $out) -G Ninja `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DCMAKE_C_COMPILER=$(ToCmakePath $crt)" `
    "-DCMAKE_CXX_COMPILER=$(ToCmakePath $crt)" `
    "-DCMAKE_ASM_COMPILER=$(ToCmakePath $crt)" `
    "-DCMAKE_RC_COMPILER=$(ToCmakePath $rcExe)" `
    "-DCMAKE_MT=$(ToCmakePath $mtExe)" `
    "-DLLVM_ENABLE_RUNTIMES=compiler-rt" `
    "-DLLVM_TARGETS_TO_BUILD=X86" `
    "-DCOMPILER_RT_INCLUDE_TESTS=OFF" `
    "-DCOMPILER_RT_BUILD_SANITIZERS=ON" `
    "-DCOMPILER_RT_BUILD_PROFILE=ON" `
    "-DCOMPILER_RT_BUILD_ORC=OFF" `
    "-DCOMPILER_RT_BUILD_XRAY=OFF" `
    "-DCOMPILER_RT_BUILD_LIBFUZZER=OFF" `
    "-DCOMPILER_RT_BUILD_MEMPROF=OFF" `
    "-DCOMPILER_RT_BUILD_CTX_PROFILE=OFF" `
    "-DCOMPILER_RT_BUILD_GWP_ASAN=OFF" `
    "-DCOMPILER_RT_HAS_VERSION_SCRIPT=OFF"
if ($LASTEXITCODE -ne 0) { throw "configure failed with exit $LASTEXITCODE" }

Write-Host "=== build ===" -ForegroundColor Cyan
& $cmake --build $out
if ($LASTEXITCODE -ne 0) { throw "build failed with exit $LASTEXITCODE" }

Write-Host "=== artifacts ===" -ForegroundColor Cyan
Get-ChildItem $out -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^clang_rt\.' -and $_.Extension -in '.lib', '.dll', '.a', '.exe' } |
    Sort-Object Name |
    ForEach-Object { "  {0,-52} {1,8} KB" -f $_.Name, [int]($_.Length / 1KB) }
