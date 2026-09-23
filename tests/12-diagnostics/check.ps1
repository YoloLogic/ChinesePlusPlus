# ============================================================================
#  12 diagnostics: the diagnostic BODY must be Chinese, everything else
#  must be untouched.
#
#  What this proves (no eyeballing anywhere):
#    * the message body is Chinese               -> "expect:" markers in each .cpp
#    * the English body is GONE, not appended    -> "forbid:" markers in each .cpp
#    * error:/warning: prefix and [-Wxxx] option name still there
#    * diagnostics WITHOUT a table entry fall back to English
#        (10_fallback_english.cpp: default log must be BYTE-IDENTICAL to the
#         -fno-chinese-diagnostics log -- a diagnostic with no entry cannot
#         possibly be affected, so any difference is a bug)
#    * -fno-chinese-diagnostics really switches back to English
#    * a normal file still compiles (11_ok.cpp)
#
#  Expectations live INSIDE each .cpp as
#      // expect: <text>      must appear in the compiler output
#      // forbid: <text>      must NOT appear
#  so every case documents itself and this script stays pure ASCII (see
#  ..\README.md: PowerShell 5.1 reads a BOM-less file as GBK).
#
#  Compiler output is captured through cmd redirection so the raw UTF-8 bytes
#  survive, and every comparison is on BYTES, never on decoded text -- so the
#  result does not depend on the console code page.
#
#  Table structure (does every ID still exist? do the placeholders still match
#  the English?) is checked separately by tests\checks\verify_zh_diagnostics.py.
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$fail = 0
$utf8  = [System.Text.Encoding]::UTF8
$ascii = [System.Text.Encoding]::ASCII

function Get-Log {
    param([string]$File, [string]$Extra = '', [string]$Tag = 'log')
    $src = Join-Path $here $File
    $log = Join-Path $out ("$File.$Tag.txt")
    if (Test-Path $log) { Remove-Item $log -Force }
    & cmd /c "`"$cxx`" -std=c++20 -fsyntax-only $Extra `"$src`" > `"$log`" 2>&1"
    $code = $LASTEXITCODE
    return @{
        Code  = $code
        Log   = $log
        Bytes = [System.IO.File]::ReadAllBytes($log)
    }
}

function Test-Bytes {
    param([byte[]]$Hay, [byte[]]$Needle)
    if ($null -eq $Hay -or $null -eq $Needle) { return $false }
    if ($Needle.Length -eq 0 -or $Hay.Length -lt $Needle.Length) { return $false }
    for ($i = 0; $i -le $Hay.Length - $Needle.Length; $i += 1) {
        $same = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Hay[$i + $j] -ne $Needle[$j]) { $same = $false; break }
        }
        if ($same) { return $true }
    }
    return $false
}

function Test-SameBytes {
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i += 1) {
        if ($A[$i] -ne $B[$i]) { return $false }
    }
    return $true
}

function Get-Marked {
    param([string]$File, [string]$Mark)
    $path = Join-Path $here $File
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $key  = "// ${Mark}:"
    $res  = @()
    foreach ($line in ($text -split "`n")) {
        $t = $line.Trim()
        if ($t.StartsWith($key)) { $res += $t.Substring($key.Length).Trim() }
    }
    return $res
}

function Check-Case {
    param(
        [string]$File,
        [string]$Extra = '',
        [ValidateSet('fail', 'ok')]
        [string]$Expect = 'fail'
    )

    $tag = 'log'
    if ($Extra) { $tag = 'x' }
    $label = "--- $File"
    if ($Extra) { $label = "$label  [$Extra]" }
    Write-Host $label

    $r = Get-Log $File $Extra $tag

    if ($Expect -eq 'ok') {
        if ($r.Code -ne 0) {
            Write-Host "    FAIL: should have compiled, exit=$($r.Code)"
            $script:fail += 1
            Get-Content $r.Log | Select-Object -Last 4 | ForEach-Object { Write-Host "      $_" }
        } else {
            Write-Host '    OK: exit 0 as expected'
        }
    } elseif ($r.Code -eq 0) {
        Write-Host '    FAIL: compiled, but this file is supposed to fail'
        $script:fail += 1
    }

    $i = 0
    foreach ($n in (Get-Marked $File 'expect')) {
        $i += 1
        if (Test-Bytes $r.Bytes ($utf8.GetBytes($n))) {
            Write-Host "    OK   expect #$i present"
        } else {
            Write-Host "    FAIL expect #$i MISSING: $n"
            $script:fail += 1
        }
    }
    $i = 0
    foreach ($n in (Get-Marked $File 'forbid')) {
        $i += 1
        if (Test-Bytes $r.Bytes ($utf8.GetBytes($n))) {
            Write-Host "    FAIL forbid #$i STILL PRESENT: $n"
            $script:fail += 1
        } else {
            Write-Host "    OK   forbid #$i absent"
        }
    }
    return $r
}

