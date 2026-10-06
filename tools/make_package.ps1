# ============================================================================
#  Assemble the distributable package: Chinese++-<ver>-win64\
#
#  Design notes (all measured, see docs\packaging design doc, section 7)
#  ---------------------------------------------------------------------------
#  * bin\ in the build tree is 650 MB because the driver family and the lld
#    family are the SAME binaries under different names:
#        clang.exe / clang-cl.exe / clang-cpp.exe / clang++.exe   identical SHA256
#        lld.exe / ld.lld.exe / lld-link.exe / wasm-ld.exe        identical SHA256
#        llvm-ar.exe / llvm-lib.exe / llvm-ranlib.exe             identical SHA256
#    (clang's driver dispatches on argv[0].)
#  * ZIP DOES NOT STORE HARDLINKS. So we ship ONE real copy of each family and
#    have the on-target installer recreate the other names as hardlinks.
#    That is 178 MB instead of 650 MB. Falls back to copying if linking fails.
#  * Build-time tools are NOT shipped: llvm-tblgen, clang-tblgen,
#    llvm-min-tblgen, clang-tidy-confusable-chars-gen, llvm-lit.
#  * lib\*.lib (918 MB) is the compiler's own build output, not for users.
#    Only lib\clang\<ver>\ (the resource dir) ships.
#  * licenses\ must travel with the binaries: LLVM is Apache-2.0 with LLVM
#    exceptions and we ship MODIFIED LLVM.
#
#  Usage:
#      powershell -File E:\Chinese++\tools\make_package.ps1
#      powershell -File E:\Chinese++\tools\make_package.ps1 -NoZip
#
#  ENCODING: THIS FILE IS INTENTIONALLY PURE ASCII.
#    PowerShell 5.1 reads a BOM-less file as GBK; non-ASCII in *code*
#    (paths, string literals) breaks the parser outright. Chinese user-facing
#    text lives in packaging\vscode-kit\messages.txt (a UTF-8 data file).
# ============================================================================

param(
    [string] $Version = '0.2',
    [switch] $NoZip,
    # Include a portable editor IN the zip (offline variant, ~322 MB zip).
    # Default is OFF: the official VS Code may not be redistributed (its license
    # forbids "share, publish ... the software"), so the default package is
    # toolchain-only and install.ps1 downloads the editor on the user's machine.
    [switch] $WithEditor,
    # Where to assemble the package. Default: <repo>\dist.
    #
    # WHY THIS IS A PARAMETER: "does the package work" must be tested where a
    # user actually puts it. Point this at a folder whose path contains
    # NON-ASCII characters (user instruction 2026-10-05) -- measured: a package
    # under a Chinese-named folder compiles and runs a Chinese include with no
    # flags, because bin\<driver>.cfg holds forward-slash ABSOLUTE paths.
    # See docs\packaging\...  section 7.10.  The folder is created if missing.
    #
    # NOTE: this file is PURE ASCII on purpose, so no non-ASCII path is ever
    # spelled here; pass it on the command line.
    [string] $OutDir
)

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$build    = Join-Path $root 'build\Release'
$binSrc   = Join-Path $build 'bin'
$resSrc   = Join-Path $build 'lib\clang'
$licSrc   = Join-Path $root 'licenses'
$packSrc  = Join-Path $root 'packaging'
$distRoot = if ($OutDir) { $OutDir } else { Join-Path $root 'dist' }
if (-not (Test-Path $distRoot)) { New-Item -ItemType Directory -Force $distRoot | Out-Null }
$pkgName  = "Chinese++-$Version-win64"
$pkg      = Join-Path $distRoot $pkgName

Write-Host "=== assemble $pkgName ===" -ForegroundColor Cyan

if (-not (Test-Path $binSrc)) { throw "no build tree at $binSrc" }

# ---------------------------------------------------------------------------
# 1. clean output
# ---------------------------------------------------------------------------
if (Test-Path $pkg) { Remove-Item -Recurse -Force $pkg }
New-Item -ItemType Directory -Force (Join-Path $pkg 'bin') | Out-Null

