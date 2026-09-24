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
    # Default the language standard, but do NOT force it: a case that sets its
    # own -std= or switches language with -x (the .c cases) would otherwise
    # fight it -- "-std=c++20" together with "-x c" is
    # "invalid argument '-std=c++20' not allowed with 'C'".
    # A hard-coded flag that silently overrides (or breaks) a case's own flags
    # is the same class of trap as the duplicate patch gate.
    $std = '-std=c++20'
    if ($Extra -match '-std=' -or $Extra -match '(^|\s)-x(\s|$)') { $std = '' }
    & cmd /c "`"$cxx`" $std -fsyntax-only $Extra `"$src`" > `"$log`" 2>&1"
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

# Same idea, but for Chinese needles: Expect-Ascii encodes with the ASCII
# encoding, so a Chinese string would come out as question marks. This is why
# every other Chinese assertion in this suite lives in a case file's
# "// expect:" comment instead. Hand-built renderer text has no case file of
# its own for the switch, so it needs this.
function Expect-Utf8 {
    param([string]$Label, [byte[]]$Hay, [byte[]]$Needle, [bool]$Want)
    $found = Test-Bytes $Hay $Needle
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

# --- C2a (2026-09-23): the rest of the measured top ranks.
Check-Case '55_dllattr_precedence.cpp'         -Expect ok
Check-Case '56_lambda_in_constexpr.cpp'        '-std=c++14'
Check-Case '57_blocks_disabled.c'              '-x cl -cl-std=CL1.2'
Check-Case '58_builtin_unknown.c'              '-x c'
Check-Case '59_unguarded_header.cpp'
Check-Case '60_constexpr_call_here.cpp'        '-std=c++14'
Check-Case '61_undefined_template.cpp'
Check-Case '62_friend_decl_spec.cpp'
Check-Case '63_template_missing_args.cpp'      '-std=c++14'
Check-Case '64_forward_declaration.cpp'
Check-Case '65_expected_capture.cpp'
Check-Case '66_tsdmd_here.cpp'
Check-Case '67_redeclared_family.cpp'
Check-Case '68_previous_initializer.c'         '-x c -Winitializer-overrides' -Expect ok

# --- hand-built renderer text (2026-09-24). No diagnostic ID exists for these,
# --- so the Chinese lives inline in the renderer and is gated by the SAME
# --- option the table lookup uses. The switch assertions for 69 are below.
Check-Case '69_macro_backtrace.cpp'
Check-Case '70_include_stack.cpp'

# --- C4 (2026-09-24): chosen from the REAL-PROJECT ranking, not clang/test.
Check-Case '71_deprecated.cpp'                 '-Wall'  -Expect ok
Check-Case '72_deprecated_message.cpp'         '-Wall'  -Expect ok
Check-Case '73_unused_function.cpp'            '-Wall'  -Expect ok
Check-Case '74_override_exception_spec.cpp'    '-Wall'  -Expect ok
Check-Case '75_template_member_here.cpp'
Check-Case '76_uninit_const_pointer.cpp'       '-Wall'  -Expect ok

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
# 3b) the switch must ALSO cover the hand-built renderer text.
#     Those strings have no diagnostic ID, so they are gated inline; nothing
#     else in this suite would notice if that gate were dropped. The macro
#     backtrace note is the one that fires most in real projects.
# ---------------------------------------------------------------------------
Write-Host '--- hand-built renderer text must obey the switch too'
$mbOn  = Get-Log '69_macro_backtrace.cpp' '' 'mbon'
$mbOff = Get-Log '69_macro_backtrace.cpp' '-fno-chinese-diagnostics' 'mboff'
Expect-Utf8 'on : macro backtrace is Chinese' $mbOn.Bytes ([byte[]](0xE4, 0xBB, 0x8E, 0xE5, 0xAE, 0x8F)) $true   # "cong hong"
Expect-Ascii 'off: macro backtrace is English again' $mbOff.Bytes 'expanded from macro' $true

# 3c) the "N warnings generated." summary is only printed by a real compile
#     (-c), not by -fsyntax-only, so it needs its own check.
Write-Host '--- the generated-count summary follows the switch'
$obj = Join-Path $out 'cnt.obj'
$src = Join-Path $here '68_previous_initializer.c'
& cmd /c "`"$cxx`" -c -x c -Wall `"$src`" -o `"$obj`" > `"$out\cnt.on.txt`" 2>&1"
$cntOn = [System.IO.File]::ReadAllBytes((Join-Path $out 'cnt.on.txt'))
& cmd /c "`"$cxx`" -c -x c -Wall -fno-chinese-diagnostics `"$src`" -o `"$obj`" > `"$out\cnt.off.txt`" 2>&1"
$cntOff = [System.IO.File]::ReadAllBytes((Join-Path $out 'cnt.off.txt'))
Expect-Utf8 'on : summary is Chinese' $cntOn ([byte[]](0xE7, 0x94, 0x9F, 0xE6, 0x88, 0x90, 0xE4, 0xBA, 0x86)) $true   # "sheng cheng le"
Expect-Ascii 'off: summary is English again' $cntOff 'generated.' $true

# 3d) A CLEAN compile must print NO summary at all.
#     This assertion did not exist before 2026-09-24, and its absence let a real
#     regression ship: in CompilerInstance.cpp the Chinese branch printed an
#     unconditional "sheng cheng le " prefix, so EVERY successful compile
#     emitted a stray half-sentence while the English branch printed nothing.
#     All 78 cases here and all 18 acceptance checks still passed, because every
#     single one of them compiles a file that has diagnostics.
#     "No assertion = not verified."
Write-Host '--- a clean compile prints no summary at all'
$clean = Join-Path $out 'clean_summary.cpp'
[System.IO.File]::WriteAllText($clean, "int main(){ return 0; }")
$clOn = Join-Path $out 'clean.on.txt'
& cmd /c "`"$cxx`" -c `"$clean`" -o `"$obj`" > `"$clOn`" 2>&1"
$clOnB = [System.IO.File]::ReadAllBytes($clOn)
Expect-Utf8 'on : no Chinese summary on a clean compile' $clOnB `
    ([byte[]](0xE7, 0x94, 0x9F, 0xE6, 0x88, 0x90, 0xE4, 0xBA, 0x86)) $false
Expect-Ascii 'on : no English summary on a clean compile' $clOnB 'generated.' $false

# 3e) warnings AND errors together: the Chinese connector must be followed by a
#     space. The typography rule is a space between a CJK character and a digit
#     (measured on the shipped table: 0 exceptions), so it is "he SPACE 1",
#     never "he1". This defect shipped once too -- same missing assertion.
Write-Host '--- warning + error: Chinese connector keeps the digit space'
$mix = Join-Path $out 'mix_summary.cpp'
[System.IO.File]::WriteAllText($mix, "int a(){ int unused_a; return 0; }`nint b(){ int unused_b; return 0; }`nint c(){ return undefined_c; }`n")
$mxOn = Join-Path $out 'mix.on.txt'
& cmd /c "`"$cxx`" -c -Wall `"$mix`" -o `"$obj`" > `"$mxOn`" 2>&1"
$mxOnB = [System.IO.File]::ReadAllBytes($mxOn)
$mxOff = Join-Path $out 'mix.off.txt'
& cmd /c "`"$cxx`" -c -Wall -fno-chinese-diagnostics `"$mix`" -o `"$obj`" > `"$mxOff`" 2>&1"
$mxOffB = [System.IO.File]::ReadAllBytes($mxOff)
# needle = "ge jing gao he 1 ge cuo wu"  (the space before 1 is the point)
Expect-Utf8 'on : mixed summary keeps the space after the connector' $mxOnB `
    ([byte[]](0xE4, 0xB8, 0xAA, 0xE8, 0xAD, 0xA6, 0xE5, 0x91, 0x8A, 0xE5, 0x92, 0x8C,
              0x20, 0x31, 0x20, 0xE4, 0xB8, 0xAA, 0xE9, 0x94, 0x99, 0xE8, 0xAF, 0xAF)) $true
Expect-Ascii 'off: same counts in English' $mxOffB 'warnings and 1 error generated.' $true

# ---------------------------------------------------------------------------
# 4) There used to be a "fallback" case here: a file whose diagnostic was NOT
#    in the table, asserted byte-identical with and without the switch. As of
#    2026-09-24 that property is no longer observable -- every one of the 7374
#    builtin diagnostics that HAS English text is now in the table (7344
#    entries; the remaining 30 are `"%0"` pass-throughs with no English of
#    their own to translate). So there is nothing left to fall back FROM.
#    The stronger guarantee replaces it, at table level, in
#    tests\checks\verify_zh_diagnostics.py: no builtin diagnostic with English
#    text may be missing from the table. Here we assert what still IS
#    observable: the switch flips this table-backed diagnostic.
# ---------------------------------------------------------------------------
Write-Host '--- 10: the switch flips a table-backed diagnostic'
$def = Get-Log '10_fallback_english.cpp' '' 'def'
# needle = "wu fa chu shi hua"
Expect-Utf8 'default: Chinese body present' $def.Bytes `
    ([byte[]](0xE6, 0x97, 0xA0, 0xE6, 0xB3, 0x95, 0xE5, 0x88, 0x9D,
              0xE5, 0xA7, 0x8B, 0xE5, 0x8C, 0x96)) $true
$flg = Get-Log '10_fallback_english.cpp' '-fno-chinese-diagnostics' 'flg'
Expect-Ascii 'off: English body is back' $flg.Bytes 'cannot initialize a variable of type' $true
Expect-Utf8 'off: Chinese body is gone' $flg.Bytes `
    ([byte[]](0xE6, 0x97, 0xA0, 0xE6, 0xB3, 0x95, 0xE5, 0x88, 0x9D,
              0xE5, 0xA7, 0x8B, 0xE5, 0x8C, 0x96)) $false

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
# Covers *.cpp AND *.c -- this gate originally globbed only *.cpp, so .c cases
# like 27_implicit_function.c were outside its protection. Its own hole.
# Keep the whole foreach on ONE line: a trailing "|" as a line continuation is
# PowerShell 7 only; 5.1 fails with "Unexpected token ')'". This script must
# also run under 5.1.
# (And keep every line here ASCII -- see the header note: 5.1 reads a BOM-less
#  file as GBK, so a Chinese comment turns into mojibake and breaks parsing.)
foreach ($f in (Get-ChildItem -Path $here -File | Where-Object { $_.Extension -eq '.cpp' -or $_.Extension -eq '.c' } | Sort-Object Name)) {
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
