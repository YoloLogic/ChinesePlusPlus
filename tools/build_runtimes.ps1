# ---------------------------------------------------------------------------
# build_runtimes.ps1 -- build the compiler-rt runtime libraries for Chinese++.
#
# WHAT THIS PRODUCES
#   clang_rt.asan*      -fsanitize=address
#   clang_rt.ubsan*     -fsanitize=undefined
#   clang_rt.profile*   --coverage / -fprofile-instr-generate
#   (clang_rt.builtins* only if the target needs them; the MSVC target does not)
#
# AND WHERE THEY GO (added 2026-10-05)
#   This script now also INSTALLS them where the driver looks for them --
#   <resource-dir>\lib\windows\ (+ the ignorelists in <resource-dir>\share\),
#   with the resource dir taken from `chinese++.exe --print-resource-dir`.
#   Before that, this script only printed the artifacts, so the 2026-09-26 copy
#   was placed BY HAND -- i.e. repackaging depended on someone remembering, and
#   make_package.ps1 throws when the folder is missing. It also self-checks that
#   the 6 runtime libraries packaging\verify.ps1 demands are really there.
#   Expected: 12 clang_rt.* files / ~8.3 MB.  See docs\打包\打包方案.md 7.11.
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
# A SOURCE-TREE HAZARD, OBSERVED ONCE  (2026-09-27)
#   CMake runs helper Python scripts straight out of the LLVM source tree, and
#   CPython then writes a __pycache__ next to them. One such file turned up at
#       LLVM-main\openmp\runtime\tools\__pycache__\libomputils.cpython-313.pyc
#   It is not source, but it broke tools\make_patch.ps1's coverage sweep:
#       openmp   files 857/858   bytes 7649466/7652311   differs   NOT SCANNED
#   i.e. a top-level directory differed while no patch covers it, so the script
#   refused to claim "our patches reproduce our tree". The gate was RIGHT.
#
#   The file was deleted BEFORE its timestamp was recorded, so WHICH build
#   produced it was NOT established. libomputils.py is imported only by scripts
#   under openmp\runtime\tools\ (message-converter / generate-def /
#   check-execstack / check-depends), and THIS script only configures
#   -DLLVM_ENABLE_RUNTIMES=compiler-rt -- so most likely some openmp/libomp
#   configure did it, but that is inference, not proof.
#   Treat the PYTHONDONTWRITEBYTECODE line below as PREVENTION, not as a
#   verified root-cause fix. If the file reappears, record its timestamp FIRST.
#
# HOW TO RUN
#   powershell -ExecutionPolicy Bypass -File tools\build_runtimes.ps1
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

# Keep CPython from dropping __pycache__ into the LLVM source tree (see the
# hazard note above). Child processes -- cmake, ninja, the Python scripts they
# spawn -- inherit this.
$env:PYTHONDONTWRITEBYTECODE = '1'

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

# ---------------------------------------------------------------------------
# CMAKE_AR must be an MSVC-compatible archiver. (Observed 2026-10-05.)
#
# SYMPTOM: a fresh Ninja configure outside a "Developer Command Prompt" leaves
#   CMAKE_AR-NOTFOUND, and then EVERY static library target dies at the archive
#   step with:
#       C:\windows\system32\cmd.exe /C "... CMAKE_AR-NOTFOUND /nologo /machine:x64
#            /IGNORE:4221 /out:compiler-rt\lib\windows\clang_rt.builtins-x86_64.lib @..."
#       'CMAKE_AR-NOTFOUND' is not recognized as an internal or external command
#   Measured: 2 targets FAILED (clang_rt.builtins-x86_64.lib,
#   clang_rt.stats-x86_64.lib) and ninja stopped at 463/505 with ZERO
#   clang_rt.* artifacts produced -- i.e. the sanitizer runtime the package
#   needs was silently absent. In a VS prompt lib.exe is on PATH, which is why
#   this was never seen before.
#
# WHY lib.exe AND NOT llvm-ar.exe: CMake's Windows-clang platform module writes
#   MSVC-style archive command lines (`/nologo /machine:x64 /IGNORE:4221
#   /out:...`). MSVC's lib.exe is exactly that tool. llvm-ar.exe only behaves
#   that way when it is INVOKED as `llvm-lib` (name-based dispatch), and the
#   build tree has no llvm-lib.exe -- so llvm-ar.exe under its own name would be
#   given MSVC flags it does not accept. We therefore look for MSVC's lib.exe in
#   the usual Visual Studio roots (short list, no full-tree recursion), newest
#   toolset first; if none is found we fall back to creating the llvm-lib.exe
#   alias next to our own llvm-ar.exe, which the packaged install does too.
# ---------------------------------------------------------------------------
$arExe = $null
$vsRoots = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Community',
    'C:\Program Files\Microsoft Visual Studio\2022\BuildTools',
    'C:\Program Files\Microsoft Visual Studio\2022\Professional',
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise',
    'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools',
    'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community'
)
foreach ($vs in $vsRoots) {
    $msvcDirs = Join-Path $vs 'VC\Tools\MSVC'
    if (-not (Test-Path $msvcDirs)) { continue }
    $toolset = Get-ChildItem $msvcDirs -Directory -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First 1
    if (-not $toolset) { continue }
    $cand = Join-Path $toolset.FullName 'bin\Hostx64\x64\lib.exe'
    if (Test-Path $cand) { $arExe = $cand; break }
}
if (-not $arExe) {
    $libAlias = Join-Path $bin 'llvm-lib.exe'
    if (-not (Test-Path $libAlias)) {
        try { New-Item -ItemType HardLink -Path $libAlias -Target (Join-Path $bin 'llvm-ar.exe') -ErrorAction Stop | Out-Null }
        catch { Copy-Item (Join-Path $bin 'llvm-ar.exe') $libAlias -Force }
    }
    $arExe = $libAlias
    Write-Host "  archiver: fell back to $libAlias (no MSVC lib.exe found)" -ForegroundColor Yellow
} else {
    Write-Host "  archiver: $arExe"
}

