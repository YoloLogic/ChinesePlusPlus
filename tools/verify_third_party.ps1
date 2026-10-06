# ============================================================================
#  Verify that ORDINARY third-party C++ projects still build with our compiler.
#
#  Why this exists
#  ---------------
#  The project's hard rule is: after any Chinese-ification, an arbitrary
#  open-source C++ project must still compile with our compiler. Every other
#  test in this repo uses code WE wrote, which cannot prove that rule. This
#  script compiles code OTHER PEOPLE wrote.
#
#  What it does
#  ------------
#  For each project under third_party\src\, it configures, builds and tests
#  the project TWICE:
#      ours  = E:\Chinese++\build\Release\bin\clang.exe / chinese++.exe
#      stock = the unmodified clang shipped inside Visual Studio
#  and compares the three exit codes (configure / build / ctest). Anything the
#  two sides disagree on is a real finding.
#
#  Layout (see third_party\README.md)
#  ----------------------------------
#      third_party\src\      clean upstream clone, never edited
#      third_party\build\    generated build trees (safe to delete)
#      third_party\logs\     raw logs of every run, one per project+side
#
#  Usage
#  -----
#      powershell -File E:\Chinese++\tools\verify_third_party.ps1
#      powershell -File E:\Chinese++\tools\verify_third_party.ps1 -Projects tinyxml2
#      powershell -Command "& 'E:\Chinese++\tools\verify_third_party.ps1' -Projects cJSON,zlib -Variants static"
#
#      # Reproduce the two packaging defects exactly as our distribution ships
#      # (see README.md section 4). Logs get a -plain / -nolld suffix.
#      powershell -Command "& 'E:\Chinese++\tools\verify_third_party.ps1' -Toolchain plain -Projects tinyxml2"
#      powershell -Command "& 'E:\Chinese++\tools\verify_third_party.ps1' -Toolchain nolld -Projects tinyxml2"
#
#  Notes
#  -----
#  * This file is pure ASCII on purpose: PowerShell 5.1 reads a BOM-less file
#    as GBK, so a Chinese literal here would be mangled into a bad path.
#  * Earlier rounds passed -DCMAKE_LINKER_TYPE=MSVC to BOTH sides, because
#    CMake asks Clang for "-fuse-ld=lld-link" and our distribution had no
#    lld-link.exe. That gap is CLOSED (2026-09-23): bin\ now ships lld-link.exe
#    + llvm-ar/llvm-lib/llvm-ranlib/llvm-rc, so the default 'plain' toolchain
#    runs exactly what we ship, with no substitution. The old behaviour is
#    still reachable with -Toolchain workaround, for comparison.
#  * Build tools live OUTSIDE this repo (CLion's CMake/Ninja, the Windows SDK
#    rc.exe), so this script needs the wider sandbox: cmake probes the
#    compiler by spawning it with piped stdio, which deadlocks when confined.
# ============================================================================

param(
    [string[]] $Projects = @('tinyxml2', 'pugixml', 'fmt', 'googletest'),
    [string]   $Root     = 'E:\Chinese++\third_party',
    # Which build shape to exercise. The first round only ever covered one:
    # Ninja + Release + static library. Each new shape is a new real risk, and
    # 'shared' / 'debug' cost nothing but a flag.
    [ValidateSet('static', 'shared', 'debug')]
    [string[]] $Variants = @('static'),
    # Which toolchain to give the compiler under test:
    #   plain (default) - exactly what our distribution ships TODAY, used as
    #                     shipped: the drivers in build\Release\bin plus the
    #                     lld-link / llvm-ar / llvm-lib / llvm-ranlib / llvm-rc
    #                     built on 2026-09-23. This is the honest default -
    #                     verification then tests what a user really gets.
    #   workaround      - borrowed llvm-ar/llvm-ranlib from the stock LLVM plus
    #                     -DCMAKE_LINKER_TYPE=MSVC. HISTORICAL: it exists to
    #                     isolate the COMPILER by hiding gaps in our toolchain.
    #   nolld           - MSVC link.exe but no archiver; reproduces the
    #                     CMAKE_AR-NOTFOUND packaging defect.
    [ValidateSet('plain', 'workaround', 'nolld')]
    [string]   $Toolchain = 'plain',
    # Which directory holds OUR drivers. Default = the development build tree
    # (the pre-18.48 behaviour, and what every earlier round used).
    #
    # Point it at a DISTRIBUTION package's bin\ to verify what a USER really
    # gets -- in particular the bundled (zero-Visual-Studio) substrate:
    #     -OursBin E:\Chinese++\dist\Chinese++-0.2-win64\bin
    # When it is not the development default the logs get a -bundled suffix,
    # so this round's evidence never overwrites the earlier rounds'.
    [string]   $OursBin  = 'E:\Chinese++\build\Release\bin'
)

