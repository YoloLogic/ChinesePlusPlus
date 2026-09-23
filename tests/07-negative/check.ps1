# ============================================================================
#  Negative test: neg_rename.cpp MUST fail to compile.
#
#  The old Chinese spelling for `virtual` (动态绑定) was renamed to 虚拟 in the
#  2026-09-22 round, so the old name must now be just an ordinary identifier.
#  If this file compiles, the rename did not take effect -- most likely
#  chinese++.exe is a stale hard link left behind by the linker.
#
#  Pure ASCII on purpose (see ..\README.md).
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$src  = Join-Path $here 'neg_rename.cpp'

Write-Host "--- compile (expected to FAIL): $(Split-Path $src -Leaf)"
$out = & $cxx -std=c++20 -fsyntax-only $src 2>&1 | Out-String
$code = $LASTEXITCODE
Write-Host "    exit=$code  (must be non-zero)"

if ($code -eq 0) {
    Write-Host 'FAILED: the old spelling still compiles -- the rename is not in effect.'
    Write-Host '        (check whether chinese++.exe is a stale hard link)'
    exit 1
}

Write-Host '    OK: rejected as expected.'
exit 0
