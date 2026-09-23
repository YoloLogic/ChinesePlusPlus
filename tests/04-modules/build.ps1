# ============================================================================
#  Build and run the C++20 module test.
#
#  The module name is Chinese (a Chinese identifier) and so are the keywords used here
#  (the Chinese spellings of export/module/import). This script is PURE ASCII on purpose: PowerShell 5.1
#  reads a BOM-less file as GBK, and a Chinese path literal inside a script
#  would then be mangled into a bad path. The module name never has to appear
#  in this file -- clang reads it from the .pcm via -fmodule-file=<path>.
#
#  Standard explicit C++20 modules flow.
#
#  -x c++-module is REQUIRED whenever the interface unit is compiled.
#  Without it clang exits 0 but writes PREPROCESSED TEXT (the file starts
#  with '# 1 ') instead of a BMI, and step 2 then fails with
#  'file doesn''t start with precompiled file magic'. Silent, so do not drop it.
#
#    1) --precompile          -> math.pcm   (the BMI)
#    2) compile the module    -> math_module.obj   (using the BMI)
#    3) compile the importer  -> main_import.obj
#    4) link                  -> module_test.exe
#
#  Usage:
#      powershell -File E:\Chinese++\tests\04-modules\build.ps1
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cxx  = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$out  = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$mod     = Join-Path $here 'math_module.cpp'
$main    = Join-Path $here 'main_import.cpp'
$pcm     = Join-Path $out  'math.pcm'
$modObj  = Join-Path $out  'math_module.obj'
$mainObj = Join-Path $out  'main_import.obj'
$exe     = Join-Path $out  'module_test.exe'

function Invoke-Step {
    param([string]$Title, [string[]]$Argv)
    Write-Host "--- $Title"
    & $cxx @Argv 2>&1 | ForEach-Object { Write-Host "    $_" }
    $code = $LASTEXITCODE
    Write-Host "    exit=$code"
    return $code
}

$c1 = Invoke-Step '1) --precompile  -> math.pcm'      @('-std=c++20', '-x', 'c++-module', '--precompile', $mod, '-o', $pcm)
if ($c1 -ne 0) { Write-Output 'FAILED at step 1'; exit 1 }

$c2 = Invoke-Step '2) compile module  -> .obj'        @('-std=c++20', '-x', 'c++-module', '-c', $mod, '-o', $modObj)
if ($c2 -ne 0) { Write-Output 'FAILED at step 2'; exit 2 }

$c3 = Invoke-Step '3) compile importer-> .obj'        @('-std=c++20', '-c', $main, ('-fmodule-file=' + $pcm), '-o', $mainObj)
if ($c3 -ne 0) { Write-Output 'FAILED at step 3'; exit 3 }

$c4 = Invoke-Step '4) link            -> .exe'        @($modObj, $mainObj, '-o', $exe)
if ($c4 -ne 0) { Write-Output 'FAILED at step 4'; exit 4 }

Write-Output ''
Write-Output '--- run'
& $exe
Write-Output "run exit=$LASTEXITCODE"
exit $LASTEXITCODE