# Forward slashes only: CMake writes the compiler path verbatim into its cache
# and then re-parses it, where a backslash starts an escape.
$oursBinNorm  = ($OursBin -replace '\\', '/').TrimEnd('/')
$substrateTag = ''
if ($oursBinNorm -ne 'E:/Chinese++/build/Release/bin') { $substrateTag = '-bundled' }

$ErrorActionPreference = 'Continue'

$cmake = 'E:\CLion 2026.1.2\bin\cmake\win\x64\bin\cmake.exe'
$ctest = 'E:\CLion 2026.1.2\bin\cmake\win\x64\bin\ctest.exe'
$ninja = 'E:/CLion 2026.1.2/bin/ninja/win/x64/ninja.exe'

# MSVC's link.exe shells out to rc.exe for the manifest, and finds it on PATH
# only. A Visual Studio developer prompt provides that PATH; we are a plain
# shell, so we add the Windows SDK bin directory ourselves. We deliberately do
# NOT put the Visual Studio LLVM bin directory on PATH: that directory contains
# lld-link.exe, and borrowing it would hide the fact that OUR distribution
# lacks lld-link.exe (see third_party\README.md - that is a recorded finding).
$sdkBin = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64'
if ($env:PATH -notlike "*$sdkBin*") { $env:PATH = "$sdkBin;$env:PATH" }
# CMake writes this value verbatim into CMakeRCCompiler.cmake and then parses
# that file, where a backslash starts an escape: the path must use forward
# slashes only, or configuration dies with "Invalid character escape '\P'".
$rc = ($sdkBin -replace '\\', '/') + '/rc.exe'

# rc.exe needs the SDK headers on its OWN include path (a project with a .rc
# file dies with "RC1015: cannot open include file 'winver.h'"), and the SDK's
# own corecrt.h then pulls vcruntime.h out of the MSVC include directory. We
# pass them through CMAKE_RC_FLAGS rather than exporting INCLUDE, so the
# COMPILER under test sees exactly the same environment it did before - only
# the resource compiler is helped. 8.3 short paths keep every argument free of
# spaces.
$sdkInc  = 'C:/PROGRA~2/WI3CF2~1/10/Include/100261~1.0'
$msvcInc = 'C:/PROGRA~1/MICROS~4/2022/COMMUN~1/VC/Tools/MSVC/14.44.35207/include'
$rcFlags = "-I$sdkInc/um -I$sdkInc/shared -I$sdkInc/ucrt -I$sdkInc/winrt -I$msvcInc"

# Ninja lives inside CLion's install, not on the system PATH. The projects'
# own CMake tests (zlib's find_package / add_subdirectory tests) start NESTED
# cmake runs and die with "unable to find a build program corresponding to
# Ninja" unless the directory is on PATH. Added for both sides.
$ninjaDir = 'E:\CLion 2026.1.2\bin\ninja\win\x64'
if ($env:PATH -notlike "*$ninjaDir*") { $env:PATH = "$ninjaDir;$env:PATH" }

