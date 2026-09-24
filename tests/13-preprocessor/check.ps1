# ============================================================================
#  13-preprocessor: Chinese preprocessor directive spellings.
#
#  What this suite proves
#    1) every Chinese spelling the compiler accepts behaves EXACTLY like its
#       English counterpart (sweep.py, 22 spellings + a nested all-Chinese case)
#    2) English and Chinese spellings can be MIXED in one file, in one
#       conditional chain, with no flag and no mode
#    3) an all-Chinese file preprocesses to BYTE-IDENTICAL output as its
#       all-English twin (the "no lock-in" proof, at the directive level)
#    4) a Chinese directive spelling is still an ordinary identifier elsewhere
#    5) a spelling that is NOT in ChineseDirectives.def is still rejected
#
#  Pure ASCII on purpose (see ..\README.md): PowerShell 5.1 reads a BOM-less
#  file as GBK, and Chinese literals in *code* would break the parser outright.
#  All Chinese lives in the .cpp inputs and in sweep.py (which is UTF-8).
#
#  Usage:
#      powershell -File E:\Chinese++\tests\13-preprocessor\check.ps1
# ============================================================================

$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)      # E:\Chinese++
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$python = 'E:\python\python.exe'

$out = Join-Path $here 'out'
New-Item -ItemType Directory -Force $out | Out-Null

$fail = 0
function Fail($msg) { Write-Host ("  [FAIL] " + $msg); $script:fail = 1 }
function Pass($msg) { Write-Host ("  [ok]   " + $msg) }

if (-not (Test-Path $cxx)) { Fail "no compiler at $cxx"; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 1) mixed English + Chinese directives in one file'
$mixed = Join-Path $here 'mixed.cpp'
$mixedExe = Join-Path $out 'mixed.exe'
& $cxx -std=c++23 -O0 -o $mixedExe $mixed 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Fail 'mixed.cpp did not compile' }
else {
    & $mixedExe
    if ($LASTEXITCODE -eq 0) { Pass 'mixed.cpp compiles, runs, self-check holds' }
    else { Fail "mixed.cpp exited $LASTEXITCODE" }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) all-Chinese vs all-English: byte-identical preprocessing'
# The two sources differ ONLY in directive spelling, so any behavioural
# difference has to show up as a byte difference here.
$zhExe = Join-Path $out 'chinese.exe'
$enExe = Join-Path $out 'english.exe'
& $cxx -std=c++23 -O0 -o $zhExe (Join-Path $here 'chinese.cpp') 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Fail 'chinese.cpp did not compile' }
& $cxx -std=c++23 -O0 -o $enExe (Join-Path $here 'english.cpp') 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Fail 'english.cpp did not compile' }

# Redirect through cmd, NOT through a PowerShell pipeline: `> file` is shell
# DEPENDENT (5.1 writes UTF-16LE with a BOM, 7 writes raw bytes). Same lesson as
# tests\06-parity\check.ps1 documents -- the byte count here IS the evidence.
$zhI = Join-Path $out 'chinese.i'
$enI = Join-Path $out 'english.i'
& cmd /c "`"$cxx`" -std=c++23 -E -P `"$(Join-Path $here 'chinese.cpp')`" > `"$zhI`""
& cmd /c "`"$cxx`" -std=c++23 -E -P `"$(Join-Path $here 'english.cpp')`" > `"$enI`""

$a = [System.IO.File]::ReadAllBytes($zhI)
$b = [System.IO.File]::ReadAllBytes($enI)
Write-Host ("    bytes: zh=$($a.Length)  en=$($b.Length)")
if ($a.Length -eq 0) { Fail 'preprocessed output is empty -- the comparison would be vacuous' }
elseif ($a.Length -ne $b.Length) { Fail 'preprocessed output length differs' }
else {
    $diff = -1
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { $diff = $i; break } }
    if ($diff -ge 0) { Fail "preprocessed output differs at byte $diff" }
    else { Pass "preprocessed output is byte-identical ($($a.Length) bytes)" }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) the resolved value must be the expected branch'
# Byte-identity alone would also hold if BOTH files resolved to the same wrong
# branch. Anchor the expected value.
if ($a.Length -gt 0) {
    $text = [System.IO.File]::ReadAllText($zhI)
    if ($text -match '40 == 40') { Pass 'chinese.cpp took the #elifndef branch (PICK == 40)' }
    else { Fail 'chinese.cpp did not resolve PICK to 40' }
    # FROM_HEADER is already macro-expanded in -E output, so the needle is the
    # VALUE, not the name. 11 comes from inc_b.h, i.e. through the Chinese
    # spelling of #include.
    if ($text -match '11 == 11') { Pass 'the Chinese include directive pulled in inc_b.h (FROM_B == 11)' }
    else { Fail 'FROM_B is missing -- the Chinese include directive did not happen' }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) a directive spelling is still an ordinary identifier'
