# ============================================================================
#  check_handwritten_alternatives.ps1 -- for every symbol OUR OWN CRT provides,
#  ask the open-source libraries we already ship whether THEY provide it too.
#
#  WHY THIS EXISTS (user question, 2026-10-06: "can't we just take open-source
#  code from GitHub?")
#    The honest answer needs EVIDENCE, not memory. This project's rule is
#    "no 'I remember'": so this script derives the list of things we hand-wrote
#    FROM OUR OWN ARTIFACT (nm on vendor\crt\libcmt.lib -- nothing is typed in
#    by hand, so the list cannot rot), and then checks two open-source families
#    we ship:
#        * mingw-w64  (public domain)          -- nm --defined-only
#        * compiler-rt (Apache-2.0 WITH LLVM-exception, shipped in the package)
#                                              -- dumpbin /symbols, UNDEF-filtered
#    A symbol counts as "available in the open" ONLY if it is DEFINED there.
#    Counting mere references (UNDEF) is the exact mistake this project already
#    made twice today with `??_7type_info@@6B@` and `__chkstk`.
#
#  WHAT THE RESULT MEANS
#    For the MSVC-private ABI/SFU symbols (__security_cookie, __chkstk, _fltused,
#    type_info's vftable, ...) the answer measured so far is: NOBODY provides
#    them. They live only in Microsoft's static CRT, which may not be
#    redistributed. The alternatives that do exist are licence-blocked:
#        Wine     LGPL  (we would link statically / ship it)
#        ReactOS  GPL   (viral)
#        libgcc   GPL + Runtime Exception (covers only programs built by GCC)
#        MS SDK/VS UCRT + CRT sources: "All rights reserved" -- read only.
#
#  USAGE
#    pwsh -NoProfile -File tools\check_handwritten_alternatives.ps1
#    pwsh -NoProfile -File tools\check_handwritten_alternatives.ps1 -Quiet
#
#  ASCII-only on purpose.
# ============================================================================
param(
    [string] $OurLib     = 'E:\Chinese++\vendor\crt\libcmt.lib',
    [string] $MingwRoot  = 'E:\c++\mingw64',
    [string] $CompilerRt = 'E:\Chinese++\dist\Chinese++-0.2-win64\lib\clang\24\lib\windows',
    [switch] $Quiet
)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