# ---------------------------------------------------------------------------
# 2. ONE real copy per binary family. THE ALIASES ARE *NOT* CREATED HERE.
#
#    Why: ZIP HAS NO HARDLINK CONCEPT. If we created the 9 aliases before
#    zipping, Compress-Archive would store each one's full content and the
#    download would be ~650 MB instead of ~180 MB -- defeating the whole point.
#    So the zip carries exactly one file per family, and install.ps1 recreates
#    the aliases (hardlink, falling back to a copy) after extraction.
#
#    $families: realName -> @(aliases to be created on the target machine)
# ---------------------------------------------------------------------------
$families = [ordered]@{
    'chinese++.exe' = @('clang.exe', 'clang++.exe', 'clang-cl.exe', 'clang-cpp.exe')
    'lld-link.exe'  = @('lld.exe', 'ld.lld.exe', 'wasm-ld.exe')
    'llvm-ar.exe'   = @('llvm-lib.exe', 'llvm-ranlib.exe')
    'clangd.exe'    = @()
    'llvm-rc.exe'   = @()
}

foreach ($real in $families.Keys) {
    $src = Join-Path $binSrc $real
    if (-not (Test-Path $src)) { throw "missing $real in $binSrc" }
    Copy-Item $src (Join-Path $pkg "bin\$real") -Force
}
$aliasCount = 0
foreach ($real in $families.Keys) { $aliasCount += $families[$real].Count }
$msg = "  bin: {0} real files shipped; {1} aliases will be created by install.ps1" -f $families.Count, $aliasCount
Write-Host $msg

# ---------------------------------------------------------------------------
# 3. resource dir  (lib\clang\<ver>\)
#
#    THREE directories must ship. Their layout is not guessed: it is exactly
#    what compiler-rt's own `cmake --install` produces (verified 2026-09-26),
#    and it agrees with what the driver asks for:
#
#       clang --print-runtime-dir
#           -> lib\clang\24\lib\windows
#       clang -fsanitize=address -###
#           -libpath:...\lib\clang\24\lib\windows
#
#    so:
#        include\      builtin headers, plus compiler-rt's sanitizer\ and
#                      profile\ headers                        REQUIRED
#        lib\windows\  every clang_rt.*.lib and clang_rt.*.dll  REQUIRED
#        share\        asan / cfi / hwasan / msan ignorelists   REQUIRED
#
#    Do NOT move the runtime libraries into lib\x86_64-pc-windows-msvc\.
#    The link line names that directory, but the runtime is resolved through
#    -libpath (lib\windows\). Measured: with only lib\windows\ populated,
#    -fsanitize=address links AND runs.
#
#    compiler-rt is NOT produced by the normal clang build. LLVM_ENABLE_RUNTIMES
#    is a separate configure; see tools\build_runtimes.ps1.
# ---------------------------------------------------------------------------
$ver = (Get-ChildItem $resSrc -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
if (-not $ver) { throw "no resource dir under $resSrc" }
$resDst = Join-Path $pkg "lib\clang\$ver"
New-Item -ItemType Directory -Force $resDst | Out-Null
Copy-Item (Join-Path $resSrc "$ver\include") (Join-Path $resDst 'include') -Recurse -Force
Write-Host "  lib\clang\$ver\include copied"

$rtWin = Join-Path $resSrc "$ver\lib\windows"
if (-not (Test-Path $rtWin)) {
    throw "compiler-rt missing at $rtWin -- run tools\build_runtimes.ps1 first"
}
$rtDstWin = Join-Path $resDst 'lib\windows'
New-Item -ItemType Directory -Force $rtDstWin | Out-Null
Copy-Item -Path (Join-Path $rtWin '*') -Destination $rtDstWin -Force
$shareSrc = Join-Path $resSrc "$ver\share"
if (Test-Path $shareSrc) { Copy-Item $shareSrc (Join-Path $resDst 'share') -Recurse -Force }

$rtFiles = @(Get-ChildItem $rtDstWin -File)
$rtSizeKB = [int](($rtFiles | Measure-Object Length -Sum).Sum / 1KB)
Write-Host ("  lib\clang\{0}\lib\windows: {1} runtime files, {2} KB" -f $ver, $rtFiles.Count, $rtSizeKB)

# ---------------------------------------------------------------------------
# 4. licenses  (Apache-2.0 section 4(a) and 4(b); NOT optional)
# ---------------------------------------------------------------------------
if (-not (Test-Path (Join-Path $licSrc 'LICENSE.TXT'))) {
    throw "licenses\LICENSE.TXT missing -- run tests\checks\verify_licenses.py first"
}
Copy-Item (Join-Path $licSrc 'LICENSE.TXT') (Join-Path $pkg 'LICENSE.TXT') -Force
Copy-Item (Join-Path $licSrc 'NOTICE.txt')  (Join-Path $pkg 'NOTICE.txt')  -Force
Write-Host "  LICENSE.TXT + NOTICE.txt copied"

# ---------------------------------------------------------------------------
# 5. installer, editor kit, examples
# ---------------------------------------------------------------------------
foreach ($d in @('vscode-kit', 'examples')) {
    $s = Join-Path $packSrc $d
    if (Test-Path $s) {
        Copy-Item $s (Join-Path $pkg $d) -Recurse -Force
        Write-Host "  $d copied"
    }
}
# Copy the PowerShell scripts and the launchers BY EXTENSION, not by name:
# several have Chinese file names and THIS FILE IS PURE ASCII on purpose, so it
# must not contain those names as literals.
Get-ChildItem $packSrc -File | Where-Object { $_.Extension -eq '.ps1' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $pkg $_.Name) -Force }
Get-ChildItem $packSrc -File | Where-Object { $_.Extension -in @('.cmd', '.bat') } |
    ForEach-Object {
        Copy-Item $_.FullName (Join-Path $pkg $_.Name) -Force
        Write-Host ("  launcher copied: " + $_.Name)
    }
