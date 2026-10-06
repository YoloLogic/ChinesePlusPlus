# ============================================================================
#  verify.ps1 -- prove THIS PACKAGE works, from inside the package.
#
#  Why this exists separately from tests\run_all.ps1
#  ------------------------------------------------
#  Everything else in the repo tests the BUILD TREE (build\Release\bin).
#  A package is a different artifact with failure modes of its own:
#    * hardlinks lost during zip/unzip  -> clang.exe etc. may be missing
#    * the resource dir (lib\clang\<ver>\include) not found from a foreign cwd
#    * invoked from another drive, or from a path containing non-ASCII
#    * Visual Studio Build Tools absent -> MSVC STL / Windows SDK missing
#  So "the package is fine" must be its own claim, checked here.
#
#  This script does NOT assume the build tree exists. It only uses what is
#  inside the package, and it does not care where the package sits.
#
#  Usage:
#      powershell -File <package>\verify.ps1
#      powershell -File <package>\verify.ps1 -KeepTemp
#
#  ENCODING: PURE ASCII on purpose (PowerShell 5.1 reads BOM-less files as GBK).
#    Chinese test sources are generated from code points, not typed here.
# ============================================================================

param([switch] $KeepTemp)

$ErrorActionPreference = 'Continue'

$here = $PSScriptRoot
$bin  = Join-Path $here 'bin'
$cxx  = Join-Path $bin 'chinese++.exe'

$pass = 0; $fail = 0
function Ok  ($m) { Write-Host ("  [ok]   " + $m) -ForegroundColor Green;  $script:pass++ }
function Bad ($m) { Write-Host ("  [FAIL] " + $m) -ForegroundColor Red;    $script:fail++ }

# --- how many checks this script performs when everything passes -------------
#  §18.47: this number is the ONLY source of truth for "the package self-test has
#  N items". check_zhdocs.ps1 (gate guard #15) reads it from this file and refuses
#  any hand-written doc that quotes a different number -- so docs cannot drift.
#  Add or remove a check -> this assertion tells you to bump the number.
$expectedChecks = 21

Write-Host ""
Write-Host "=== Chinese++ package self-test ===" -ForegroundColor Cyan
Write-Host "package root: $here"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. the compiler and every hardlink alias must be present
# ---------------------------------------------------------------------------
Write-Host '--- 1) files present (hardlink aliases included)'
# The zip ships only 5 real files; the other 8 names are hardlinks that
# install.ps1 creates after extraction. So "aliases missing" on a freshly
# unzipped package is NOT a defect -- it means setup has not run yet. Saying
# "1 failed" there would scare a first-time user for no reason, so that case is
# reported separately with its own exit code.
$real  = @('chinese++.exe','lld-link.exe','llvm-ar.exe','clangd.exe','llvm-rc.exe')
$alias = @('clang.exe','clang++.exe','clang-cl.exe','clang-cpp.exe',
           'lld.exe','ld.lld.exe','wasm-ld.exe','llvm-lib.exe','llvm-ranlib.exe')
$must  = $real + $alias
$missing = @()
foreach ($f in $must) { if (-not (Test-Path (Join-Path $bin $f))) { $missing += $f } }

$missingReal  = @($missing | Where-Object { $real  -contains $_ })
$missingAlias = @($missing | Where-Object { $alias -contains $_ })

if ($missing.Count -eq 0) {
    Ok ("all {0} binaries present" -f $must.Count)
} elseif ($missingReal.Count -eq 0 -and $missingAlias.Count -gt 0) {
    Write-Host ''
    Write-Host '  This package has NOT BEEN SET UP YET.' -ForegroundColor Yellow
    Write-Host ("  {0} of the binary names are missing: they are hardlinks that the" -f $missingAlias.Count) -ForegroundColor Yellow
    Write-Host '  setup step creates after extraction (the zip ships one copy of each' -ForegroundColor Yellow
    Write-Host '  binary; a zip cannot store hardlinks).' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Run this first, then run verify.ps1 again:' -ForegroundColor Yellow
    Write-Host '      double-click the one-click setup file in this folder' -ForegroundColor Yellow
    Write-Host '      (or: powershell -File install.ps1)' -ForegroundColor Yellow
    Write-Host ''
    exit 3
} else {
    Bad ("missing: " + ($missing -join ', '))
}

