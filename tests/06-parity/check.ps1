# ============================================================================
#  Parity check: the "no lock-in" proof.
#
#    1) compile parity.cpp with OUR compiler (chinese++.exe) and run it
#    2) convert it to English with tools\zh_to_en.py (mechanical, whole-token)
#    3) compile that with a STOCK compiler (Visual Studio's clang, not our fork)
#    4) compare the two outputs byte for byte
#
#  Pure ASCII on purpose (see ..\README.md): PowerShell 5.1 reads a BOM-less
#  file as GBK, and Chinese file-name literals inside a script would be mangled.
#
#  Usage:
#      powershell -File E:\Chinese++\tests\06-parity\check.ps1
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)      # E:\Chinese++

$cxx    = Join-Path $root 'build\Release\bin\chinese++.exe'
$conv   = Join-Path $root 'tools\zh_to_en.py'
$python = 'E:\python\python.exe'
$stock  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\x64\bin\clang.exe'

$src = Join-Path $here 'parity.cpp'
$out = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$gen    = Join-Path $out 'parity.english.cpp'
$zhExe  = Join-Path $out 'parity_zh.exe'
$enExe  = Join-Path $out 'parity_en.exe'
$zhTxt  = Join-Path $out 'out_zh.txt'
$enTxt  = Join-Path $out 'out_en.txt'

Write-Host '--- 1) compile with our compiler'
& $cxx -std=c++20 -O0 -o $zhExe $src 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Write-Host 'FAILED: our compiler'; exit 1 }
# Redirect through cmd, NOT through a PowerShell pipeline -- same lesson as
# tools\rebuild_clang.ps1 documents for MSBuild. `& $exe > file` is shell
# DEPENDENT: Windows PowerShell 5.1 pushes the text through Out-File and lands
# UTF-16LE with a BOM (68 bytes for this program), while PowerShell 7 writes
# the program's raw bytes (45). The byte count is evidence, so it must not
# depend on which shell happens to be driving the test.
& cmd /c "`"$zhExe`" > `"$zhTxt`""
Write-Host "    ran, exit=$LASTEXITCODE"

Write-Host '--- 2) convert to English'
& $python $conv $src $gen 2>&1 | ForEach-Object { Write-Host "    $_" }
if (-not (Test-Path $gen)) { Write-Host 'FAILED: conversion produced nothing'; exit 2 }

Write-Host '--- 3) compile with STOCK clang (not our fork)'
& $stock --version 2>&1 | Select-Object -First 1 | ForEach-Object { Write-Host "    $_" }
& $stock -x c++ -std=c++20 -O0 -o $enExe $gen 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Write-Host 'FAILED: stock compiler'; exit 3 }
& cmd /c "`"$enExe`" > `"$enTxt`""
Write-Host "    ran, exit=$LASTEXITCODE"

Write-Host '--- 4) compare'
$a = [System.IO.File]::ReadAllBytes($zhTxt)
$b = [System.IO.File]::ReadAllBytes($enTxt)
Write-Host "    bytes: zh=$($a.Length)  en=$($b.Length)"
if ($a.Length -ne $b.Length) { Write-Host 'FAILED: length differs'; exit 4 }
for ($i = 0; $i -lt $a.Length; $i++) {
    if ($a[$i] -ne $b[$i]) { Write-Host "FAILED: first difference at byte $i"; exit 5 }
}
Write-Host '    OK: outputs are byte-identical (no lock-in)'
exit 0