$sides = @(
    @{ tag = 'ours';  cc = "$oursBinNorm/clang.exe";
       cxx = "$oursBinNorm/chinese++.exe" },
    @{ tag = 'stock'; cc = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin/clang.exe';
       cxx = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin/clang++.exe' }
)

# Our build tree ships ONLY the compiler drivers: no lld-link.exe, no
# llvm-ar.exe, no llvm-lib.exe, no llvm-ranlib.exe (the stock toolchain ships
# all of them). CMake therefore cannot archive a static library with our
# toolchain - it runs the literal string "CMAKE_AR-NOTFOUND qc ...". That is a
# recorded packaging finding, not a compiler bug, so for this verification the
# archiver is borrowed from the stock LLVM and given to BOTH sides, leaving the
# compiler as the only variable under test.
$stockLlmBin = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin'
$arTools = @("-DCMAKE_AR=$stockLlmBin/llvm-ar.exe",
             "-DCMAKE_RANLIB=$stockLlmBin/llvm-ranlib.exe")

# Per-project switches that turn the project's own test suite on.
$extra = @{
    'tinyxml2'   = @('-Dtinyxml2_BUILD_TESTING=ON')
    'pugixml'    = @('-DPUGIXML_BUILD_TESTS=ON')
    'fmt'        = @('-DFMT_TEST=ON', '-DFMT_DOC=OFF')
    'googletest' = @('-Dgtest_build_tests=ON', '-Dgmock_build_tests=ON', '-DINSTALL_GTEST=OFF')
    # Pure C projects. These exercise the C driver (clang.exe), which the first
    # round never did: all four projects then were C++, so our C compiler had
    # only ever been fed the 3-line file CMake uses for ABI detection.
    'cJSON'      = @('-DENABLE_CJSON_TEST=ON', '-DENABLE_CJSON_UTILS=ON',
                     # cJSON turns on -Werror with ~25 extra warning flags; its
                     # own cJSON.c trips -Wcast-qual under EVERY clang (19 and 24
                     # alike). That is the project's warning policy, not our
                     # compiler, so it is switched off for a fair test.
                     '-DENABLE_CUSTOM_COMPILER_FLAGS=OFF')
    'zlib'       = @('-DZLIB_BUILD_TESTING=ON')
    'libuv'      = @('-DLIBUV_BUILD_TESTS=ON', '-DLIBUV_BUILD_BENCH=OFF', '-DENABLE_CLANG_TIDY=OFF')
}

# Build shapes. 'static' keeps the original log names so the first round's
# evidence stays valid.
# NOTE: PowerShell variable names are case-insensitive, so this table must NOT
# be called $variants - that would be the validated parameter $Variants itself.
$variantDefs = @{
    'static' = @{ suffix = '';        buildType = 'Release'; args = @() }
    'shared' = @{ suffix = '-shared'; buildType = 'Release'; args = @('-DBUILD_SHARED_LIBS=ON') }
    'debug'  = @{ suffix = '-debug';  buildType = 'Debug';   args = @() }
}

function Invoke-Step {
    param([string] $name, [string] $exe, [string[]] $argv, [string] $log)
    "-- $name --" | Out-File -Append -Encoding utf8 $log
    & $exe @argv 2>&1 | Out-File -Append -Encoding utf8 $log
    return $LASTEXITCODE
}

function Get-TestSummary {
    param([string] $log)
    $m = Select-String -Path $log -Pattern 'tests passed.*out of (\d+)' -Encoding utf8 |
         Select-Object -Last 1
    if ($m) { return $m.Line.Trim() }
    return '(no ctest summary)'
}

function Get-FailedTests {
    param([string] $log)
    # ctest marks a failing test either ***Failed or ***Exception: SegFault etc.
    # Returns a SORTED comma-joined list so the two sides can be compared as a
    # SET. Comparing only the ctest exit code is not enough: both sides can exit
    # 8 while failing DIFFERENT tests - that happened (zlib), and an exit-code
    # comparison hid it.
    $hits = Select-String -Path $log -Pattern 'Test\s+#\d+:\s+(\S+)\s.*\*\*\*(?:Failed|Exception|Timeout|Not Run)' -Encoding utf8
    if (-not $hits) { return '' }
    $names = @()
    foreach ($h in $hits) { $names += $h.Matches[0].Groups[1].Value }
    return (($names | Sort-Object -Unique) -join ',')
}

function Get-DllDirs {
    param([string] $Root)
    # A shared-library build puts the .dll next to the .exe only sometimes; a
    # test that runs the .exe then dies with 0xc0000135 (STATUS_DLL_NOT_FOUND).
    # Real developers add the output directory to PATH; so do we, for both
    # sides, so 'shared' variants actually TEST something instead of failing on
    # a missing DLL.
    $dirs = @($Root)
    $subs = Get-ChildItem $Root -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { @(Get-ChildItem $_.FullName -Filter *.dll -File -ErrorAction SilentlyContinue).Count -gt 0 } |
            Select-Object -ExpandProperty FullName
    foreach ($s in $subs) { $dirs += $s }
    return $dirs
}

$rows = @()

foreach ($proj in $Projects) {

    $srcDir = Join-Path $Root "src\$proj"
    if (-not (Test-Path $srcDir)) { Write-Host "SKIP  $proj (no source at $srcDir)"; continue }

    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host "  $proj"
    Write-Host ('=' * 72)

    foreach ($variantName in $Variants) {

        if (-not $variantDefs.ContainsKey($variantName)) { Write-Host "SKIP  unknown variant $variantName"; continue }
        $v   = $variantDefs[$variantName]
        $sfx = $v.suffix
        $row = [ordered]@{ Project = $proj; Variant = $variantName }

        foreach ($side in $sides) {

            $tag = $side.tag
            $bld = Join-Path $Root "build\$proj-$tag$sfx"
            $logName = "$proj-$tag$sfx"
            if ($Toolchain -ne 'workaround') { $logName += "-$Toolchain$substrateTag" }
            $log = Join-Path $Root "logs\$logName.log"

            if (Test-Path $bld) { Remove-Item -Recurse -Force $bld -ErrorAction SilentlyContinue }
            "===== $proj / $variantName / $tag  (toolchain=$Toolchain) =====" | Out-File -Encoding utf8 $log

            $argv = @('-S', $srcDir, '-B', $bld, '-G', 'Ninja',
                      "-DCMAKE_MAKE_PROGRAM=$ninja",
                      "-DCMAKE_RC_COMPILER=$rc",
                      "-DCMAKE_RC_FLAGS=$rcFlags",
                      "-DCMAKE_BUILD_TYPE=$($v.buildType)",
                      "-DCMAKE_C_COMPILER=$($side.cc)",
                      "-DCMAKE_CXX_COMPILER=$($side.cxx)")
            if ($Toolchain -ne 'plain')      { $argv += '-DCMAKE_LINKER_TYPE=MSVC' }
            if ($Toolchain -eq 'workaround') { $argv += $arTools }
            if ($extra.ContainsKey($proj))   { $argv += $extra[$proj] }
            $argv += $v.args

            $c1 = Invoke-Step 'configure' $cmake $argv $log
            $c2 = 1
            $c3 = 1
            if ($c1 -eq 0) {
                $c2 = Invoke-Step 'build' $cmake @('--build', $bld) $log
                if ($c2 -eq 0) {
                    $savedPath = $env:PATH
                    $env:PATH = ((Get-DllDirs $bld) -join ';') + ';' + $env:PATH
                    $c3 = Invoke-Step 'ctest' $ctest @('--test-dir', $bld, '--output-on-failure') $log
                    $env:PATH = $savedPath
                }
            }

            Write-Host ("  {0,-7} {1,-6} configure={2}  build={3}  ctest={4}" -f $variantName, $tag, $c1, $c2, $c3)
            Write-Host ("          {0}" -f (Get-TestSummary $log))
            $bad = Get-FailedTests $log
            if ($bad) { Write-Host ("          failed: {0}" -f $bad) }

            $row["$tag-conf"]   = $c1
            $row["$tag-build"]  = $c2
            $row["$tag-test"]   = $c3
            $row["$tag-failed"] = $bad
        }

        # What matters is not "all green" - it is "does OUR compiler behave
        # exactly like the unmodified one". A test that fails identically on
        # both sides is an upstream/environment problem, not a Chinese-keyword
        # regression; a difference between the two sides is what we hunt for.
        # The comparison covers BOTH the exit codes AND the set of failing
        # tests: two sides can exit 8 while failing different tests (zlib did).
        $oursZero = ($row['ours-conf']  -eq 0 -and $row['ours-build'] -eq 0 -and $row['ours-test'] -eq 0)
        $codesSame = ($row['ours-conf']  -eq $row['stock-conf']  -and
                      $row['ours-build'] -eq $row['stock-build'] -and
                      $row['ours-test']  -eq $row['stock-test'])
        $setsSame  = ($row['ours-failed'] -eq $row['stock-failed'])
        $same      = ($codesSame -and $setsSame)
        if     ($same -and $oursZero) { $row['Verdict'] = 'PASS' }
        elseif ($same)                { $row['Verdict'] = 'SAME' }
        else                          { $row['Verdict'] = 'FAIL' }
        if (-not $setsSame) {
            Write-Host '          *** the two sides failed DIFFERENT tests ***'
            Write-Host ("          ours : {0}" -f $row['ours-failed'])
            Write-Host ("          stock: {0}" -f $row['stock-failed'])
        }
        $rows += [pscustomobject]$row
    }
}

Write-Host ''
Write-Host ('=' * 72)
Write-Host '  summary'
Write-Host ('=' * 72)
$rows | Select-Object Project, Variant, 'ours-conf', 'ours-build', 'ours-test',
                            'stock-conf', 'stock-build', 'stock-test', Verdict |
    Format-Table -AutoSize | Out-String -Width 200 | Write-Host

foreach ($r in ($rows | Where-Object { $_.Verdict -eq 'FAIL' -and $_.'ours-failed' -ne $_.'stock-failed' })) {
    Write-Host ("{0} / {1}: the two sides failed DIFFERENT tests" -f $r.Project, $r.Variant)
    Write-Host ("    ours : {0}" -f $r.'ours-failed')
    Write-Host ("    stock: {0}" -f $r.'stock-failed')
}

Write-Host 'PASS = ours is all green and identical to stock'
Write-Host 'SAME = ours fails exactly like stock (upstream/environment, not us)'
Write-Host 'FAIL = ours differs from stock  <-- this is what we are hunting for'

$failed = @($rows | Where-Object { $_.Verdict -eq 'FAIL' })
Write-Host ("cases={0}  pass={1}  same={2}  fail={3}   (case = project x variant)" -f $rows.Count,
            @($rows | Where-Object { $_.Verdict -eq 'PASS' }).Count,
            @($rows | Where-Object { $_.Verdict -eq 'SAME' }).Count,
            $failed.Count)

if ($failed.Count -gt 0) { exit 1 }
exit 0
