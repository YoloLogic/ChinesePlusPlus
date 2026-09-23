# ============================================================================
#  Make PowerShell terminals UTF-8 by adding a marked, removable block to $PROFILE.
#
#  Usage:
#      powershell -File setup_utf8_terminal.ps1                 # install
#      powershell -File setup_utf8_terminal.ps1 -Undo           # remove
#      powershell -File setup_utf8_terminal.ps1 -WhatIfOnly     # dry run
#      powershell -File setup_utf8_terminal.ps1 -ProfilePath <file>   # test/other
#
#  WHY NOT VIA VS CODE SETTINGS  (two failures, do NOT retry)
#    1) long args: ["-NoExit","-Command","chcp 65001 > $null; [Console]::..."]
#       -> VS Code lost the quotes and the terminal opened with
#          "unexpected token '-Command'" (see docs, Chinese wording kept there)
#    2) short args: ["-NoExit","-Command","chcp 65001"]
#       -> the terminal opened with chcp saying
#          "parameter format not correct - -Command"
#    Root cause of (2): something else (VS Code shell integration / conda
#    activation) appends ANOTHER -Command. PowerShell honours only the FIRST
#    -Command and treats everything after it as script text, so the line really
#    becomes `chcp 65001 -Command ...` and chcp rejects "-Command".
#    RULE: never put -Command into a terminal profile's args. It must appear
#    once, last, and nobody else may want it.
#
#  WHAT THIS DOES INSTEAD
#    Appends a marked block to the user's own PowerShell profile. $PROFILE is not
#    subject to any editor's argument joining, so it works in EVERY terminal --
#    VS Code's integrated one, a plain console window, another IDE's terminal.
#    It fixes BOTH layers of mojibake:
#      1) what your program prints at run time
#      2) what the compiler itself prints (its Chinese diagnostics are UTF-8 too)
#
#  This edits the user's PERSONAL environment, which is exactly why it is a
#  separate opt-in script and why it is fully reversible (-Undo restores the
#  file byte-for-byte: the block is delimited by markers).
#
#  ENCODING: pure ASCII -- both this script and the block it writes, so the
#  profile needs no BOM and PowerShell 5.1 cannot mangle it.
# ============================================================================

param(
    [switch]$Undo,
    [switch]$WhatIfOnly,
    [string]$ProfilePath
)

$ErrorActionPreference = 'Continue'

$Begin = '# >>> Chinese++ UTF-8 terminal >>>'
$End = '# <<< Chinese++ UTF-8 terminal <<<'

$targets = @()
if ($ProfilePath) {
    $targets = @($ProfilePath)
} else {
    # Touch ONLY profile files that already exist -- appending to a file the user
    # never had would be a bigger footprint than the fix needs. If none exists,
    # create the host-specific one (the standard place).
    $candidates = @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) |
        Where-Object { $_ } | Select-Object -Unique
    $targets = @($candidates | Where-Object { Test-Path $_ })
    if ($targets.Count -eq 0) { $targets = @($PROFILE.CurrentUserCurrentHost) }
}

function Get-BlockLines {
    param([int]$PrevChars = -1)
    # The begin marker carries the ORIGINAL character count, so undo can restore
    # the file exactly -- including the trailing blank lines that marker-based
    # removal would otherwise eat (observed: 269 -> 267 bytes, not byte-identical).
    $begin = $Begin
    if ($PrevChars -ge 0) { $begin = "$Begin prev-chars=$PrevChars" }
    return @(
        $begin,
        '# Let this console interpret UTF-8 bytes correctly, so Chinese text does',
        '# not become mojibake. This fixes BOTH layers: what your program prints at',
        '# run time, and what the compiler itself prints (diagnostics are UTF-8 too).',
        '# Added by E:\Chinese++\tools\setup_utf8_terminal.ps1  --  remove with -Undo',
        'try { chcp 65001 > $null } catch { }',
        'try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }',
        'try { $OutputEncoding = [Text.Encoding]::UTF8 } catch { }',
        $End
    )
}

$changed = 0
$failed = 0
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# A write that silently fails must NOT be reported as success. The first version
# of this script counted "changed" unconditionally and printed "updated 2 profile
# file(s)" while every write had been DENIED by the sandbox -- exactly the
# "reports success on failure" bug class that reviewers have caught in this
# project twice. So: wrap every write, and re-read to confirm the block landed.
function Install-Block {
    param([string]$Path, [string]$Text, [bool]$HadBom)
    try {
        Write-TextKeepBom -Path $Path -Text $Text -HadBom $HadBom
    } catch {
        Write-Host ("  FAILED    {0}" -f $Path)
        Write-Host ("            {0}" -f $_.Exception.Message)
        return $false
    }
    try {
        $check = [System.IO.File]::ReadAllText($Path)
    } catch {
        Write-Host ("  FAILED    {0}  (wrote it but cannot read it back)" -f $Path)
        return $false
    }
    if ($Text.Contains($Begin)) {
        if (-not $check.Contains($Begin) -and -not $Text.StartsWith($Begin)) {
            Write-Host ("  FAILED    {0}  (block not found after writing)" -f $Path)
            return $false
        }
    } elseif ($check.Contains($Begin)) {
        Write-Host ("  FAILED    {0}  (block still present after undo)" -f $Path)
        return $false
    }
    return $true
}

