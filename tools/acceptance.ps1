# ============================================================================
#  ONE-COMMAND ACCEPTANCE CHECK for the Chinese-diagnostics work.
#
#  Usage (the ONLY command a reviewer needs):
#      powershell -File E:\Chinese++\tools\acceptance.ps1
#
#  It prints one PASS/FAIL line per claim, each backed by evidence it produced
#  itself, then a total, then exits 0 only if everything passed.
#
#  For a reviewer: DO NOT trust the project's markdown docs. Trust this output.
#  Then read this script -- it is short, and every claim below is checkable by
#  reading it. If a claim is not in here, treat it as unverified.
#
#  What it does NOT do: rebuild the compiler from source (not needed), and it
#  does not test against the upstream clang test suite.
#
#  Runtime: roughly 6-10 minutes (the patch step re-hashes clang + llvm +
#  clang-tools-extra against a clean reference tree).
#
#  ENCODING: pure ASCII by project convention. Chinese never appears as a
#  literal here -- expected Chinese strings are read out of the test .cpp files
#  and compared as raw UTF-8 BYTES, so the result cannot depend on the console
#  code page.
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root  = 'E:\Chinese++'
$Mine  = Join-Path $Root 'LLVM-main'
$Base  = 'E:\LLVM-main'                       # clean reference tree (read-only)
$Cxx   = Join-Path $Root 'build\Release\bin\chinese++.exe'
$Clang = Join-Path $Root 'build\Release\bin\clang++.exe'
$TdDir = Join-Path $Mine 'clang\include\clang\Basic'
$IncDir = Join-Path $Root 'build\tools\clang\include\clang\Basic'
$Tests = Join-Path $Root 'tests'
$Out   = Join-Path $Root 'build\_acceptance'
New-Item -ItemType Directory -Force $Out | Out-Null

$pass = 0
$fail = 0
$failed = @()

# Progress uses Write-Host only: it must never leak into a function's return
# value (that exact mistake once turned the patch gate into a rubber stamp).
function Report {
    param([string]$Name, [bool]$Ok, [string]$Evidence)
    if ($Ok) {
        $script:pass += 1
        Write-Host ("  PASS  {0}" -f $Name)
    } else {
        $script:fail += 1
        $script:failed += $Name
        Write-Host ("  FAIL  {0}" -f $Name)
    }
    if ($Evidence) { Write-Host ("        {0}" -f $Evidence) }
}

function Get-Bytes {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return [byte[]]@() }
    return [System.IO.File]::ReadAllBytes($Path)
}

function Test-Contains {
    param([byte[]]$Hay, [byte[]]$Needle)
    if ($Hay.Length -lt $Needle.Length -or $Needle.Length -eq 0) { return $false }
    for ($i = 0; $i -le $Hay.Length - $Needle.Length; $i = $i + 1) {
        $same = $true
        for ($j = 0; $j -lt $Needle.Length; $j = $j + 1) {
            if ($Hay[$i + $j] -ne $Needle[$j]) { $same = $false; break }
        }
        if ($same) { return $true }
    }
    return $false
}

function Test-Same {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i = $i + 1) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}

