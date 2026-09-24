# ============================================================================
#  14-main-alias: the Chinese spelling of the program entry point.
#
#  What this proves
#    1) the Chinese spelling works as the entry point (compiles, links, runs)
#    2) it is the SAME ENTITY as `main`, not "a second name for the same symbol"
#         - writing both is a REDEFINITION error (caught at compile time)
#         - it is a RESERVED name: declaring a variable with it is rejected
#    3) every `main`-specific check applies to the Chinese spelling too
#         - return type must be int
#         - only the legal parameter forms are accepted
#       This is the point that a text-substitution or asm-label approach MISSES:
#       both of those let a void-returning entry point through silently.
#    4) English code is untouched (regression guard)
#
#  Pure ASCII on purpose (see ..\README.md): PowerShell 5.1 reads a BOM-less
#  file as GBK, and Chinese literals in *code* would break the parser outright.
#  All Chinese lives in the .cpp inputs; needles are built from code points.
#
#  Usage:
#      powershell -File E:\Chinese++\tests\14-main-alias\check.ps1
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)      # E:\Chinese++
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'

$out = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$fail = 0
function Fail($m) { Write-Host ("  [FAIL] " + $m); $script:fail = 1 }
function Pass($m) { Write-Host ("  [ok]   " + $m) }

if (-not (Test-Path $cxx)) { Fail "no compiler at $cxx"; exit 1 }

# Code-point needles so this script stays pure ASCII.
$ZH_MAIN   = -join [char[]](0x4E3B, 0x51FD, 0x6570)                  # entry point
$ZH_REDEF  = -join [char[]](0x91CD, 0x5B9A, 0x4E49)                  # redefinition
$ZH_MUSTINT= -join [char[]](0x5FC5, 0x987B, 0x8FD4, 0x56DE)          # must return

# Helper: compile (optionally link), return @{ rc; txt }
function Compile($src, $exe) {
    $a = @('-std=c++20')
    if ($exe) { $a += @('-o', $exe) }
    else { $a += '-fsyntax-only' }
    $a += (Join-Path $here $src)
    $t = Join-Path $out ($src + '.txt')
    & cmd /c "`"$cxx`" $($a -join ' ') > `"$t`" 2>&1"
    return @{ rc = $LASTEXITCODE; txt = [System.IO.File]::ReadAllText($t) }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 1) the Chinese spelling IS the entry point'

$r = Compile 'entry_zh.cpp' (Join-Path $out 'entry_zh.exe')
if ($r.rc -ne 0) { Fail ("entry_zh.cpp did not build: " + $r.txt.Trim()) }
else {
    $run = Join-Path $out 'entry_zh.run.txt'
    & cmd /c "`"$(Join-Path $out 'entry_zh.exe')`" > `"$run`" 2>&1"
    if ($LASTEXITCODE -ne 0) { Fail "entry_zh.exe exited $LASTEXITCODE" }
    else { Pass 'entry_zh.cpp compiles, links and runs as the entry point' }
}

$r = Compile 'args_ok.cpp' (Join-Path $out 'args_ok.exe')
if ($r.rc -ne 0) { Fail ("args_ok.cpp did not build: " + $r.txt.Trim()) }
else { Pass 'the Chinese (int, char**) form also works' }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) same entity, not a second name'

$r = Compile 'both.cpp' $null
if ($r.rc -eq 0) { Fail 'writing BOTH main and the Chinese spelling compiled -- they are not one entity' }
elseif (-not $r.txt.Contains($ZH_REDEF)) { Fail ('expected a redefinition error, got: ' + $r.txt.Trim()) }
else { Pass 'writing both is a compile-time redefinition error' }

$r = Compile 'reserved.cpp' $null
if ($r.rc -eq 0) { Fail ('the Chinese spelling is usable as a variable name -- not reserved: ' + $r.txt.Trim()) }
else { Pass 'the Chinese spelling is a reserved name (variable use rejected)' }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) main-specific checks apply to the Chinese spelling'

$r = Compile 'bad_return.cpp' $null
if ($r.rc -eq 0) { Fail 'void return type was ACCEPTED -- this is the asm-label trap' }
elseif (-not $r.txt.Contains($ZH_MUSTINT)) { Fail ('wrong message: ' + $r.txt.Trim()) }
else { Pass 'void return type is rejected with the main-specific diagnostic' }

$r = Compile 'bad_param.cpp' $null
if ($r.rc -eq 0) { Fail 'a wrong first-parameter type was ACCEPTED' }
else { Pass 'a wrong first-parameter type is rejected' }

# Parity, not guesswork.
#
# The first version of this suite asserted that a single-int-parameter entry
# point must FAIL. It does not: clang reports warn_main_one_arg, which is a
# WARNING, so exit code 0. The expectation was wrong, not the compiler.
# The right criterion for "same entity" is not a severity I guessed -- it is
# that the Chinese spelling behaves EXACTLY like `main`. So compare them.
Write-Host ''
Write-Host '--- 3b) parity with `main` on a diagnostic that is only a warning'
$rz = Compile 'parity_one_arg_zh.cpp' $null
$re = Compile 'parity_one_arg_en.cpp' $null
if ($rz.rc -ne $re.rc) {
    Fail ("exit codes differ: zh=$($rz.rc) en=$($re.rc)")
} else {
    # Strip file name and the echoed source line; the two files necessarily
    # differ in both. What must match is the diagnostic itself.
    # Take the text from the level word onwards -- path-independent, and it
    # avoids the Windows-drive-letter colon trap (`^[^:]+:` stops at 'E').
    # (Same bug I already fixed once in tests\13-preprocessor\sweep.py.)
    function Core($t) {
        $ls = $t -split "`r?`n" | ForEach-Object {
            $m = [regex]::Match($_, '(warning|error|note):.*')
            if ($m.Success) { $m.Value }
        }
        ($ls -join "`n")
    }
    $cz = Core $rz.txt; $ce = Core $re.txt
    if ($cz -ne $ce) {
        Fail ("diagnostics differ:`n        zh: $cz`n        en: $ce")
    } else {
        Pass "identical diagnostic (exit=$($rz.rc)): $cz"
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) English is untouched'

$r = Compile 'entry_en.cpp' (Join-Path $out 'entry_en.exe')
if ($r.rc -ne 0) { Fail ('entry_en.cpp regressed: ' + $r.txt.Trim()) }
else { Pass 'the English spelling still works' }

# ---------------------------------------------------------------------------
Write-Host ''
if ($fail -eq 0) { Write-Host '  => PASS'; exit 0 }
Write-Host '  => FAIL'
exit 1