function Expect-Ascii {
    param([string]$Label, [byte[]]$Hay, [string]$Text, [bool]$Want)
    $found = Test-Bytes $Hay ($ascii.GetBytes($Text))
    if ($found -eq $Want) { Write-Host "    OK   $Label" }
    else {
        Write-Host "    FAIL $Label (found=$found, wanted=$Want)"
        $script:fail += 1
    }
}

# ---------------------------------------------------------------------------
# 1) one case per translated entry
# ---------------------------------------------------------------------------
Check-Case '01_missing_semi.cpp'    | Out-Null
Check-Case '02_unknown_type.cpp'    | Out-Null
Check-Case '03_undeclared.cpp'      | Out-Null
Check-Case '04_no_member.cpp'       | Out-Null
Check-Case '05_no_overload.cpp'     | Out-Null
Check-Case '06_unmatched_brace.cpp' | Out-Null
Check-Case '07_keyword_as_name.cpp' | Out-Null
Check-Case '08_const_assign.cpp'    | Out-Null
$r09 = Check-Case '09_unused_var.cpp' '-Wall' -Expect ok
Check-Case '11_ok.cpp' -Expect ok | Out-Null

# ---------------------------------------------------------------------------
# 1b) second batch: 18 entries chosen by MEASURED frequency
#     (tools\diag_frequency.py over 400 real files -> 2820 diagnostics)
# ---------------------------------------------------------------------------
Check-Case '12_missing_include.cpp'        | Out-Null
Check-Case '13_subscript.cpp'              | Out-Null
Check-Case '14_bad_operands.cpp'           | Out-Null
Check-Case '15_redefinition.cpp'           | Out-Null
Check-Case '16_redefinition_kind.cpp'      | Out-Null
Check-Case '17_nested_type_not_found.cpp'  | Out-Null
Check-Case '18_missing_type_specifier.cpp' | Out-Null
Check-Case '19_toplevel_declarator.cpp'    | Out-Null
# -std=c++17 is REQUIRED: in C++20 the implicit typename is legal, so the
# warning never fires. The ID is compat_pre_cxx20_implicit_typename.
Check-Case '20_typename_missing.cpp' '-std=c++17' | Out-Null
Check-Case '21_unused_param.cpp'   '-Wall -Wextra' -Expect ok | Out-Null
Check-Case '22_unused_expr.cpp'    '-Wall' -Expect ok | Out-Null
Check-Case '23_unused_typedef.cpp' '-Wall' -Expect ok | Out-Null
Check-Case '24_shadow.cpp'         '-Wshadow' -Expect ok | Out-Null
Check-Case '25_template_notes.cpp' '-Wall' | Out-Null
Check-Case '26_fn_template_spec.cpp' '-Wall' | Out-Null
Check-Case '27_implicit_function.c'            '-x c -std=c99'
Check-Case '28_static_assert_no_message.cpp'   '-std=c++14' -Expect ok
Check-Case '29_unknown_attribute.cpp'           -Expect ok
Check-Case '30_missing_braces.cpp'             '-Wall' -Expect ok
Check-Case '31_constexpr_var_init.cpp'
Check-Case '32_conv_function_params.cpp'
Check-Case '33_multi_line_comment.cpp'         '-Wall' -Expect ok
Check-Case '34_sa_requirement.cpp'               
Check-Case '35_sa_requirement_msg.cpp'           
Check-Case '36_reinterpret_updown.cpp'            -Expect ok
Check-Case '37_conv_function_complex.cpp'        
Check-Case '38_unsatisfied_trait.cpp'            '-std=c++26' 
Check-Case '39_unused_private_field.cpp'         '-Wall'  -Expect ok
Check-Case '40_unused_lambda_capture.cpp'        '-Wall'  -Expect ok
Check-Case '41_conv_to_function.cpp'            
Check-Case '42_matrix_disabled.cpp'              '-std=c++20'