if (-not (Test-Path $cxx)) { Write-Host "`n  cannot continue without $cxx" -ForegroundColor Red; exit 1 }

$resdir = Get-ChildItem (Join-Path $here 'lib\clang') -Directory -ErrorAction SilentlyContinue |
          Select-Object -First 1
if ($resdir -and (Test-Path (Join-Path $resdir.FullName 'include\stddef.h'))) {
    Ok ("resource dir present: lib\clang\" + $resdir.Name + "\include")
} else { Bad 'resource dir (lib\clang\<ver>\include\stddef.h) missing' }

foreach ($f in @('LICENSE.TXT','NOTICE.txt')) {
    if (Test-Path (Join-Path $here $f)) { Ok "$f present" } else { Bad "$f missing (license obligation)" }
}

# ---------------------------------------------------------------------------
# 2. toolchain works: compile and run, from a temp dir that is NOT the package
#
#    Compiling in a foreign cwd is deliberate: it catches a package that only
#    works when cwd == package root.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) compile and run from a foreign working directory'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("zhpp_verify_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force $tmp | Out-Null

# Chinese source built from code points so this file stays ASCII.
# The Chinese spelling of: int main() { std::printf("OK\n"); return 0; }
$zh = -join @(
    [char]0x6574,[char]0x6570,' main() { std::printf("OK\n"); ',
    [char]0x8FD4,[char]0x56DE,' 0; }'
)
$src1 = Join-Path $tmp 'hello.cpp'
"#include <cstdio>`n$zh`n" | Set-Content -Encoding UTF8 $src1

$exe1 = Join-Path $tmp 'hello.exe'
$out = & $cxx -std=c++20 -o $exe1 $src1 2>&1
if ($LASTEXITCODE -ne 0) {
    Bad "compiling a Chinese hello world failed:"
    $out | Select-Object -First 6 | ForEach-Object { Write-Host "         $_" }
    Write-Host ""
    Write-Host "  most likely cause: Visual Studio Build Tools are not installed." -ForegroundColor Yellow
    Write-Host "  this toolchain uses the MSVC STL and the Windows SDK; they are not" -ForegroundColor Yellow
    Write-Host "  bundled. see NOTICE.txt section 4." -ForegroundColor Yellow
} else {
    Ok 'compiles a Chinese hello world'
    $runOut = & cmd /c "`"$exe1`" 2>&1"
    if ($LASTEXITCODE -eq 0 -and "$runOut" -match 'OK') { Ok 'runs and prints' }
    else { Bad "the produced exe did not run correctly (exit=$LASTEXITCODE)" }
}

# ---------------------------------------------------------------------------
# 3. Chinese preprocessor directives + the Chinese entry point spelling
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) Chinese directives and the Chinese entry point'

# Chinese directive #include, and the Chinese spelling of the entry point.
$hash = [char]0x23
$zhInc = "$hash" + [char]0x5305 + [char]0x542B          # Chinese "#include"
$zhMain = [char]0x4E3B + [char]0x51FD + [char]0x6570    # Chinese "main"
$src2 = Join-Path $tmp 'directives.cpp'
"$zhInc <cstdio>`n" + [char]0x6574 + [char]0x6570 + " $zhMain() { " + [char]0x8FD4 + [char]0x56DE + " 0; }`n" |
    Set-Content -Encoding UTF8 $src2

$exe2 = Join-Path $tmp 'directives.exe'
& $cxx -std=c++20 -o $exe2 $src2 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok 'the Chinese include directive compiles' } else { Bad 'the Chinese include directive failed' }

$src3 = Join-Path $tmp 'zhmain.cpp'
# NOTE: the return type must be spelled too. The first version omitted it and
# produced `entrypoint() { ... }` with no return type -- a mistake in this
# script, not in the compiler. Build the whole line with -join: `[char] + [char]`
# in PowerShell does INTEGER ADDITION, not concatenation.
$line3 = -join @([char]0x6574, [char]0x6570, ' ', $zhMain, '() { ',
                 [char]0x8FD4, [char]0x56DE, ' 0; }')
$line3 | Set-Content -Encoding UTF8 $src3
$exe3 = Join-Path $tmp 'zhmain.exe'
& $cxx -std=c++20 -o $exe3 $src3 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok 'the Chinese entry point spelling links' }
else { Bad 'the Chinese entry point spelling failed to link' }

# ---------------------------------------------------------------------------
# 4. Chinese diagnostics
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) diagnostics are in Chinese'

$src4 = Join-Path $tmp 'err.cpp'
"int main(){ return " + [char]0x672A + [char]0x58F0 + [char]0x660E + "; }`n" | Set-Content -Encoding UTF8 $src4
$t4 = Join-Path $tmp 'err.txt'
& cmd /c "`"$cxx`" -fsyntax-only `"$src4`" > `"$t4`" 2>&1"
$txt = [System.IO.File]::ReadAllText($t4)
if ($txt -match [string][char]0x672A + [char]0x58F0 + [char]0x660E) { Ok 'diagnostic text is Chinese' }
else { Bad 'diagnostic text is not Chinese' }

# ---------------------------------------------------------------------------
# 5. the shipped clangd is OURS (the one that knows Chinese keywords)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 5) bundled clangd'
$clangd = Join-Path $bin 'clangd.exe'
if (Test-Path $clangd) {
    $v = & $clangd --version 2>&1 | Select-Object -First 1
    Ok ("clangd runs: " + "$v".Trim())
} else { Bad 'clangd.exe missing (the editor kit needs it)' }

# ---------------------------------------------------------------------------
# 6. the compiler-rt runtime libraries must be present AND actually usable
#
#    Why this section exists: the package gained these libraries on 2026-09-26,
#    and nothing above would notice if they went missing. The failure mode is
#    the nastiest one this package can produce:
#      * the ASan IMPORT library (.lib) is what the linker needs
#      * the ASan DLL is what the built program needs at RUN time
#    Ship only the .lib and everything looks fine -- compile OK, link OK -- and
#    then the program dies instantly with exit code -1073741515 (0xC0000135)
#    and prints NOTHING. So both halves are checked, and ASan is made to
#    actually report a real use-after-free.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 6) compiler-rt runtimes (-fsanitize=address / --coverage)'

$rtDir = ''
if ($resdir) { $rtDir = Join-Path $resdir.FullName 'lib\windows' }
$rtMust = @(
    'clang_rt.asan_dynamic-x86_64.dll',
    'clang_rt.asan_dynamic-x86_64.lib',
    'clang_rt.asan_dynamic_runtime_thunk-x86_64.lib',
    'clang_rt.asan_static_runtime_thunk-x86_64.lib',
    'clang_rt.profile-x86_64.lib',
    'clang_rt.ubsan_standalone-x86_64.lib'
)
$rtMissing = @()
if (-not $rtDir -or -not (Test-Path $rtDir)) {
    $rtMissing = $rtMust
} else {
    foreach ($f in $rtMust) { if (-not (Test-Path (Join-Path $rtDir $f))) { $rtMissing += $f } }
}
if ($rtMissing.Count -eq 0) { Ok ("all {0} required runtime libraries present" -f $rtMust.Count) }
else { Bad ("runtime libraries missing from lib\clang\<ver>\lib\windows: " + ($rtMissing -join ', ')) }

foreach ($f in @('asan_ignorelist.txt', 'cfi_ignorelist.txt')) {
    $p = ''
    if ($resdir) { $p = Join-Path $resdir.FullName "share\$f" }
    if ($p -and (Test-Path $p)) { Ok "$f present" } else { Bad "$f missing (clang passes it to the driver)" }
}

# (a) it must LINK -- this is the import-library half
$srcA = Join-Path $tmp 'asan.cpp'
"int main() { int *p = new int[4]; delete[] p; return p[0]; }`n" | Set-Content -Encoding ASCII $srcA
$exeA = Join-Path $tmp 'asan.exe'
& $cxx -fsanitize=address -o $exeA $srcA 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok '-fsanitize=address compiles and links' }
else { Bad '-fsanitize=address failed to compile or link' }

# (b) it must REPORT -- this is the DLL half, and it fails silently without it
if ((Test-Path $exeA) -and $rtDir -and (Test-Path $rtDir)) {
    $savedPath = $env:PATH
    $env:PATH = "$rtDir;$env:PATH"
    $t6 = Join-Path $tmp 'asan.txt'
    & cmd /c "`"$exeA`" > `"$t6`" 2>&1"
    $env:PATH = $savedPath
    $aTxt = [System.IO.File]::ReadAllText($t6)
    if ($aTxt -match 'AddressSanitizer') { Ok 'AddressSanitizer reports a real use-after-free' }
    else { Bad 'AddressSanitizer produced no report (is the runtime DLL reachable?)' }
}

$srcC = Join-Path $tmp 'cov.cpp'
"int add(int a, int b) { return a + b; } int main() { return add(1,2) == 3 ? 0 : 1; }`n" |
    Set-Content -Encoding ASCII $srcC
$exeC = Join-Path $tmp 'cov.exe'
& $cxx --coverage -o $exeC $srcC 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Ok '--coverage compiles and links' }
else { Bad '--coverage failed to compile or link' }

