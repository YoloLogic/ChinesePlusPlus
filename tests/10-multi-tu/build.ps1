# ============================================================================
#  10 multi-TU: several translation units per program, written in Chinese.
#
#  Why this folder needs its own driver: the generic path in run_all.ps1
#  compiles each .cpp and runs it, but these programs are SPLIT ACROSS
#  translation units -- the objects must be LINKED together.
#
#  The interesting case is the cross one:
#      english_driver.cpp (English source) + impl_cn.cpp (Chinese source)
#  Both compiled by our clang. It must link and run: the Chinese keywords
#  have to produce exactly the same symbols as the English ones.
#
#  Pure ASCII on purpose. Chinese in a script is a PowerShell 5.1 hazard:
#  without a UTF-8 BOM the file is read as GBK, and a Chinese path literal
#  would be mangled. All Chinese lives inside the .cpp files (see ..\README.md).
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$script:fail = 0

function Compile([string]$name) {
    $obj  = Join-Path $out ([System.IO.Path]::GetFileNameWithoutExtension($name) + '.obj')
    $src  = Join-Path $here $name
    & $cxx -std=c++20 -c $src -o $obj 2>&1 | ForEach-Object { Write-Host "      $_" }
    $code = $LASTEXITCODE
    return [pscustomobject]@{ obj = $obj; code = $code }
}

function Case([string]$title, [string[]]$sources, [string]$exeName) {
    Write-Host "--- $title"
    $objs = @()
    foreach ($s in $sources) {
        $r = Compile $s
        if ($r.code -ne 0) { Write-Host "    FAIL: compile $s"; $script:fail += 1; return }
        $objs += $r.obj
    }
    $exe = Join-Path $out $exeName
    & $cxx @objs '-o' $exe 2>&1 | ForEach-Object { Write-Host "      $_" }
    if ($LASTEXITCODE -ne 0) { Write-Host '    FAIL: link'; $script:fail += 1; return }
    & $exe 2>&1 | ForEach-Object { Write-Host "      $_" }
    if ($LASTEXITCODE -ne 0) { Write-Host '    FAIL: run'; $script:fail += 1; return }
    Write-Host '    OK'
}

# all Chinese
Case 'all Chinese:  driver_cn + impl_cn'                   @('driver_cn.cpp', 'impl_cn.cpp')          'cn.exe'
# the point of the whole folder: English driver linked with a Chinese-compiled impl
Case 'cross:        english_driver + impl_cn (Chinese!)'   @('english_driver.cpp', 'impl_cn.cpp')     'cross.exe'
# all English control
Case 'all English:  english_driver + english_impl'         @('english_driver.cpp', 'english_impl.cpp') 'en.exe'
# exception / RTTI across translation units
Case 'exceptions across TUs'                               @('exc_driver.cpp', 'exc_throw.cpp')       'exc.exe'
# single-TU cases
Case 'RTTI on Chinese type names'                          @('rtti_driver.cpp', 'exc_throw.cpp')                       'rtti.exe'
Case 'class keyword in every syntax position'              @('type_keyword.cpp')                      'typekw.exe'
Case 'typename in both legal positions'                    @('typename.cpp')                          'tname.exe'

Write-Host ''
if ($script:fail -eq 0) { Write-Host 'all multi-TU cases passed'; exit 0 }
Write-Host "$script:fail case(s) failed"; exit 1