# User-facing documents (the cheat sheet is GENERATED from the compiler's own
# tables by tools\make_cheatsheet.py, so it cannot drift). Copied by extension
# for the same ASCII reason as above.
Get-ChildItem $packSrc -File | Where-Object { $_.Extension -in @('.md', '.txt') } |
    ForEach-Object {
        Copy-Item $_.FullName (Join-Path $pkg $_.Name) -Force
        Write-Host ("  document copied: " + $_.Name)
    }

# ---------------------------------------------------------------------------
# 5a. the Chinese standard library itself, and the two scripts that tell the
#     compiler where it is (2026-10-05, decision D-22).
#
#     WHY IT MUST SHIP: `#include <...>` for our headers is not magic -- the
#     compiler only knows where to look because of a `<driver>.cfg` sitting next
#     to it, and that cfg points at THIS package's zhstdlib. Without zhstdlib in
#     the package a user cannot compile a single Chinese include, and nothing in
#     the package said so (measured 2026-10-05: make_package.ps1 had no mention
#     of zhstdlib at all, and dist\Chinese++-0.1-win64\ had no such folder).
#
#     WHY THE CFG IS NOT WRITTEN HERE: it holds ABSOLUTE paths, and the package
#     has no final location until the user unzips it. install.ps1 writes it.
#
#     ASCII NOTE: zhstdlib\'s four sub-folders have CHINESE names. This file
#     stays pure ASCII, so those names are never spelled here -- they live in
#     tools\zh_includes.ps1 (single source of truth), which ships in tools\.
#     Size measured 2026-10-05: 2.7 MB / 118 headers (the zip is ~178 MB, so
#     this is noise). `_来源\` is NOT included: it holds source manifests and
#     copies, takes no part in `#include`, and shipping it could shadow a real
#     Microsoft header.
# ---------------------------------------------------------------------------
$zhSrc = Join-Path $root 'zhstdlib'
if (-not (Test-Path $zhSrc)) {
    throw "no Chinese library at $zhSrc -- run tools\regen_zhstdlib.ps1 before packaging"
}
Copy-Item $zhSrc (Join-Path $pkg 'zhstdlib') -Recurse -Force
$zhFiles = @(Get-ChildItem (Join-Path $pkg 'zhstdlib') -Recurse -File)
$zhKB = [int](($zhFiles | Measure-Object Length -Sum).Sum / 1KB)
Write-Host ("  zhstdlib: {0} headers, {1} KB" -f $zhFiles.Count, $zhKB)