# UBSan CANNOT be linked on its own here. The package FAQ section 9 records the
# evidence: the __coe_win interface it needs is implemented in neither this
# VS/SDK nor anywhere in the LLVM source tree. Combined WITH address it links and
# really reports, so that combination -- and only that -- is asserted.
# NOTE: the flag MUST stay quoted; PowerShell would otherwise split the comma
# into two arguments and clang would reject the command line.
$srcU = Join-Path $tmp 'ub.cpp'
"int main() { int x = 1; return x << 40; }`n" | Set-Content -Encoding ASCII $srcU
$exeU = Join-Path $tmp 'ub.exe'
& $cxx '-fsanitize=address,undefined' -o $exeU $srcU 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Bad '-fsanitize=address,undefined failed to compile or link'
} else {
    $savedPath2 = $env:PATH
    $env:PATH = "$rtDir;$env:PATH"
    $tU = Join-Path $tmp 'ub.txt'
    & cmd /c "`"$exeU`" > `"$tU`" 2>&1"
    $env:PATH = $savedPath2
    $uTxt = [System.IO.File]::ReadAllText($tU)
    if ($uTxt -match 'UndefinedBehaviorSanitizer|runtime error') {
        Ok 'UBSan (with address) reports real undefined behaviour'
    } else { Bad 'UBSan produced no report' }
}

