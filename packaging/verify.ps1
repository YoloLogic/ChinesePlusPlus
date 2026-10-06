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

# 18.48: read the chosen toolchain mode EARLY. Sections before 3c need it to know
# whether LINKING is expected to work yet: in bundled mode the header substrate is
# complete but the link layer (import libraries + CRT startup objects) is batch 3,
# so a link attempt would fail with LNK1120 and look like a regression.
$tcMode = '(unknown)'
$tcFile = Join-Path $bin 'toolchain.txt'
if (Test-Path $tcFile) {
    $tm0 = [regex]::Match([System.IO.File]::ReadAllText($tcFile), 'mode\s*=\s*(\w+)')
    if ($tm0.Success -and $tm0.Groups[1].Value -in @('bundled', 'system')) { $tcMode = $tm0.Groups[1].Value }
}

$pass = 0; $fail = 0
function Ok  ($m) { Write-Host ("  [ok]   " + $m) -ForegroundColor Green;  $script:pass++ }
function Bad ($m) { Write-Host ("  [FAIL] " + $m) -ForegroundColor Red;    $script:fail++ }

# --- how many checks this script performs when everything passes -------------
#  18.47: this number is the ONLY source of truth for "the package self-test has
#  N items". check_zhdocs.ps1 (gate guard #15) reads it from this file and refuses
#  any hand-written doc that quotes a different number -- so docs cannot drift.
#  Add or remove a check -> this assertion tells you to bump the number.
#  18.48 batch 1 added three (toolchain mode / runtime DLLs / <vector> provenance);
#  18.48 batch 2 added one more (Windows + Chinese header with no Microsoft path).
$expectedChecks = 26

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
if (-not (Test-Path $exeA)) {
    Bad 'AddressSanitizer executable was not produced'
} elseif (-not $rtDir -or -not (Test-Path $rtDir)) {
    Bad 'AddressSanitizer runtime directory is missing (lib\clang\<ver>\lib\windows)'
} else {
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
$covLinked = ($LASTEXITCODE -eq 0)
$covGcda = $false
if ($covLinked -and $rtDir -and (Test-Path $rtDir)) {
    # 真跑：--coverage 的 .gcda 是在**退出时**由 clang_rt.profile 落盘的，
    # 它靠 atexit 注册 —— 这正是 bundled 地基里我们手搓的那条链
    # （vendor\crt\startup-extra.cpp + crt0 调 ucrtbase 的 exit），所以必须真跑才算数。
    $savedPath3 = $env:PATH
    $env:PATH = "$rtDir;$env:PATH"
    & cmd /c "`"$exeC`" > `"$(Join-Path $tmp 'cov.txt')`" 2>&1" | Out-Null
    $env:PATH = $savedPath3
    $covGcda = [bool](Get-ChildItem $tmp -Filter '*cov.gcda' -ErrorAction SilentlyContinue)
}
if ($covLinked -and $covGcda) { Ok '--coverage compiles, links, runs and writes its .gcda' }
elseif ($covLinked) { Bad '--coverage linked but wrote no .gcda after running' }
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
    #   <include-directive> <vector-cn>
    #   #include <vector>
    #   <int-cn> <main-cn>(){ <std-cn>::<vector-cn><<int-cn>> t; t.<push_back-cn>(1);
    #               std::vector<int> u{1,2};
    #               char buf[9000]; buf[0]=1; buf[8999]=2;
    #               return (int)t.<size-cn>() + (int)u.size() - 3
    #                      + (buf[0]-1) + (buf[8999]-2); }
    #
    #  ⚠ The 9000-byte LOCAL is not decoration: a frame larger than 4 KB makes the
    #    compiler call __chkstk, which is hand-written asm in vendor\crt\
    #    security-cookie.cpp. MEASURED 2026-10-06: the first version of that asm
    #    walked the guard page wrongly, so EVERY function with a >4 KB frame died
    #    with 0xC0000005 in the prologue -- before a single statement ran, which
    #    made it look like a static-initialization bug for a long time. This line
    #    is what keeps that from coming back unnoticed.
    $libSrc = Join-Path $tmp 'zhlib.cpp'
    $l = -join @(
        $zhInc, ' <', [char]0x5411, [char]0x91CF, ">`n",
        "#include <vector>`n",
        [char]0x6574, [char]0x6570, ' ', $zhMain, '(){ ',
        [char]0x6807, [char]0x51C6, '::', [char]0x5411, [char]0x91CF, '<', [char]0x6574, [char]0x6570, '> ',
        [char]0x8868, '; ', [char]0x8868, '.', [char]0x5C3E, [char]0x63D2, '(1); ',
        'std::vector<int> ', [char]0x4E59, '{1,2}; ',
        'char buf[9000]; buf[0]=1; buf[8999]=2; ',
        [char]0x8FD4, [char]0x56DE, ' (int)', [char]0x8868, '.', [char]0x5C3A, [char]0x5BF8,
        '() + (int)', [char]0x4E59, '.size() - 3 + (buf[0]-1) + (buf[8999]-2); }'
    )
    $l | Set-Content -Encoding UTF8 $libSrc
    $libExe = Join-Path $tmp 'zhlib.exe'
    # NOTE: deliberately NO -I and NO -isystem -- that is the whole point here.
    # 18.48 batch 3 closed the last gap: BOTH modes now link and run, so this is a
    # single unified assertion.  (It used to compile-to-.obj only in bundled mode,
    # because the link layer did not exist yet.)
    $outLib = & $cxx -std=c++20 -o $libExe $libSrc 2>&1
    if ($LASTEXITCODE -ne 0) {
        Bad ("compiling a Chinese standard-library include with no include flags failed ({0} mode):" -f $tcMode)
        $outLib | Select-Object -First 6 | ForEach-Object { Write-Host "         $_" }
        if ($tcMode -eq 'system') {
            Write-Host '         most likely cause: the package folder was moved or renamed' -ForegroundColor Yellow
            Write-Host '         after setup -- re-run install.ps1 (the cfg holds absolute paths).' -ForegroundColor Yellow
        }
    } else {
        Ok ("compiles a Chinese include + std::vector in one file, with no flags ({0} mode)" -f $tcMode)
        & cmd /c "`"$libExe`" > `"$tmp\zhlib.txt`" 2>&1"
        if ($LASTEXITCODE -eq 0) { Ok ("the Chinese-library program links and runs (exit 0, {0} mode)" -f $tcMode) }
        else { Bad ("the Chinese-library program exited " + $LASTEXITCODE) }
    }
}