$guard = Join-Path $here 'guard_identifiers.cpp'
$guardExe = Join-Path $out 'guard.exe'
& $cxx -std=c++23 -O0 -o $guardExe $guard 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Fail 'guard_identifiers.cpp did not compile' }
else {
    & $guardExe
    if ($LASTEXITCODE -eq 0) { Pass 'globals named after directive spellings still work' }
    else { Fail "guard_identifiers.exe exited $LASTEXITCODE" }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 5) unknown spellings are still rejected'
$bad = Join-Path $here 'bad_directive.cpp'
$badTxt = Join-Path $out 'bad.txt'
& cmd /c "`"$cxx`" -std=c++23 -fsyntax-only `"$bad`" > `"$badTxt`" 2>&1"
if ($LASTEXITCODE -eq 0) { Fail 'bad_directive.cpp compiled -- unknown directives are being accepted' }
else {
    $bt = [System.IO.File]::ReadAllText($badTxt)
    # Both lines must be rejected: the near-miss Chinese typo and the English one.
    # The needle is built from code points so this file stays pure ASCII.
    # NOTE: `[char]0x65E0 + [char]0x6548` would ADD the two code points into one
    # unrelated character -- string interpolation is required.
    $needle = "$([char]0x65E0)$([char]0x6548)"       # U+65E0 U+6548 = "invalid"
    $n = ([regex]::Matches($bt, [regex]::Escape($needle))).Count
    Write-Host ("    'invalid directive' diagnostics: $n (expected 2)")
    if ($n -ge 2) { Pass '#otherwise-if-defined typo and #elsedef are both rejected' }
    else { Fail 'expected 2 invalid-directive diagnostics' }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 6) -E echoes the spelling the user wrote'
# `-dI` prints every include as a comment, going through
# PrintPreprocessedOutput.cpp:494-496, which does `*OS << "#" << TokenText`
# with TokenText = PP.getSpelling(IncludeTok). That means the ORIGINAL spelling
# survives, so a preprocessed file can be fed back unchanged.
$echoTxt = Join-Path $out 'echo.txt'
& cmd /c "`"$cxx`" -E -dI `"$(Join-Path $here 'echo_spelling.cpp')`" > `"$echoTxt`" 2>&1"
$et = [System.IO.File]::ReadAllText($echoTxt)
# U+0023 U+5305 U+542B is the Chinese spelling of #include.
$zhInc = "$([char]0x23)$([char]0x5305)$([char]0x542B)"
if ($et.Contains($zhInc)) { Pass '-E -dI echoes the Chinese include spelling verbatim' }
else { Fail '-E -dI normalised the Chinese directive spelling to English' }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 7) diagnostics name directives in CHINESE, whatever the user typed'
# The keyword policy is "always show the canonical Chinese spelling", NOT
# "echo what the user typed": writing English `static_assert` still prints the
# Chinese spelling of static_assert. Directives must follow the same rule, so
# BOTH files below must print the Chinese spelling. Asserting this in both
# directions is the only way to tell the two policies apart -- a single file
# would pass under either.
$needleZh = -join [char[]](0x23, 0x5426, 0x5219, 0x82E5, 0x5DF2, 0x5B9A, 0x4E49)
$diagEn = Join-Path $out 'elifdef_en.txt'
$diagZh = Join-Path $out 'elifdef_zh.txt'
& cmd /c "`"$cxx`" -std=c++20 -fsyntax-only `"$(Join-Path $here 'elifdef_en.cpp')`" > `"$diagEn`" 2>&1"
& cmd /c "`"$cxx`" -std=c++20 -fsyntax-only `"$(Join-Path $here 'elifdef_zh.cpp')`" > `"$diagZh`" 2>&1"
# Only the diagnostic lines -- NOT the echoed source line. The echo necessarily
# shows whatever the user wrote (that is the point of an echo), so searching the
# whole output would always "find" the English spelling.
function Get-DiagLine($path) {
    $ls = [System.IO.File]::ReadAllText($path) -split "`r?`n"
    return (($ls | Where-Object { $_ -match 'warning:|error:' }) -join "`n")
}
$te = Get-DiagLine $diagEn
$tz = Get-DiagLine $diagZh
Write-Host ("    english input -> " + $te.Trim())
Write-Host ("    chinese input -> " + $tz.Trim())
if (-not $te.Contains($needleZh)) { Fail 'English #elifdef input did not produce the Chinese directive spelling' }
elseif (-not $tz.Contains($needleZh)) { Fail 'Chinese input did not produce the Chinese directive spelling' }
elseif ($te.Contains('#elifdef') -or $tz.Contains('#elifdef')) { Fail 'the English spelling #elifdef is still echoed in the diagnostic text' }
else { Pass 'both #elifdef and the Chinese spelling print the Chinese spelling' }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 8) per-spelling parity sweep'
& $python (Join-Path $here 'sweep.py') $cxx 2>&1 | Select-Object -Last 6 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) { Fail 'sweep.py reported a mismatch' } else { Pass 'sweep.py: all spellings at parity' }

# ---------------------------------------------------------------------------
Write-Host ''
if ($fail -eq 0) { Write-Host '  => PASS'; exit 0 }
Write-Host '  => FAIL'
exit 1