$pkgTools = Join-Path $pkg 'tools'
New-Item -ItemType Directory -Force $pkgTools | Out-Null
foreach ($n in @('zh_includes.ps1', 'make_zhcfg.ps1')) {
    $s = Join-Path $root "tools\$n"
    if (-not (Test-Path $s)) { throw "missing tools\$n (needed to write the include-path cfg)" }
    Copy-Item $s (Join-Path $pkgTools $n) -Force
}
Write-Host '  tools\zh_includes.ps1 + tools\make_zhcfg.ps1 copied'

# ---------------------------------------------------------------------------
# 5b. bundled portable editor (VSCodium)
#
#     WHY VSCODIUM AND NOT VS CODE
#       VS Code's *source* is MIT, but the official *binary* ships under the
#       Microsoft Software License Terms. Redistributing it inside our zip is
#       not clean. VSCodium is built from the same MIT source with MS branding
#       and telemetry removed, and its binaries are MIT -- redistributable.
#
#     WHY PORTABLE MODE ONLY
#       A "data" folder next to the editor executable makes the editor keep
#       settings and extensions inside that folder. The user's own VS Code
#       installation is never read or written. (User decision, 2026-09-25:
#       "initial version, must not disturb normal VS Code usage".)
#
#     KNOWN CONSEQUENCE, recorded honestly: Microsoft's C/C++ extension
#     (ms-vscode.cpptools) is not licensed for VSCodium, so DEBUGGING is not
#     available out of the box. clangd (via Open VSX) covers highlighting,
#     completion and diagnostics, which is the part that shows off the Chinese
#     keywords.
# ---------------------------------------------------------------------------
$codiumZip = Join-Path $root 'build\_downloads\VSCodium-win32-x64.zip'
if ($WithEditor -and (Test-Path $codiumZip)) {
    Write-Host '  bundling VSCodium (portable)...'
    $edst = Join-Path $pkg 'vscodium'
    New-Item -ItemType Directory -Force $edst | Out-Null
    Expand-Archive -Path $codiumZip -DestinationPath $edst -Force
    # portable mode: everything (settings, extensions) stays in this folder
    $exe = Get-ChildItem $edst -Recurse -Filter 'VSCodium.exe' -File | Select-Object -First 1
    if ($exe) {
        New-Item -ItemType Directory -Force (Join-Path $exe.Directory.FullName 'data') | Out-Null
        $emsg = "  vscodium: " + $exe.Directory.Name + "\VSCodium.exe (portable mode: data\)"
        Write-Host $emsg
    } else { Write-Host '  [warn] VSCodium.exe not found after extraction' -ForegroundColor Yellow }
} else {
    if ($WithEditor) {
        Write-Host '  [warn] -WithEditor given but no VSCodium zip in build\_downloads' -ForegroundColor Yellow
    }
    Write-Host '  toolchain-only package (install.ps1 downloads the editor on demand)' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 6. MANIFEST  (what shipped, from where, and the hash of each unique binary)
# ---------------------------------------------------------------------------
$lines = @()
$lines += "Chinese++ $Version  (win64, target x86_64-pc-windows-msvc)"
$lines += "built: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$lines += ""
$lines += "=== bin (one real file per family; aliases are NOT in the zip) ==="
foreach ($real in $families.Keys) {
    $p = Join-Path $pkg "bin\$real"
    $h = (Get-FileHash $p -Algorithm SHA256).Hash
    $lines += ("{0,-18} {1,6} MB  {2}" -f $real, [int]((Get-Item $p).Length/1MB), $h)
}
$lines += ""
$lines += "aliases install.ps1 creates (hardlink, falling back to a copy):"
foreach ($real in $families.Keys) {
    foreach ($alias in $families[$real]) { $lines += "  $alias  ->  $real" }
}
$lines += ""
$lines += "=== NOT shipped on purpose ==="
$lines += "  lib\*.lib                     918 MB, compiler's own build output"
$lines += "  llvm-tblgen / clang-tblgen / llvm-min-tblgen /"
$lines += "  clang-tidy-confusable-chars-gen / llvm-lit    build-time tools"
$lines += "  opt / llc / llvm-as / llvm-dis / llvm-config / lldb /"
$lines += "  clang-tidy / libclang / polly                  LLVM tools, not"
$lines += "                                                 needed to compile"
$lines += ""
$lines += "=== compiler-rt runtime libraries (SHIPPED) ==="
$lines += "  lib\clang\$ver\lib\windows\      the runtimes themselves"
$lines += "  lib\clang\$ver\include\sanitizer\  and include\profile\  headers"
$lines += "  lib\clang\$ver\share\            asan/cfi/hwasan/msan ignorelists"
foreach ($f in ($rtFiles | Sort-Object Name)) {
    $lines += ("  {0,-50} {1,6} KB" -f $f.Name, [int]($f.Length / 1KB))
}
$lines += ""
$lines += "  -fsanitize=address    VERIFIED: links, and catches a real"
$lines += "                        heap-use-after-free at run time."
$lines += "                        NOTE: clang_rt.asan_dynamic-x86_64.dll must"
$lines += "                        be on PATH (or beside the .exe) to RUN the"
$lines += "                        program. install.ps1 puts it on PATH."
$lines += "  --coverage            VERIFIED: links and runs."
$lines += "  -fsanitize=undefined  CANNOT LINK ON ITS OWN here. Fails with:"
$lines += "                          __imp_getenv            (gone with /MD)"
$lines += "                          __imp_CommandLineToArgvW (gone with shell32.lib)"
$lines += "                          __imp_SymLoadModuleEx    (needs dbghelp.lib)"
$lines += "                          __coe_win::ContinueOnError / RawWrite"
$lines += "                        __coe_win is implemented in NEITHER this VS/SDK"
$lines += "                        NOR anywhere in the LLVM source tree -- and not"
$lines += "                        in Microsoft's own clang_rt.ubsan_standalone"
$lines += "                        either (member lists compared). Upstream skew."
$lines += "  -fsanitize=address,undefined   VERIFIED: links, and UBSan really"
$lines += "                        reports undefined behaviour. This is the form"
$lines += "                        to use -- UBSan needs the ASan runtime to"
$lines += "                        resolve those symbols. Do not use it alone."
$lines += "  -fopenmp              works, but not because of this package:"
$lines += "                        Visual Studio already ships libomp.lib in"
$lines += "                        VC\Tools\MSVC\<ver>\lib\x64\. It is not"
$lines += "                        shipped here and is not needed."
$lines += "  -fsanitize=address/undefined need MSVC STL + Windows SDK anyway."

$lines += ""
$lines += "=== REQUIRED on the user's machine (not in this package) ==="
$lines += "  Visual Studio Build Tools: MSVC STL, Windows SDK, link.exe"
$lines += "  See NOTICE.txt section 4."
$lines | Set-Content -Encoding UTF8 (Join-Path $pkg 'MANIFEST.txt')
Write-Host "  MANIFEST.txt written"

# ---------------------------------------------------------------------------
# 7. summary + zip
# ---------------------------------------------------------------------------
$size = [int]((Get-ChildItem $pkg -Recurse -File | Measure-Object Length -Sum).Sum/1MB)
Write-Host ""
Write-Host ("uncompressed: {0} MB" -f $size) -ForegroundColor Green

if (-not $NoZip) {
    $zip = Join-Path $distRoot "$pkgName.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    # Retry: the freshly copied ~79 MB executables are often still being scanned
    # by Windows Defender for a few seconds, which makes Compress-Archive fail
    # with "being used by another process". Observed twice (2026-09-25); it is
    # predictable, so it is handled here instead of by hand.
    $ok = $false
    for ($i = 1; $i -le 6; $i++) {
        try {
            Compress-Archive -Path $pkg -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
            $ok = $true; break
        } catch {
            Write-Host ("  zip attempt {0} failed ({1}); retrying in {2}s" -f `
                        $i, $_.Exception.GetType().Name, (3 * $i)) -ForegroundColor DarkGray
            Start-Sleep -Seconds (3 * $i)
            if (Test-Path $zip) { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
        }
    }
    if (-not $ok) { throw "could not create $zip after 6 attempts" }
    $zsize = [int]((Get-Item $zip).Length/1MB)
    Write-Host ("zip: {0} MB  ->  {1}" -f $zsize, $zip) -ForegroundColor Green
}

Write-Host ""
Write-Host "next: verify the PACKAGE (not the build tree):"
Write-Host "  powershell -File $pkg\verify.ps1"