# AND put its directory on PATH -- measured 2026-10-05, this is the part that
# actually fixes it:
#   `-DCMAKE_AR=<lib.exe>` alone is NOT enough. The log says
#       "-- Performing standalone runtimes build."
#   i.e. compiler-rt is configured by a SECOND, nested cmake invocation, and that
#   nested configure does not inherit the outer cache's CMAKE_AR -- every static
#   library target still came out as `CMAKE_AR-NOTFOUND`. With lib.exe's own
#   directory on PATH, CMake finds it by itself (find_program), for BOTH the
#   outer and the nested configure. That is precisely what a "Developer Command
#   Prompt" provides, which is why this never happened upstream or on 2026-09-26.
#   (Keeping -DCMAKE_AR as well is harmless and helps the outer configure.)
$arDir = Split-Path -Parent $arExe
if ($env:PATH -notlike "*$arDir*") {
    $env:PATH = "$arDir;$env:PATH"
    Write-Host "  archiver dir on PATH: $arDir"
}

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
    "-DCMAKE_AR=$(ToCmakePath $arExe)" `
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

# ---------------------------------------------------------------------------
# === install into the resource dir ===  (added 2026-10-05)
#
# WHY THIS STEP EXISTS AT ALL: compiler-rt does NOT install itself where the
#   driver looks for it. This script used to stop after printing the artifacts,
#   so the 2026-09-26 copy under build\Release\lib\clang\24\lib\windows was
#   placed BY HAND -- i.e. "repackaging" depended on someone remembering, and
#   make_package.ps1 throws when that folder is missing (measured 2026-10-05:
#   the folder did not exist at all, so no package could be assembled).
#
# WHERE: never guessed. The driver reports its own resource dir:
#       chinese++.exe --print-resource-dir   ->  ...\build\Release\lib\clang\24
#   and packaging\verify.ps1 checks exactly:
#       <resource-dir>\lib\windows\clang_rt.*        (the runtime libraries)
#       <resource-dir>\share\{asan,cfi}_ignorelist.txt (clang passes these to
#                                                      the driver; shipped too)
#
# JUDGED, not assumed: the 6 files verify.ps1 requires must exist afterwards,
#   otherwise this script fails loudly instead of leaving a half-installed tree.
# ---------------------------------------------------------------------------
Write-Host "=== install into the resource dir ===" -ForegroundColor Cyan
$resDir = (& (Join-Path $bin 'chinese++.exe') --print-resource-dir | Select-Object -First 1)
if ($resDir) { $resDir = $resDir.Trim() }
if (-not $resDir -or -not (Test-Path $resDir)) { throw "cannot determine the resource dir (got '$resDir')" }
$dstWin   = Join-Path $resDir 'lib\windows'
$dstShare = Join-Path $resDir 'share'
New-Item -ItemType Directory -Force $dstWin, $dstShare | Out-Null

$nRt = 0
Get-ChildItem $out -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^clang_rt\.' -and $_.Extension -in '.lib', '.dll' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $dstWin $_.Name) -Force; $nRt++ }

$ignoreSrc = Join-Path $root 'LLVM-main\compiler-rt\lib\sanitizer_ignorelists'
$nIgn = 0
foreach ($n in @('asan_ignorelist.txt', 'cfi_ignorelist.txt', 'hwasan_ignorelist.txt', 'msan_ignorelist.txt')) {
    $s = Join-Path $ignoreSrc $n
    if (Test-Path $s) { Copy-Item $s (Join-Path $dstShare $n) -Force; $nIgn++ }
}
Write-Host ("  {0} runtime files -> {1}" -f $nRt, $dstWin)
Write-Host ("  {0} ignorelists  -> {1}" -f $nIgn, $dstShare)

# The same 6 names packaging\verify.ps1 demands -- keep the two lists in sync.
$must = @(
    'clang_rt.asan_dynamic-x86_64.dll',
    'clang_rt.asan_dynamic-x86_64.lib',
    'clang_rt.asan_dynamic_runtime_thunk-x86_64.lib',
    'clang_rt.asan_static_runtime_thunk-x86_64.lib',
    'clang_rt.profile-x86_64.lib',
    'clang_rt.ubsan_standalone-x86_64.lib'
)
$miss = @($must | Where-Object { -not (Test-Path (Join-Path $dstWin $_)) })
if ($miss.Count) { throw ("install incomplete -- still missing: " + ($miss -join ', ')) }
foreach ($n in @('asan_ignorelist.txt', 'cfi_ignorelist.txt')) {
    if (-not (Test-Path (Join-Path $dstShare $n))) { throw "install incomplete -- share\$n missing" }
}
Write-Host "  all 6 required runtime libraries + both ignorelists are in place" -ForegroundColor Green