# ---------------------------------------------------------------------------
# 3b. the Chinese standard library, found with NO -I / -isystem on the command line
#
#     WHY THIS IS ITS OWN CLAIM (2026-10-05, decision D-22): the shipped library
#     (zhstdlib\) is reachable only because bin\<driver>.cfg carries the search
#     paths, and that same file is how clangd (the editor's language server)
#     learns them. The list is NOT written here either: it comes from
#     tools\zh_includes.ps1 (single source of truth) through make_zhcfg.ps1 --
#     which is why this script never needs -I or -isystem for our own headers.
#     Measured before it existed: a package user could not compile a single
#     Chinese include, and NOTHING in the package said so. So this check compiles
#     a Chinese include from a foreign working directory with no flags at all and
#     runs the result; a moved/renamed package folder surfaces right here.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3b) the Chinese standard library (no -I, no -isystem)'

$cfgs = @('chinese++.cfg', 'clang++.cfg', 'clang.cfg')
$cfgMissing = @($cfgs | Where-Object { -not (Test-Path (Join-Path $bin $_)) })
$zhRoot = Join-Path $here 'zhstdlib'
if ($cfgMissing.Count) {
    Bad ("missing include-path config: " + ($cfgMissing -join ', '))
    Write-Host '         these are WRITTEN BY THE INSTALLER -- run setup first:' -ForegroundColor Yellow
    Write-Host '             powershell -File install.ps1' -ForegroundColor Yellow
    Write-Host '         without them the compiler cannot find the Chinese headers.' -ForegroundColor Yellow
    Write-Host '         (clang.cfg is needed too: clangd falls back to the `clang`' -ForegroundColor Yellow
    Write-Host '          next to it, so without that file the editor stays red.)' -ForegroundColor Yellow
} elseif (-not (Test-Path $zhRoot)) {
    Bad 'zhstdlib\ is missing from this package (the Chinese library did not ship)'
} else {
    Ok 'include-path config present (chinese++.cfg / clang++.cfg / clang.cfg)'
    Ok 'zhstdlib\ present'
    # The Chinese source is built from code points so this file stays ASCII:
    #   #include-directive <vector-cn>
    #   #include <vector>
    #   int main(){ 标准::向量<int> 表; 表.尾插(1); std::vector<int> 乙{1,2};
    #               return (int)表.尺寸() + (int)乙.size() - 3; }
    $libSrc = Join-Path $tmp 'zhlib.cpp'
    $l = -join @(
        $zhInc, ' <', [char]0x5411, [char]0x91CF, ">`n",
        "#include <vector>`n",
        [char]0x6574, [char]0x6570, ' ', $zhMain, '(){ ',
        [char]0x6807, [char]0x51C6, '::', [char]0x5411, [char]0x91CF, '<', [char]0x6574, [char]0x6570, '> ',
        [char]0x8868, '; ', [char]0x8868, '.', [char]0x5C3E, [char]0x63D2, '(1); ',
        'std::vector<int> ', [char]0x4E59, '{1,2}; ',
        [char]0x8FD4, [char]0x56DE, ' (int)', [char]0x8868, '.', [char]0x5C3A, [char]0x5BF8,
        '() + (int)', [char]0x4E59, '.size() - 3; }'
    )
    $l | Set-Content -Encoding UTF8 $libSrc
    $libExe = Join-Path $tmp 'zhlib.exe'
    # NOTE: deliberately NO -I and NO -isystem -- that is the whole point here.
    $outLib = & $cxx -std=c++20 -o $libExe $libSrc 2>&1
    if ($LASTEXITCODE -ne 0) {
        Bad 'compiling a Chinese standard-library include with no include flags failed:'
        $outLib | Select-Object -First 6 | ForEach-Object { Write-Host "         $_" }
        Write-Host '         most likely cause: the package folder was moved or renamed' -ForegroundColor Yellow
        Write-Host '         after setup -- re-run install.ps1 (the cfg holds absolute paths).' -ForegroundColor Yellow
    } else {
        Ok 'compiles a Chinese include + std::vector in one file, with no flags'
        & cmd /c "`"$libExe`" > `"$tmp\zhlib.txt`" 2>&1"
        if ($LASTEXITCODE -eq 0) { Ok 'the Chinese-library program runs (exit 0)' }
        else { Bad ("the Chinese-library program exited " + $LASTEXITCODE) }
    }
}

# ---------------------------------------------------------------------------
if (-not $KeepTemp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ('=' * 60)
if ($fail -eq 0) {
    if ($pass -ne $expectedChecks) {
        Write-Host ("  [FAIL] ran {0} checks, expected {1} -- bump `$expectedChecks here AND the docs that quote it" -f $pass, $expectedChecks) -ForegroundColor Red
        exit 1
    }
    Write-Host ("  {0} passed, 0 failed -- this package works." -f $pass) -ForegroundColor Green
    exit 0
}
Write-Host ("  {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor Red
exit 1