# ---------------------------------------------------------------------------
# 3c) WHICH toolchain substrate, and is the bundled one self-contained? (18.48)
#
#     Two substrates exist and the user picks one at install time:
#       bundled (default) -- lib\stl\ + bin\*.dll ship inside this package, so no
#                            Visual Studio is needed;
#       system            -- the machine's own Visual Studio / Windows SDK.
#     install.ps1 writes bin\toolchain.txt. This section
#       (a) makes sure that file exists and names a usable mode,
#       (b) checks the VC++ runtime DLLs our own tools IMPORT are actually here
#           (measured: chinese++.exe/clangd.exe/lld-link.exe all import
#            MSVCP140.dll + VCRUNTIME140.dll + VCRUNTIME140_1.dll; a machine
#            without the VC++ Redistributable cannot even START the compiler),
#       (c) compiles an English <vector> with -H and looks at WHERE it resolved:
#           in bundled mode it must come from inside this package, or the
#           "no Visual Studio needed" claim is false.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3c) toolchain substrate (bundled vs the machine''s Visual Studio)'

$tcFile = Join-Path $bin 'toolchain.txt'
$tcMode = ''
if (Test-Path $tcFile) {
    $tm = [regex]::Match([System.IO.File]::ReadAllText($tcFile), 'mode\s*=\s*(\w+)')
    if ($tm.Success -and $tm.Groups[1].Value -in @('bundled', 'system')) {
        $tcMode = $tm.Groups[1].Value
        Ok ("toolchain mode recorded: " + $tcMode)
    } else {
        Bad 'bin\toolchain.txt exists but has no usable "mode = bundled|system" line'
    }
} else {
    Bad 'bin\toolchain.txt is missing -- run install.ps1 (it records the mode)'
}

$rtDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$rtMissing = @($rtDlls | Where-Object { -not (Test-Path (Join-Path $bin $_)) })
if ($rtMissing.Count) {
    Bad ("VC++ runtime DLLs missing from bin\: " + ($rtMissing -join ', '))
    Write-Host '         our own tools import these; on a machine without the' -ForegroundColor Yellow
    Write-Host '         VC++ Redistributable the compiler cannot even start.' -ForegroundColor Yellow
} else {
    Ok ("VC++ runtime DLLs shipped app-local (" + $rtDlls.Count + " checked)")
}

