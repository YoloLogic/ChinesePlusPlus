# ============================================================================
#  Run every test under tests\.
#
#  Convention per folder:
#    - build.ps1 present -> run it (multi-step, e.g. 04-modules)
#    - check.ps1 present -> run it (comparison test, e.g. 06-parity)
#    - otherwise         -> compile every *.cpp with chinese++.exe and run it
#
#  Discovery only: no source file name is hard-coded, so Chinese file names
#  would work here too. This script itself stays pure ASCII (see README.md):
#  PowerShell 5.1 reads a BOM-less file as GBK, and a Chinese path literal
#  inside a script would be mangled into a bad path.
#
#  Usage:
#      powershell -File E:\Chinese++\tests\run_all.ps1
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cxx  = 'E:\Chinese++\build\Release\bin\chinese++.exe'

$pass = 0
$fail = 0
$failed = @()

# ---------------------------------------------------------------------------
# Child scripts run under PowerShell 7 (pwsh) when it is available, otherwise
# under Windows PowerShell 5.1, which ships with Windows. Both are verified to
# run every suite in this project (2026-09-24).
#
# The probe is not paranoia: being on PATH is not the same as working. The
# Store install puts an app-execution ALIAS on PATH, and an alias can fail to
# start in contexts where a real executable would not -- so we start it once
# and check the exit code before trusting it.
#
# Keep this block identical in the three scripts that spawn children:
#   tests\run_all.ps1, tools\acceptance.ps1,
#   tests\checks\verify_make_patch_gate.ps1
# ---------------------------------------------------------------------------
$psExe = 'powershell'
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) {
    & $pwshCmd.Source -NoProfile -Command 'exit 0' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $psExe = $pwshCmd.Source }
}
# Say out loud which one was chosen: an unobservable fallback cannot be tested,
# and the whole point of this block is that it has TWO paths.
Write-Host ("  child shells: " + $psExe)

foreach ($dir in (Get-ChildItem $here -Directory | Sort-Object Name)) {

    $driver = $null
    foreach ($cand in @('build.ps1', 'check.ps1')) {
        $p = Join-Path $dir.FullName $cand
        if (Test-Path $p) { $driver = $p; break }
    }

    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host ("  {0}" -f $dir.Name)
    Write-Host ('=' * 72)

    if ($driver) {
        & $psExe -NoProfile -ExecutionPolicy Bypass -File $driver 2>&1 |
            ForEach-Object { Write-Host "  $_" }
        $code = $LASTEXITCODE
    } else {
        $code = 0
        $out = Join-Path $dir.FullName 'out'
        New-Item -ItemType Directory -Force $out | Out-Null
        foreach ($f in (Get-ChildItem $dir.FullName -Filter *.cpp)) {
            $exe = Join-Path $out ($f.BaseName + '.exe')
            Write-Host ("  compile {0}" -f $f.Name)
            & $cxx -std=c++20 -O0 -o $exe $f.FullName 2>&1 | ForEach-Object { Write-Host "      $_" }
            if ($LASTEXITCODE -ne 0) { $code = 1; break }
            Write-Host ("  run {0}" -f $f.BaseName)
            & $exe 2>&1 | ForEach-Object { Write-Host "      $_" }
            if ($LASTEXITCODE -ne 0) { $code = 1; break }
        }
    }

    if ($code -eq 0) { Write-Host '  => PASS'; $pass++ }
    else { Write-Host "  => FAIL (exit=$code)"; $fail++; $failed += $dir.Name }
}

# ---- checks: scripts under tests\checks\ (static / e2e / clangd) ----
$checksDir = Join-Path $here 'checks'
if (Test-Path $checksDir) {
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host '  checks'
    Write-Host ('=' * 72)
    foreach ($s in (Get-ChildItem $checksDir -File | Sort-Object Name)) {
        if ($s.Extension -eq '.ps1') {
            Write-Host ("  run {0}" -f $s.Name)
            & $psExe -NoProfile -ExecutionPolicy Bypass -File $s.FullName 2>&1 |
                Select-Object -Last 8 | ForEach-Object { Write-Host "      $_" }
        } elseif ($s.Extension -eq '.py') {
            Write-Host ("  run {0}" -f $s.Name)
            & 'E:\python\python.exe' $s.FullName 2>&1 |
                Select-Object -Last 8 | ForEach-Object { Write-Host "      $_" }
        } else { continue }
        if ($LASTEXITCODE -eq 0) { Write-Host '    => PASS'; $pass++ }
        else { Write-Host "    => FAIL (exit=$LASTEXITCODE)"; $fail++; $failed += $s.Name }
    }
}
Write-Host ''
Write-Host ('=' * 72)
Write-Host ("  passed: $pass    failed: $fail")
if ($failed.Count -gt 0) { Write-Host ("  failed folders: " + ($failed -join ', ')) }
if ($fail -eq 0) { exit 0 } else { exit 1 }
