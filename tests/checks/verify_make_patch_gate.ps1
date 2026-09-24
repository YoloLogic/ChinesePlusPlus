# ============================================================================
#  checks: the patch-verification GATE must be able to fail.
#
#  Why this check exists
#  ---------------------
#  tools\make_patch.ps1 verifies each patch by applying it back onto the clean
#  tree and comparing SHA256. That gate shipped BROKEN once: New-Patch used
#  Write-Output for progress and returned a boolean, so the caller's
#  `if (-not (New-Patch ...))` swallowed the output stream -- the evidence was
#  never printed, and the captured value was a non-empty array (always truthy),
#  which made `$ok = $false` unreachable. A deliberately corrupted patch still
#  reported "all patches verified" and exited 0.
#  Found by an independent reviewer on 2026-09-22 (forced-failure experiment).
#
#  So the gate now has its own test: run it on a good patch (must pass) and on
#  a sabotaged patch (must fail). If the sabotaged run passes, this check fails.
#  It is fast -- one file, no full-tree scan.
#
#  Pure ASCII, like every script under tests\ (see ..\README.md).
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$script = Join-Path $root 'tools\make_patch.ps1'

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

Write-Host "run: make_patch.ps1 -SelfTest"
& $psExe -NoProfile -ExecutionPolicy Bypass -File $script -SelfTest 2>&1 |
    Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
$code = $LASTEXITCODE

if ($code -eq 0) {
    Write-Host "gate self-test passed: a good patch is accepted, a broken one is rejected"
    exit 0
}
Write-Host "gate self-test FAILED (exit=$code): the patch verification gate cannot fail"
exit 1
