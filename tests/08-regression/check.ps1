# ============================================================================
#  08 regression: everything here MUST compile.
#
#  These are the earlier-session cases, renamed to say what they test:
#    chinese.cpp     - a full Chinese program, verbs/nouns all Chinese
#    english.cpp     - a full English program: the most important regression
#                      (the standard library headers are full of English
#                      keywords; this file must keep compiling)
#    translit_zh.cpp - Chinese side of a translation pair
#    translit_en.cpp - English side of the same pair (must stay equivalent)
#
#  Compile-only (not run): some of these are translation pairs without a
#  single well-defined main(), so "exit code 0" is the assertion here.
#
#  Pure ASCII on purpose (see ..\README.md).
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'

$fail = 0
foreach ($f in (Get-ChildItem $here -Filter *.cpp | Sort-Object Name)) {
    Write-Host ("--- {0}" -f $f.Name)
    & $cxx -std=c++20 -fsyntax-only $f.FullName 2>&1 | ForEach-Object { Write-Host "    $_" }
    $code = $LASTEXITCODE
    if ($code -eq 0) { Write-Host '    OK' }
    else { Write-Host "    FAIL (exit=$code)"; $fail += 1 }
}

if ($fail -eq 0) { Write-Host 'all compiled'; exit 0 }
Write-Host "$fail file(s) failed"; exit 1