# where does <vector> actually come from?
$probeSrc = Join-Path $tmp 'prov.cpp'
"#include <vector>" | Set-Content -Encoding ASCII $probeSrc
Add-Content -Encoding ASCII $probeSrc 'int main(){ std::vector<int> v{1}; return (int)v.size()-1; }'
$hOut = & $cxx -std=c++20 -fsyntax-only -H $probeSrc 2>&1
$hCode = $LASTEXITCODE
#  NOTE: with 2>&1 the include tree arrives as ErrorRecord objects, so force strings
#  before matching (measured: calling .Trim() on one throws, and the check then
#  silently contributes neither an ok nor a fail -- the count assertion caught it).
$vecLine = @($hOut | ForEach-Object { [string]$_ } | Where-Object { $_ -match '\\vector$' } | Select-Object -First 1)
function Get-Norm([string] $s) { return (($s -replace '\\\\', '\') -replace '/', '\').ToLower() }
function Get-TracePath([string] $s) { return (($s -replace '^\s*\.+\s*', '').Trim()) }
if ($hCode -ne 0) {
    Bad 'a plain English <vector> program does not compile at all'
    $hOut | Select-Object -First 4 | ForEach-Object { Write-Host "         $_" }
} elseif ($tcMode -eq 'system') {
    Ok 'system mode: <vector> resolved from the machine (Visual Studio / SDK)'
} elseif ($vecLine.Count -eq 0) {
    Bad 'bundled mode, but no <vector> line in the include trace (cannot tell where it came from)'
} else {
    $vecPath = Get-TracePath $vecLine[0]
    if ((Get-Norm $vecPath).StartsWith((Get-Norm $here))) {
        Ok '<vector> resolves INSIDE this package (bundled substrate works)'
    } else {
        Bad ('bundled mode, but <vector> came from OUTSIDE the package: ' + $vecPath)
    }
}

# --- the real 18.48 batch-2 claim: a Windows + CHINESE-header program, with no
#     Microsoft path anywhere in the include trace. Built from code points so this
#     file stays pure ASCII; $zhInc is the Chinese "#include" spelling.
$winSrc = Join-Path $tmp 'provwin.cpp'
$cnWindow = -join @([char]0x7A97, [char]0x53E3)                 # window
$winBody = @(
    '#include <windows.h>',
    '#include <commctrl.h>',
    ($zhInc + ' <' + $cnWindow + '>'),
    'int main(){ HWND h = nullptr; INITCOMMONCONTROLSEX ic{}; (void)h; (void)ic; return 0; }'
) -join "`n"
[System.IO.File]::WriteAllText($winSrc, $winBody, (New-Object System.Text.UTF8Encoding($false)))
$winOut = & $cxx -std=c++20 -fsyntax-only -H $winSrc 2>&1
$winCode = $LASTEXITCODE
$winLines = @($winOut | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\s*\.+\s' })
$winVS = @($winLines | Where-Object { $_ -match 'Program Files' })
if ($winCode -ne 0) {
    Bad 'a <windows.h> + Chinese-header program does not compile'
    $winOut | Select-Object -First 4 | ForEach-Object { Write-Host "         $_" }
} elseif ($tcMode -eq 'bundled' -and $winVS.Count -gt 0) {
    Bad ("bundled mode, but " + $winVS.Count + " headers came from Program Files, e.g.: " + (Get-TracePath $winVS[0]))
} elseif ($tcMode -eq 'bundled') {
    Ok ("<windows.h> + a Chinese header resolve with NO Microsoft path anywhere (" + $winLines.Count + " includes traced)")
} else {
    Ok 'system mode: <windows.h> + a Chinese header compile against the machine''s Visual Studio'
}

# --- LINK-layer provenance (18.48 batch 3): with -Wl,/verbose we can see every
#     library lld-link actually READ. In bundled mode none of them may come from
#     Program Files -- that is the difference between "zero VS" as a fact and
#     "happened not to need it". Search paths (clang still passes the VS -libpath:
#     entries) are NOT reads, so only "Reading" lines count.
if ($tcMode -eq 'bundled') {
    $lnkSrc = Join-Path $tmp 'linkprov.cpp'
    "#include <vector>`nint main(){ std::vector<int> v{1}; return (int)v.size()-1; }`n" |
        Set-Content -Encoding ASCII $lnkSrc
    $lnkExe = Join-Path $tmp 'linkprov.exe'
    #  NOTE: '-Wl,/verbose' MUST stay quoted -- unquoted, PowerShell's parser chokes
    #  on the comma ("missing argument in parameter list"), measured 2026-10-06.
    $lnkOut = & $cxx -std=c++20 '-Wl,/verbose' -o $lnkExe $lnkSrc 2>&1
    $lnkCode = $LASTEXITCODE
    $lnkLines = @($lnkOut | ForEach-Object { [string]$_ })
    $readLibs = @($lnkLines | Where-Object { $_ -match 'lld-link: Reading' })
    $msLibs   = @($readLibs | Where-Object { $_ -match 'Program Files' })
    if ($lnkCode -ne 0) {
        Bad 'bundled mode: a real link of a <vector> program failed'
        $lnkLines | Where-Object { $_ -match 'error|错误' } | Select-Object -First 4 |
            ForEach-Object { Write-Host "         $_" }
    } elseif ($msLibs.Count -gt 0) {
        Bad ("bundled mode, but the link READ " + $msLibs.Count + " librar(y|ies) from Program Files, e.g.: " + $msLibs[0].Trim())
    } else {
        Ok ("bundled mode: the link read " + $readLibs.Count + " libraries, none from Program Files")
    }
} else {
    Ok 'system mode: the link reads the machine''s Visual Studio / SDK libraries (as designed)'
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