# Read a text file and remember whether it had a UTF-8 BOM, so that rewriting it
# PRESERVES the original preamble. Dropping a BOM changes how PowerShell 5.1
# decodes the file (GBK instead of UTF-8), which has bitten this project three
# times -- never rewrite a profile without keeping its BOM state.
function Read-TextKeepBom {
    param([string]$Path)
    $raw = [System.IO.File]::ReadAllBytes($Path)
    $hadBom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
    return @{ Text = [System.IO.File]::ReadAllText($Path); HadBom = $hadBom }
}

function Write-TextKeepBom {
    param([string]$Path, [string]$Text, [bool]$HadBom)
    $enc = if ($HadBom) { $utf8Bom } else { $utf8NoBom }
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

foreach ($p in $targets) {
    $exists = Test-Path $p
    $text = ''
    $hadBom = $false
    if ($exists) {
        $r = Read-TextKeepBom $p
        $text = $r.Text
        $hadBom = $r.HadBom
    }
    $hasBlock = $text.Contains($Begin)

    if ($Undo) {
        if (-not $hasBlock) { Write-Host ("  skip      {0}  (no block)" -f $p); continue }
        # Exact restore when we can prove nothing was added after our block;
        # otherwise fall back to marker removal (safe, but trailing blank lines
        # may differ) and say so.
        $prev = -1
        foreach ($line in ($text -split "`r?`n")) {
            if ($line.Trim().StartsWith($Begin)) {
                if ($line -match 'prev-chars=(\d+)') { $prev = [int]$Matches[1] }
                break
            }
        }
        $endIdx = $text.IndexOf($End)
        $tail = if ($endIdx -ge 0) { $text.Substring($endIdx + $End.Length) } else { '' }
        $exact = ($prev -ge 0) -and ($text.Length -ge $prev) -and ($tail.Trim() -eq '')
        if ($exact) {
            $new = $text.Substring(0, $prev)
        } else {
            $out = New-Object System.Collections.ArrayList
            $inside = $false
            foreach ($line in ($text -split "`r?`n")) {
                $t = $line.Trim()
                if ($t -eq $Begin -or $t.StartsWith($Begin)) { $inside = $true; continue }
                if ($t -eq $End) { $inside = $false; continue }
                if ($inside) { continue }
                [void]$out.Add($line)
            }
            while ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -eq '') { $out.RemoveAt($out.Count - 1) }
            $new = if ($out.Count -gt 0) { ($out -join "`r`n") + "`r`n" } else { '' }
            Write-Host ("  note      {0}  (marker removal; trailing blank lines may differ)" -f $p)
        }
        if ($WhatIfOnly) { Write-Host ("  would undo {0}" -f $p); continue }
        # If the file exists only because we created it (nothing left after undo),
        # delete it, so the machine goes back to exactly how it was.
        if ($new -eq '') {
            try {
                Remove-Item $p -Force -ErrorAction Stop
                Write-Host ("  deleted   {0}  (was empty / created by this script)" -f $p)
                $changed = $changed + 1
            } catch {
                Write-Host ("  FAILED    {0}" -f $p)
                Write-Host ("            {0}" -f $_.Exception.Message)
                $failed = $failed + 1
            }
            continue
        }
        if (Install-Block -Path $p -Text $new -HadBom $hadBom) {
            Write-Host ("  undone    {0}" -f $p)
            $changed = $changed + 1
        } else {
            $failed = $failed + 1
        }
        continue
    }

    if ($hasBlock) { Write-Host ("  skip      {0}  (already installed)" -f $p); continue }
    $block = (Get-BlockLines -PrevChars $text.Length) -join "`r`n"
    if (-not $exists) {
        $dir = Split-Path $p -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $new = $block + "`r`n"
        $action = 'created'
    } else {
        $sep = if ($text.EndsWith("`n") -or $text -eq '') { '' } else { "`r`n" }
        $new = $text + $sep + "`r`n" + $block + "`r`n"
        $action = 'appended'
    }
    if ($WhatIfOnly) { Write-Host ("  would {0,-8} {1}" -f $action, $p); continue }
    if (Install-Block -Path $p -Text $new -HadBom $hadBom) {
        Write-Host ("  {0,-9} {1}" -f $action, $p)
        $changed = $changed + 1
    } else {
        $failed = $failed + 1
    }
}

Write-Host ''
if ($WhatIfOnly) { Write-Host 'dry run: nothing written'; exit 0 }
if ($failed -gt 0) {
    Write-Host ("FAILED: {0} file(s) could not be written -- nothing is installed" -f $failed)
    Write-Host 'Common cause: no permission to write $PROFILE (it lives under C:\Users\<you>\,'
    Write-Host 'outside this project, so a restricted sandbox or ACL will block it).'
    exit 1
}
if ($Undo) {
    if ($changed -gt 0) { Write-Host ("removed from {0} file(s); restore done" -f $changed) }
    else { Write-Host 'no block present, nothing to remove' }
} else {
    if ($changed -gt 0) {
        Write-Host ("updated {0} profile file(s)" -f $changed)
        Write-Host 'verify like this (the first chcp forces GBK, so only the profile can change it):'
        Write-Host '  cmd /c "chcp 936 >nul && powershell -NoLogo -Command chcp"'
        Write-Host 'it must print:  Active code page: 65001'
    } else {
        Write-Host 'already installed, nothing to do'
    }
}
exit 0