# --- C1 (2026-09-23): sibling entries. Every one of these already had its main
# --- sentence translated; these are the variants that used to fall back to
# --- English and therefore appeared right next to Chinese in the same group.
Check-Case '43_unused_but_set_var.cpp'         '-Wall'  -Expect ok
Check-Case '44_unused_but_set_global.cpp'      '-Wall -Wunused-but-set-global' -Expect ok
Check-Case '45_sa_expr_not_constant.cpp'       '-std=c++20'
Check-Case '46_semi_decl_list.cpp'
Check-Case '47_expected_expression.cpp'
Check-Case '48_typename_suggest.cpp'
Check-Case '49_undeclared_suggest.cpp'
Check-Case '50_nested_typename_suggest.cpp'
Check-Case '51_unknown_attribute_suggest.cpp'  '-Wall'  -Expect ok
Check-Case '52_no_template_suggest.cpp'
Check-Case '53_member_redeclared.cpp'
Check-Case '54_reinterpret_warning.cpp'        '-Wall'  -Expect ok

# ---------------------------------------------------------------------------
# 2) prefix and option name must survive (ASCII, so trivially checkable)
# ---------------------------------------------------------------------------
Write-Host '--- 09: prefix and option name untouched'
Expect-Ascii 'warning: prefix still present' $r09.Bytes 'warning: ' $true
Expect-Ascii '[-Wunused-variable] still present' $r09.Bytes '[-Wunused-variable]' $true
Expect-Ascii 'source file name still echoed' $r09.Bytes '09_unused_var.cpp:' $true

# ---------------------------------------------------------------------------
# 3) the switch must work both ways
# ---------------------------------------------------------------------------
Write-Host '--- -fno-chinese-diagnostics must switch back to English'
$on  = Get-Log '09_unused_var.cpp' '-Wall' 'on'
$off = Get-Log '09_unused_var.cpp' '-Wall -fno-chinese-diagnostics' 'off'
Expect-Ascii 'off: English body is back' $off.Bytes 'unused variable' $true
if (Test-Bytes $off.Bytes ($utf8.GetBytes((Get-Marked '09_unused_var.cpp' 'expect')[0]))) {
    Write-Host '    FAIL off: Chinese body is still there'
    $script:fail += 1
} else {
    Write-Host '    OK   off: Chinese body is gone'
}
if (Test-SameBytes $on.Bytes $off.Bytes) {
    Write-Host '    FAIL on/off: logs are identical, the switch does nothing'
    $script:fail += 1
} else {
    Write-Host '    OK   on/off: logs differ, the switch does something'
}

# ---------------------------------------------------------------------------
# 4) fallback: a file with NO table entry must be byte-identical either way
# ---------------------------------------------------------------------------
Write-Host '--- 10: untranslated diagnostics must fall back to English'
$def = Get-Log '10_fallback_english.cpp' '' 'def'
# Keep this needle in sync with 10_fallback_english.cpp's "// expect:" line:
# it must name a diagnostic that is NOT in ChineseDiagnostics.def.
Expect-Ascii 'default: English body present' $def.Bytes 'cannot initialize a variable of type' $true
$flg = Get-Log '10_fallback_english.cpp' '-fno-chinese-diagnostics' 'flg'
if (Test-SameBytes $def.Bytes $flg.Bytes) {
    Write-Host '    OK   default log is byte-identical to the -fno- log (fallback works)'
} else {
    Write-Host '    FAIL default log differs from the -fno- log (fallback is broken)'
    $script:fail += 1
}

# ---------------------------------------------------------------------------
# 5) every .cpp in this directory must be REFERENCED by this script.
#    The case list above is hard-coded on purpose (each case carries its own
#    flags and exit-code expectation), but that makes one specific mistake
#    possible: drop in a new .cpp, forget the Check-Case line, and the file
#    never runs and therefore never fails. A case file that silently tests
#    nothing is worse than no case file -- it looks like coverage.
# ---------------------------------------------------------------------------
Write-Host '--- registration: every .cpp here must be run by this script'
$selfText = Get-Content -Raw -Path $MyInvocation.MyCommand.Path
$unregistered = @()
foreach ($f in (Get-ChildItem -Path $here -Filter *.cpp | Sort-Object Name)) {
    if ($selfText.IndexOf($f.Name) -lt 0) { $unregistered += $f.Name }
}
if ($unregistered.Count -gt 0) {
    Write-Host ('    FAIL not referenced by this script: ' + ($unregistered -join ', '))
    $script:fail += 1
} else {
    Write-Host '    OK   every case file is referenced by this script'
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'all Chinese-diagnostic checks passed'; exit 0 }
Write-Host "$fail check(s) failed"; exit 1
