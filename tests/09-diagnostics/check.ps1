# ============================================================================
#  09 diagnostics: Chinese must be the OFFICIAL spelling in messages.
#
#  Cases (renamed from the earlier-session files):
#    diag_cn.cpp        - deliberately wrong: the message must quote the
#                         Chinese keyword, NOT the English one
#    token_glue_bad.cpp - `返回甲` is ONE identifier, not keyword+identifier
#                         (the trap described in ..\..\docs\使用说明.md section 4)
#    mixed_tokens.cpp   - Chinese and English mixed in one file, must compile
#    min_ok.cpp         - minimal case with no #include (clangd-safe)
#
#  The Chinese needle is built from char codes so this script stays pure ASCII
#  (see ..\README.md). Comparison is done on RAW BYTES so it does not depend on
#  the console code page.
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$fail = 0

function Expect-Fail {
    param([string]$File, [string]$Label, [byte[]]$Needle)
    $src = Join-Path $here $File
    $log = Join-Path $out ($File + '.log')
    Write-Host "--- $File  ($Label) -- expected to FAIL"
    # cmd redirection keeps the compiler's raw UTF-8 bytes in the log
    & cmd /c "`"$cxx`" -std=c++20 -fsyntax-only `"$src`" > `"$log`" 2>&1"
    $code = $LASTEXITCODE
    Write-Host "    exit=$code"
    if ($code -eq 0) { Write-Host '    FAIL: compiled, but should not have'; $script:fail += 1; return }

    if ($Needle) {
        $bytes = [System.IO.File]::ReadAllBytes($log)
        $found = $false
        for ($i = 0; $i -le $bytes.Length - $Needle.Length; $i++) {
            $same = $true
            for ($j = 0; $j -lt $Needle.Length; $j++) {
                if ($bytes[$i + $j] -ne $Needle[$j]) { $same = $false; break }
            }
            if ($same) { $found = $true; break }
        }
        if ($found) { Write-Host '    OK: rejected, and the message quotes the Chinese keyword' }
        else { Write-Host '    FAIL: rejected, but the Chinese keyword is missing from the message'; $script:fail += 1 }
    }
    else { Write-Host '    OK: rejected as expected' }
}

function Expect-OK {
    param([string]$File)
    $src = Join-Path $here $File
    Write-Host "--- $File -- expected to compile"
    & $cxx -std=c++20 -fsyntax-only $src 2>&1 | ForEach-Object { Write-Host "    $_" }
    $code = $LASTEXITCODE
    if ($code -eq 0) { Write-Host '    OK' } else { Write-Host "    FAIL (exit=$code)"; $script:fail += 1 }
}

# UTF-8 bytes of the Chinese keyword for `if`
$needleIf = [System.Text.Encoding]::UTF8.GetBytes(([string][char]0x5982 + [char]0x679C))

Expect-Fail 'diag_cn.cpp'        'Chinese keyword in the message' $needleIf
Expect-Fail 'token_glue_bad.cpp' 'token gluing trap'              $null
Expect-OK   'mixed_tokens.cpp'
Expect-OK   'min_ok.cpp'

Write-Host ''
if ($fail -eq 0) { Write-Host 'all diagnostics checks passed'; exit 0 }
Write-Host "$fail check(s) failed"; exit 1