# The expected Chinese for a test case is the text after "// expect:" in the
# .cpp itself -- so this ASCII script can still compare Chinese bytes.
function Get-Expect {
    param([string]$File)
    $path = Join-Path $Tests ("12-diagnostics\" + $File)
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    foreach ($line in ($text -split "`n")) {
        $t = $line.Trim()
        if ($t.StartsWith('// expect:')) { return $t.Substring(9).Trim() }
    }
    return ''
}

function Compile-To {
    param([string]$File, [string]$Extra, [string]$Tag)
    $src = Join-Path $Tests ("12-diagnostics\" + $File)
    $log = Join-Path $Out ($File + '.' + $Tag + '.txt')
    if (Test-Path $log) { Remove-Item $log -Force }
    & cmd /c "`"$Cxx`" -std=c++20 -ferror-limit=0 -fsyntax-only $Extra `"$src`" > `"$log`" 2>&1" | Out-Null
    return $log
}

Write-Host ''
Write-Host '======================================================================'
Write-Host '  Chinese-diagnostics acceptance check'
Write-Host '  every line below is backed by evidence this script produced itself'
Write-Host '======================================================================'
Write-Host ''

# ---------------------------------------------------------------------------
Write-Host '--- 1. the compiler under test is the freshly built one ---'
# The linker's delete-then-create breaks the chinese++.exe hard link, leaving a
# STALE compiler behind with no warning. Check that first, or everything else
# is measured against the wrong binary.
#
# Compare SHA256, not just file size: size equality is only probabilistic (an
# independent reviewer flagged that the first version of this check inferred
# "same binary" from equal lengths alone).
$lenExe = (Get-Item $Cxx).Length
$lenClang = (Get-Item $Clang).Length
$hashExe = (Get-FileHash $Cxx -Algorithm SHA256).Hash
$hashClang = (Get-FileHash $Clang -Algorithm SHA256).Hash
Report 'chinese++.exe is the same binary as clang++.exe (not a stale hard link)' `
    (($lenExe -eq $lenClang) -and ($hashExe -eq $hashClang)) `
    ("sizes {0}/{1} bytes   sha256 {2}/{3}" -f $lenExe, $lenClang, $hashExe.Substring(0, 16), $hashClang.Substring(0, 16))
$ver = (& cmd /c "`"$Cxx`" --version 2>&1" | Select-Object -First 1)
Write-Host ("        version: {0}" -f $ver)

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2. upstream diagnostic definitions are UNTOUCHED ---'
# The whole design claim: we add a table, we do not edit any Diagnostic*.td.
#
# Counts are asserted explicitly. Without that, a wrong path yields an EMPTY
# file list, "$tdDiff.Count -eq 0" is vacuously true, and this step prints PASS
# while having checked nothing. (Flagged by an independent reviewer: vacuous
# truth in the first version of this check.)
$tdFiles = @(Get-ChildItem $TdDir -Filter 'Diagnostic*.td')
$tdSame = 0
$tdDiff = @()
foreach ($f in $tdFiles) {
    $b = Join-Path (Join-Path $Base 'clang\include\clang\Basic') $f.Name
    if (-not (Test-Path $b)) { $tdDiff += ($f.Name + '(missing in base)'); continue }
    if ((Get-FileHash $f.FullName -Algorithm SHA256).Hash -eq (Get-FileHash $b -Algorithm SHA256).Hash) {
        $tdSame = $tdSame + 1
    } else {
        $tdDiff += $f.Name
    }
}
Report 'all Diagnostic*.td byte-identical to the clean tree' (($tdFiles.Count -ge 10) -and ($tdDiff.Count -eq 0)) `
    ("found {0} files, {1} identical{2}" -f $tdFiles.Count, $tdSame, $(if ($tdDiff.Count) { '  DIFFER: ' + ($tdDiff -join ', ') } else { '' }))

# Generated tables must contain no non-ASCII bytes at all: they are produced
# from the untouched .td files, so Chinese has no business being there.
# Same vacuous-truth guard: assert how many files we actually looked at.
$incFiles = @(Get-ChildItem $IncDir -Filter 'Diagnostic*Kinds.inc')
$incBad = @()
foreach ($f in $incFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $n = 0
    foreach ($x in $bytes) { if ($x -gt 127) { $n = $n + 1 } }
    if ($n -gt 0) { $incBad += ("{0}({1})" -f $f.Name, $n) }
}
Report 'generated Diagnostic*Kinds.inc contain zero non-ASCII bytes' (($incFiles.Count -ge 10) -and ($incBad.Count -eq 0)) `
    ("looked at {0} generated files{1}" -f $incFiles.Count, $(if ($incBad.Count) { '  NON-ASCII: ' + ($incBad -join ', ') } else { '' }))

# The Chinese table itself must not be silently truncated.
# The table validator now enforces a minimum entry count (see MIN_ENTRIES in
# tools\diag_id_lookup.py) -- this records the number it actually read.
$zhCount = 0
& python -c "import sys; sys.path.insert(0, r'E:\Chinese++\tools'); import diag_id_lookup as d; print(len(d.parse_zh_def()))" 2>&1 |
    ForEach-Object { if ($_ -match '^\s*(\d+)\s*$') { $zhCount = [int]$Matches[1] } }
Report 'the Chinese table is not truncated (>= 32 entries)' ($zhCount -ge 32) `
    ("entries read: {0}" -f $zhCount)

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3. the message body really is Chinese ---'
$log1 = Compile-To '03_undeclared.cpp' '' 'acc'
$bytes1 = Get-Bytes $log1
$needle1 = [System.Text.Encoding]::UTF8.GetBytes((Get-Expect '03_undeclared.cpp'))
$hasZh = Test-Contains $bytes1 $needle1
Report 'Chinese body appears in the compiler output' $hasZh `
    ("needle (from the test file): {0}" -f (Get-Expect '03_undeclared.cpp'))
$hasEn = Test-Contains $bytes1 ([System.Text.Encoding]::ASCII.GetBytes('use of undeclared identifier'))
Report 'the English body is GONE (not appended)' (-not $hasEn) `
    ('searching for: use of undeclared identifier')

$log2 = Compile-To '09_unused_var.cpp' '-Wall' 'acc'
$bytes2 = Get-Bytes $log2
Report 'prefix "warning: " is untouched' (Test-Contains $bytes2 ([System.Text.Encoding]::ASCII.GetBytes('warning: '))) ''
Report 'option name [-Wunused-variable] is untouched' `
    (Test-Contains $bytes2 ([System.Text.Encoding]::ASCII.GetBytes('[-Wunused-variable]'))) ''
Report 'prefix was NOT translated to Chinese' `
    (-not (Test-Contains $bytes2 ([System.Text.Encoding]::UTF8.GetBytes('warning:' + [char]0xFF1A)))) `
    'looking for a Chinese warning prefix'

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4. untranslated diagnostics fall back to English (byte-identical) ---'
$onLog  = Compile-To '10_fallback_english.cpp' '' 'on'
$offLog = Compile-To '10_fallback_english.cpp' '-fno-chinese-diagnostics' 'off'
$onB = Get-Bytes $onLog
$offB = Get-Bytes $offLog
Report 'a diagnostic with no table entry is byte-identical with and without the switch' `
    (Test-Same $onB $offB) ("length {0} vs {1}" -f $onB.Length, $offB.Length)

Write-Host ''
Write-Host '--- 5. the switch really switches back to English ---'
$swOn  = Compile-To '09_unused_var.cpp' '-Wall' 'swon'
$swOff = Compile-To '09_unused_var.cpp' '-Wall -fno-chinese-diagnostics' 'swoff'
$swOnB = Get-Bytes $swOn
$swOffB = Get-Bytes $swOff
Report '-fno-chinese-diagnostics restores the English body' `
    (Test-Contains $swOffB ([System.Text.Encoding]::ASCII.GetBytes('unused variable'))) ''
$swNeedle = [System.Text.Encoding]::UTF8.GetBytes((Get-Expect '09_unused_var.cpp'))
Report '-fno-chinese-diagnostics removes the Chinese body' (-not (Test-Contains $swOffB $swNeedle)) ''
Report 'the two logs differ (the switch is not a no-op)' (-not (Test-Same $swOnB $swOffB)) ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 6. the table and its validator ---'
& python (Join-Path $Tests 'checks\verify_zh_diagnostics.py') 2>&1 | ForEach-Object { Write-Host ("        " + $_) }
Report 'table validator passes (IDs exist, placeholders match English)' ($LASTEXITCODE -eq 0) ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 7. the patch verification gate can FAIL (prove, do not assume) ---'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\make_patch.ps1') -SelfTest 2>&1 |
    Select-String -Pattern 'SELF-TEST|returned:|git apply exit' | ForEach-Object { Write-Host ("        " + $_.Line.Trim()) }
Report 'gate self-test: good patch accepted, sabotaged patch rejected' ($LASTEXITCODE -eq 0) ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 8. patches reproduce our tree, and cover EVERY changed directory ---'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tools\make_patch.ps1') 2>&1 |
    Select-String -Pattern 'coverage sweep|NOT SCANNED|ok: every differing|changed files|-> keywords|-> diagnostics|byte-identical|corrupt|content differs|all patches verified|something failed' |
    ForEach-Object { Write-Host ("        " + $_.Line.Trim()) }
Report 'make_patch.ps1 verified both patches against the clean tree' ($LASTEXITCODE -eq 0) `
    'this step re-hashes clang + llvm + clang-tools-extra'

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 9. the full regression suite ---'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tests 'run_all.ps1') 2>&1 |
    Select-String -Pattern 'passed:|failed:|=> FAIL' | ForEach-Object { Write-Host ("        " + $_.Line.Trim()) }
Report 'run_all.ps1 is green' ($LASTEXITCODE -eq 0) ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '======================================================================'
Write-Host ("  passed: {0}    failed: {1}" -f $pass, $fail)
if ($failed.Count -gt 0) { Write-Host ("  failed checks: " + ($failed -join ' | ')) }
Write-Host ("  raw logs: {0}" -f $Out)
Write-Host '======================================================================'
if ($fail -eq 0) { exit 0 }
exit 1
