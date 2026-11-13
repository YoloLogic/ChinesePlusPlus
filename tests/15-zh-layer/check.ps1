# ============================================================================
#  15-zh-layer / check.ps1 -- compile + run the Chinese-layer self-check case.
#
#  Prefer the self-contained packaged toolchain (bundled CRT/STL): the dev build
#  under build\Release expects the machine's MSVC environment and fails to link
#  std::mutex symbols when run outside it.
#  The case self-verifies, so this script stays pure ASCII (see tests/README.md).
# ============================================================================
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$candidates = @(
    'E:\Chinese++\dist\Chinese++-0.4-win64\bin\chinese++.exe',
    'E:\Chinese++\build\Release\bin\chinese++.exe'
)
$cxx = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $cxx) { Write-Host '  [SKIP] no chinese++.exe found'; exit 1 }

$outDir = Join-Path $here 'out'
New-Item -ItemType Directory -Force $outDir | Out-Null
$exe = Join-Path $outDir 'case.exe'
Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue

Write-Host ('  cc: ' + $cxx)
& $cxx -std=c++2c -o $exe (Join-Path $here 'case.cpp')
if ($LASTEXITCODE -ne 0) { Write-Host ('  [FAIL] compile exit ' + $LASTEXITCODE); exit 1 }

& $exe
$rc = $LASTEXITCODE
Write-Host ('  run exit: ' + $rc)
exit $rc