function Find-Tool([string[]] $Cands, [string] $What) {
    foreach ($c in $Cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}
$nm = Find-Tool @((Join-Path $MingwRoot 'bin\nm.exe'), 'E:\c++\mingw64\bin\nm.exe') 'nm'
$dumpbin = $null
$vsRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC'
if (Test-Path $vsRoot) {
    $dumpbin = Get-ChildItem $vsRoot -Recurse -Filter 'dumpbin.exe' -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1 |
               ForEach-Object { $_.FullName }
}

Write-Host '=== what WE provide vs what the open source provides (18.49 supplement) ==='
if (-not (Test-Path $OurLib)) { throw "我们的 CRT 库不在：$OurLib（先跑 tools\vendor_crt.ps1）" }
if (-not $nm) { throw '找不到 mingw 的 nm.exe（-MingwRoot）' }

# ---------------------------------------------------------------------------
# 1) the list of symbols we provide -- derived, never typed by hand
#    nm prints "<addr> <TYPE> <name>"; UPPERCASE type = external, lowercase = local.
# ---------------------------------------------------------------------------
$nmOut = & $nm --defined-only $OurLib 2>$null
$ours = @($nmOut | ForEach-Object {
    if ($_ -match '^[0-9a-fA-F]{8,}\s+([TDBRWV])\s+(\S+)$') { $Matches[2] }
} | Where-Object { $_ -and $_ -notmatch '^(\$|\.|@feat)' } | Select-Object -Unique | Sort-Object)
Write-Host ''
Write-Host ("--- 1) 我们的 libcmt.lib 对外提供的符号：{0} 个（nm 从产物里读出来的，不是手抄的）" -f $ours.Count)

# ---------------------------------------------------------------------------
# 2) mingw-w64: does it DEFINE each one?
# ---------------------------------------------------------------------------
$mingwLibs = @()
foreach ($n in @('libmingwex.a', 'libmingw32.a', 'libmsvcrt.a', 'libucrt.a', 'libucrtbase.a')) {
    $p = Join-Path $MingwRoot "x86_64-w64-mingw32\lib\$n"
    if (Test-Path $p) { $mingwLibs += $p }
}
$mingwDefs = @{}
foreach ($lib in $mingwLibs) {
    foreach ($ln in (& $nm --defined-only $lib 2>$null)) {
        if ($ln -match '^[0-9a-fA-F]{8,}\s+([TDBRWV])\s+(\S+)$') { $mingwDefs[$Matches[2]] = $true }
    }
}
Write-Host ("        mingw-w64 查了 {0} 个库" -f $mingwLibs.Count)

# ---------------------------------------------------------------------------
# 3) compiler-rt (shipped): DEFINED or only REFERENCED?
# ---------------------------------------------------------------------------
$rtDefs = @{}; $rtRefs = @{}
if ($dumpbin -and (Test-Path $CompilerRt)) {
    foreach ($lib in (Get-ChildItem $CompilerRt -Filter '*.lib' -ErrorAction SilentlyContinue)) {
        foreach ($ln in (& $dumpbin /symbols $lib.FullName 2>$null)) {
            if ($ln -notmatch '\|\s+(\S+)\s*$') { continue }
            $s = $Matches[1]
            if ($ln -match 'UNDEF') { $rtRefs[$s] = $true } else { $rtDefs[$s] = $true }
        }
    }
    Write-Host ("        compiler-rt 查了 {0} 个库" -f (Get-ChildItem $CompilerRt -Filter '*.lib').Count)
} else {
    Write-Host '        [warn] 没有 dumpbin 或没有随包的 compiler-rt —— 这一列留空' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4) the table
# ---------------------------------------------------------------------------
$rows = @()
foreach ($s in $ours) {
    $mw = if ($mingwDefs.ContainsKey($s)) { 'DEFINED' } else { '-' }
    $rt = if ($rtDefs.ContainsKey($s)) { 'DEFINED' } elseif ($rtRefs.ContainsKey($s)) { 'ref only' } else { '-' }
    $rows += [pscustomobject]@{ Symbol = $s; Mingw = $mw; CompilerRt = $rt }
}
if (-not $Quiet) {
    Write-Host ''
    Write-Host '  {0,-52} {1,-9} {2}' -f 'symbol (we provide)', 'mingw', 'compiler-rt'
    Write-Host '  ' + ('-' * 78)
    foreach ($r in $rows) { Write-Host ('  {0,-52} {1,-9} {2}' -f $r.Symbol, $r.Mingw, $r.CompilerRt) }
}

$mwHave = @($rows | Where-Object { $_.Mingw -eq 'DEFINED' })
$rtHave = @($rows | Where-Object { $_.CompilerRt -eq 'DEFINED' })
Write-Host ''
Write-Host '--- 2) 结论 ---'
Write-Host ("  我们提供 {0} 个外部符号；其中 mingw-w64 也有【定义】的 {1} 个，compiler-rt 也有【定义】的 {2} 个" -f $rows.Count, $mwHave.Count, $rtHave.Count)
if ($mwHave.Count) { Write-Host ("    mingw 有：  " + (($mwHave | ForEach-Object { $_.Symbol }) -join ', ')) }
if ($rtHave.Count) { Write-Host ("    compiler-rt 有：" + (($rtHave | ForEach-Object { $_.Symbol }) -join ', ')) }
$rtRefOnly = @($rows | Where-Object { $_.CompilerRt -eq 'ref only' })
if ($rtRefOnly.Count) {
    Write-Host ''
    Write-Host ("  ⚠ {0} 个符号在 compiler-rt 里【只被引用、没有被定义】—— 它是消费者，不是提供者：" -f $rtRefOnly.Count) -ForegroundColor Yellow
    Write-Host ("    " + (($rtRefOnly | ForEach-Object { $_.Symbol }) -join ', ')) -ForegroundColor Yellow
    Write-Host '    （这正是本项目一天里栽过两次的坑：把 UNDEF 当成"有"）' -ForegroundColor Yellow
}

#  把结论写进 build 下的日志（不入库），并**断言**清单没退化：我们列的每个符号都必须真由我们定义
$log = Join-Path $root 'build\_review_own\handwritten_alternatives.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
$txt = @("we provide $($rows.Count) external symbols from libcmt.lib",
         "mingw-w64 defines: $($mwHave.Count)",
         "compiler-rt defines: $($rtHave.Count)",
         "compiler-rt references only: $($rtRefOnly.Count)",
         "") + ($rows | ForEach-Object { '{0,-52} {1,-9} {2}' -f $_.Symbol, $_.Mingw, $_.CompilerRt })
[System.IO.File]::WriteAllLines($log, $txt, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ''
Write-Host ("  日志：$log")
Write-Host ''
Write-Host '============================================================'
if ($rows.Count -eq 0) { Write-Host '  ❌ 一个符号都没读出来 —— nm 的解析或库路径有问题' -ForegroundColor Red; exit 1 }
Write-Host ("  ok（读出自产物 {0} 个符号；本工具只出证据，不判成败）" -f $rows.Count)
Write-Host '============================================================'
exit 0
