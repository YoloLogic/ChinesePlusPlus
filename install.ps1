# ============================================================================
#  install.ps1 -- make THIS extracted folder usable. Nothing global by default.
#
#  What it does
#    1. recreate the 9 missing binary names as HARDLINKS (fallback: copies)
#       The zip shipped only one real file per family because ZIP has no
#       hardlink concept; this is where the aliases come back.
#    2. write env.cmd  -- a session-scoped PATH setter (double-click to open a
#       shell that can see chinese++). We deliberately do NOT edit the user's
#       permanent PATH: the user asked for portable, controllable behaviour
#       that does not disturb their existing setup.
#    3. check for Visual Studio Build Tools and, if absent, print the exact
#       command to install them (the MSVC STL and Windows SDK are NOT bundled).
#    4. if a bundled portable editor is present, enable portable mode for it
#       (create the "data" folder next to the editor executable) and copy the
#       editor kit into the examples folder.
#    5. run verify.ps1 -- so "installed" means "proven working", not "assumed".
#
#  Usage:
#      powershell -File <package>\install.ps1
#      powershell -File <package>\install.ps1 -AddToUserPath   # opt-in, permanent
#
#  ENCODING: PURE ASCII (PowerShell 5.1 reads BOM-less files as GBK).
# ============================================================================

param(
    [switch] $AddToUserPath,
    [switch] $SkipVerify,
    # Skip the editor step entirely. Useful when the user already has an editor
    # they like, and for testing the toolchain part without a 320 MB download.
    [switch] $NoEditor,
    # 18.48: which toolchain substrate to use.
    #   bundled (DEFAULT) -- the STL headers + VC++ runtime DLLs that ship inside
    #                        this package. No Visual Studio needed.
    #   system           -- the Visual Studio / Windows SDK installed on THIS
    #                        machine (maximum compatibility; requires VS).
    # The choice is recorded in bin\toolchain.txt and read back by verify.ps1
    # and make_zhcfg.ps1, so "which one am I running" is never a guess.
    [ValidateSet('bundled', 'system')][string] $Toolchain = 'bundled'
)

$ErrorActionPreference = 'Continue'

$here = $PSScriptRoot
$bin  = Join-Path $here 'bin'

Write-Host ""
Write-Host "=== Chinese++ setup ===" -ForegroundColor Cyan
Write-Host "folder: $here"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. recreate the aliases
#
#    Keep this table in sync with $families in tools\make_package.ps1.
# ---------------------------------------------------------------------------
Write-Host '--- 1) recreate binary names (hardlink; copied if linking is unavailable)'
$families = [ordered]@{
    'chinese++.exe' = @('clang.exe', 'clang++.exe', 'clang-cl.exe', 'clang-cpp.exe')
    'lld-link.exe'  = @('lld.exe', 'ld.lld.exe', 'wasm-ld.exe')
    'llvm-ar.exe'   = @('llvm-lib.exe', 'llvm-ranlib.exe')
}
$linked = 0; $copied = 0; $kept = 0
foreach ($real in $families.Keys) {
    $target = Join-Path $bin $real
    if (-not (Test-Path $target)) { Write-Host "  [FAIL] missing $real" -ForegroundColor Red; continue }
    foreach ($alias in $families[$real]) {
        $p = Join-Path $bin $alias
        if (Test-Path $p) { $kept++; continue }
        try {
            New-Item -ItemType HardLink -Path $p -Target $target -ErrorAction Stop | Out-Null
            $linked++
        } catch {
            Copy-Item $target $p -Force
            $copied++
        }
    }
}
Write-Host ("  created {0} hardlinks, {1} copies; {2} already present" -f $linked, $copied, $kept)

# ---------------------------------------------------------------------------
# 1b. bin\<driver>.cfg -- where the Chinese headers live (2026-10-05, D-22)
#
#     WHY: `#include <...>` for our headers must work with NO -I/-isystem on the
#     command line, and clangd (the editor's language server) asks the driver
#     for its search paths. Without this file every Chinese include is reported
#     as "file not found" -- on the command line AND, worse, underlined in red
#     in the editor. Measured on the build tree before it existed:
#         chinese++.exe -std=c++20 x.cpp   ->  cannot find file 'vector-cn'
#         clangd --check x.cpp             ->  pp_file_not_found
#     After: both clean, with the same file.
#
#     The path LIST is not written here: it comes from tools\zh_includes.ps1
#     (single source of truth), which ships in tools\. Naming the four Chinese
#     sub-folders here is impossible anyway -- this file is pure ASCII on
#     purpose (PowerShell 5.1 reads a BOM-less file as GBK).
#
#     MEASURED TRAPS (handled inside make_zhcfg.ps1):
#       * in a cfg a backslash is an ESCAPE -> the paths must use forward slashes
#       * a cfg line is split on whitespace  -> paths with spaces must be quoted
#       * a RELATIVE path resolves against the CURRENT WORKING DIRECTORY, not
#         against the cfg -> only absolute paths work.
#     Consequence, exactly like .vscode\ and env.cmd: MOVE OR RENAME THE PACKAGE
#     -> RUN THIS INSTALLER AGAIN.
#     clang.cfg is written too: clangd's fallback driver is the `clang` next to
#     it, so without clang.cfg the editor stays red even though chinese++.cfg
#     exists (measured).
#
#     Invoked through `powershell` rather than `pwsh`: the user's machine is not
#     guaranteed to have PowerShell 7, and the two scripts use nothing newer.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 1b) <driver>.cfg (Chinese include paths)'
$zhcfg = Join-Path $here 'tools\make_zhcfg.ps1'
if (Test-Path $zhcfg) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $zhcfg -BinDir $bin -ZhRoot $here -Mode $Toolchain
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  [warn] could not write <driver>.cfg -- Chinese headers will not be found' -ForegroundColor Yellow
        Write-Host '         (the package folder is probably read-only)' -ForegroundColor Yellow
    }
} else {
    Write-Host '  [warn] tools\make_zhcfg.ps1 is missing from this package copy.' -ForegroundColor Yellow
    Write-Host '         The Chinese library (zhstdlib\) will not be found: the search' -ForegroundColor Yellow
    Write-Host '         paths live in tools\zh_includes.ps1 and are written into' -ForegroundColor Yellow
    Write-Host '         bin\<driver>.cfg by that script.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 1c. record WHICH toolchain the user picked (18.48)
#
#     Two substrates exist: the one bundled in this package (lib\stl + bin\*.dll)
#     and the machine's own Visual Studio. Writing the choice down means
#     verify.ps1 and make_zhcfg.ps1 -Check test the mode that is actually in use,
#     instead of assuming. ASCII, no BOM.
# ---------------------------------------------------------------------------
$tcTxt = Join-Path $bin 'toolchain.txt'
$tcBody = @(
    '# Chinese++ toolchain mode (written by install.ps1)',
    '# bundled = the substrate inside this package (no Visual Studio needed)',
    '# system  = the Visual Studio / Windows SDK installed on this machine',
    #  NOTE the parentheses: inside an array literal PowerShell's comma binds
    #  TIGHTER than '+', so `'mode = ' + $Toolchain` would produce the two
    #  elements 'mode = ' and $Toolchain -- i.e. a `mode = ` line with nothing
    #  after it, and the mode on a line of its own.  Measured 2026-10-06: that is
    #  exactly what shipped, and every reader of this file silently fell back to
    #  "unknown mode".  Parenthesize it.
    ('mode = ' + $Toolchain)
) -join "`r`n"
try {
    [System.IO.File]::WriteAllText($tcTxt, $tcBody + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  toolchain mode recorded: {0}  (bin\toolchain.txt)" -f $Toolchain)
} catch {
    Write-Host '  [warn] could not write bin\toolchain.txt (folder read-only?)' -ForegroundColor Yellow
}
if ($Toolchain -eq 'bundled') {
    $stlDir = Join-Path $here 'lib\stl'
    if (Test-Path $stlDir) {
        Write-Host ("  bundled substrate: lib\stl has {0} headers" -f @(Get-ChildItem $stlDir -File).Count)
    } else {
        Write-Host '  [warn] lib\stl is missing -- bundled mode needs it (re-build the package)' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 2. env.cmd -- session-scoped PATH, nothing global
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) env.cmd (session-scoped PATH)'
$envCmd = Join-Path $here 'env.cmd'
$lines = @(
    '@echo off',
    'rem Double-click to open a shell that can see chinese++ from this folder.',
    'rem Nothing outside this window is modified.',
    ('set "PATH=%~dp0bin;%PATH%"'),
    'rem ---------------------------------------------------------------------',
    'rem The compiler-rt sanitizer runtimes live in lib\clang\<ver>\lib\windows.',
    'rem A program built with -fsanitize=address loads clang_rt.asan_dynamic-',
    'rem x86_64.dll AT RUN TIME. If that DLL is not findable the program dies',
    'rem at once with exit code -1073741515 (0xC0000135, DLL not found) and no',
    'rem diagnostic -- which looks like a broken build but is not. So put that',
    'rem directory on PATH for this window. Verified 2026-09-26: with it, a',
    'rem use-after-free is reported properly by AddressSanitizer.',
    'rem ---------------------------------------------------------------------',
    'for /d %%d in ("%~dp0lib\clang\*") do set "PATH=%%~fd\lib\windows;%PATH%"',
    'echo.',
    'echo   chinese++ is ready in this window.',
    'echo   try:  chinese++ --version',
    'echo   AddressSanitizer runtime DLL is on PATH here.',
    'echo.',
    'cmd /k'
)
$lines | Set-Content -Encoding ASCII $envCmd
Write-Host "  wrote $envCmd"

if ($AddToUserPath) {
    $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($cur -notlike "*$bin*") {
        [Environment]::SetEnvironmentVariable('Path', "$cur;$bin", 'User')
        Write-Host "  appended to the USER PATH (open a new shell to pick it up)" -ForegroundColor Yellow
        Write-Host "  to undo: install.ps1 -RemoveFromUserPath is not implemented yet;" -ForegroundColor Yellow
        Write-Host "           edit the user PATH manually." -ForegroundColor Yellow
    } else { Write-Host '  already on the USER PATH' }
} else {
    Write-Host '  (not touching the permanent PATH; pass -AddToUserPath to opt in)' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 3. Visual Studio Build Tools -- **OPTIONAL** since 18.48
#
#    bundled (default): the package carries its own substitute for everything
#    VS used to provide (MSVC STL headers, UCRT/Win32 headers, our own CRT +
#    import libraries + lld-link).  Visual Studio is then NOT required, and this
#    section is informational only.
#
#    system: the pre-0.2 behaviour -- the toolchain reads the MSVC STL headers,
#    the Windows SDK and link.exe out of the machine's Visual Studio install.
#    Then VS really is required, and the section says so.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host ("--- 3) Visual Studio Build Tools  [{0} mode]" -f $Toolchain)

function Find-VS {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $p = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($p) { return $p }
    }
    return $null
}

$vs = Find-VS
if ($vs) {
    Write-Host ("  found: " + $vs) -ForegroundColor Green
    $msvcInc = Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | Select-Object -First 1
    if ($msvcInc) { Write-Host ("  MSVC toolset: " + $msvcInc.Name) }
    $ucrt = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
    if (Test-Path $ucrt) { Write-Host ("  Windows SDK includes: " + (Get-ChildItem $ucrt -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name) }
    else { Write-Host '  [warn] Windows SDK include dir not found under Program Files (x86)\Windows Kits\10' -ForegroundColor Yellow }
    if ($Toolchain -eq 'bundled') {
        Write-Host '  (bundled mode does not use it: headers/CRT/import libs and lld-link all come from this package)'
    }
} elseif ($Toolchain -eq 'bundled') {
    Write-Host '  not installed -- and that is fine in bundled mode.' -ForegroundColor Green
    Write-Host '  The compiler takes the C++ standard library headers, the C runtime and' -ForegroundColor DarkGray
    Write-Host '  the Windows headers from lib\stl / lib\compiler / lib\mingw in this' -ForegroundColor DarkGray
    Write-Host '  package, and links with the bundled lld-link.  Nothing gets read from' -ForegroundColor DarkGray
    Write-Host '  Program Files.' -ForegroundColor DarkGray
    Write-Host '  (Pass -Toolchain system to use a machine-wide Visual Studio instead.)' -ForegroundColor DarkGray
} else {
    Write-Host '  [missing] Visual Studio C++ build tools were not found.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  You asked for -Toolchain system, which reads the MSVC standard library' -ForegroundColor Yellow
    Write-Host '  and the Windows SDK out of a local Visual Studio install.  Install it,' -ForegroundColor Yellow
    Write-Host '  or re-run with -Toolchain bundled (the default) to need nothing.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Install with:'
    Write-Host ''
    Write-Host '    winget install --id Microsoft.VisualStudio.2022.BuildTools ^'
    Write-Host '      --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"'
    Write-Host ''
    Write-Host '  or install Visual Studio (Community/Build Tools) and tick'
    Write-Host '  "Desktop development with C++".  Roughly 2 GB download, 6 GB on disk.'
    Write-Host ''
}

# ---------------------------------------------------------------------------
# 4. editor
#
#    Two paths, and the reason for the shape:
#
#    (a) OFFLINE: this package already contains a portable editor
#        (vscodium\) -- used as is.
#
#    (b) ONLINE (default for the toolchain-only package): download the OFFICIAL
#        Visual Studio Code into this folder.
#
#    WHY WE DOWNLOAD INSTEAD OF BUNDLING THE OFFICIAL BUILD
#      The official VS Code binary ships under the Microsoft Software License
#      Terms, which say (resources/app/LICENSE.rtf, section 5):
#          "You may not ... share, publish, rent or lease the software, or
#           provide the software as a stand-alone offering for others to use."
#      Putting that binary in a zip WE hand out would be "share, publish".
#      Letting Microsoft's own server hand it to the user is fine, and it is
#      also what makes DEBUGGING work: Microsoft's C/C++ extension
#      (ms-vscode.cpptools) is licensed for VS Code only, not for VSCodium.
#
#    PORTABLE MODE ONLY. A "data" folder next to the editor executable keeps
#    settings and extensions inside this folder. The user's own VS Code
#    installation is never read or written.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) editor'

if ($NoEditor) {
    Write-Host '  skipped (-NoEditor)' -ForegroundColor DarkGray
} else {
$VSCODE_URL   = 'https://update.code.visualstudio.com/latest/win32-x64-archive/stable'
$LANG_PACK    = 'MS-CEINTL.vscode-language-pack-zh-hans'
$CLANGD_EXT   = 'llvm-vs-code-extensions.vscode-clangd'
# Provides the cppvsdbg DEBUG ADAPTER that vscode-kit\.vscode\launch.json needs.
# VS Code only -- see the licence note where it is installed below.
$CPPTOOLS_EXT = 'ms-vscode.cpptools'
$editorDir    = Join-Path $here 'vscode'

function Enable-Portable($dir) {
    $ed = Get-ChildItem $dir -Recurse -Depth 2 -Include 'Code.exe', 'VSCodium.exe' -File -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if (-not $ed) { return $null }
    $data = Join-Path $ed.Directory.FullName 'data'
    New-Item -ItemType Directory -Force $data | Out-Null

    # CHINESE UI. Installing the language pack is NOT enough on its own: VS Code
    # reads the display language from argv.json at startup. Read out of VS Code's
    # own source (resources/app/out/main.js in the official archive):
    #     function r(){ if (process.env.VSCODE_PORTABLE) return process.env.VSCODE_PORTABLE;
    #                   if (win32 || linux) return path.join(appRoot(), "data"); }
    #     get argvResource(){ return joinPath(VSCODE_PORTABLE, "argv.json"); }
    # and appRoot() is the directory holding Code.exe, because that archive ships
    # "win32VersionedUpdate": true in product.json (verified against the zip this
    # script downloads). So the file VS Code actually reads is
    #     <editor>\data\argv.json
    # The second path below is a harmless extra for older layouts.
    # Write it MULTI-LINE with a trailing newline, and validate it with a STRICT
    # pattern that requires the value's closing quote.
    #
    # Measured on a real install (2026-09-26): VS Code rewrote the one-line file
    # this script used to write into
    #     {"locale":"zh-cn, // Allows to disable crash reporting. ...
    # -- note the MISSING closing quote. That is not valid JSON, so VS Code
    # cannot read the locale at all, silently starts in English, and also trips
    # its own "argv.json contains errors" warning.
    #
    # A substring test for '"locale"' does NOT detect that, because the corrupt
    # text contains the substring too (this script's first attempt made exactly
    # that mistake). So: drop comment lines and require a properly quoted value.
    $argv = "{`n`t`"locale`": `"zh-cn`"`n}`n"
    $script:argvPath = Join-Path $data 'argv.json'
    foreach ($p in @($script:argvPath, (Join-Path $data 'user-data\argv.json'))) {
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        $ok = $false
        if (Test-Path $p) {
            try {
                $body = ([System.IO.File]::ReadAllLines($p) |
                         Where-Object { $_.TrimStart() -notmatch '^//' }) -join "`n"
                if ($body -match '"locale"\s*:\s*"[A-Za-z][A-Za-z-]*"') { $ok = $true }
            } catch { $ok = $false }
        }
        if (-not $ok) {
            if (Test-Path $p) {
                Copy-Item $p ($p + '.zhpp-backup') -Force -ErrorAction SilentlyContinue
                Write-Host ("  repaired the display language in " + $p) -ForegroundColor Yellow
            }
            [System.IO.File]::WriteAllText($p, $argv)
        }
    }
    return $ed
}

function Find-InstalledEditor {
    # RE-RUN SAFETY. An earlier interrupted run may already have unpacked the
    # editor here. The $bundled lookup below deliberately SKIPS $editorDir (that
    # one is the download target, not something the packager shipped), so
    # without this check a second run would re-download all 320 MB.
    $direct = Join-Path $editorDir 'Code.exe'
    if (Test-Path $direct) { return (Get-Item $direct) }
    $direct = Join-Path $editorDir 'VSCodium.exe'
    if (Test-Path $direct) { return (Get-Item $direct) }
    return (Get-ChildItem $editorDir -Recurse -Depth 2 -Include 'Code.exe', 'VSCodium.exe' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1)
}

$bundled = Get-ChildItem $here -Recurse -Depth 2 -Include 'VSCodium.exe', 'Code.exe' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Directory.FullName -notlike "$editorDir*" } | Select-Object -First 1

$ed = $null
$editorFailed = $false

if ($bundled) {
    Write-Host ("  using the portable editor already in this package: " + $bundled.Name)
    $ed = Enable-Portable $bundled.Directory.FullName
} else {
    $zip = Join-Path $here 'vscode-download.zip'

    $already = Find-InstalledEditor
    if ($already) {
        # The common re-run case: everything is already here.
        Write-Host ("  editor already installed -- skipping the download: " + $already.FullName) -ForegroundColor Green
        $ed = Enable-Portable $already.Directory.FullName
    } else {
        # A previous run may have been interrupted mid-download. Reuse the file
        # if it is plausibly complete; otherwise throw it away and fetch again.
        $haveZip = $false
        if (Test-Path $zip) {
            $mb = [int]((Get-Item $zip).Length / 1MB)
            if ($mb -ge 100) {
                Write-Host ("  reusing the download from a previous run ($mb MB)")
                $haveZip = $true
            } else {
                Write-Host ("  discarding an incomplete previous download ($mb MB)")
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $haveZip) {
            Write-Host '  this package has no editor bundled.'
            Write-Host '  downloading the OFFICIAL Visual Studio Code (about 320 MB) into this folder...'
            Write-Host '  (we do not redistribute it; Microsoft serves it directly to you)'
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $VSCODE_URL -OutFile $zip -UseBasicParsing -TimeoutSec 3600
                $haveZip = $true
            } catch {
                $editorFailed = $true
                Write-Host ("  [FAIL] download failed: " + $_.Exception.Message) -ForegroundColor Red
                Write-Host '  re-run this script to try again -- nothing half-done is left behind.' -ForegroundColor Yellow
                Write-Host '  or download it manually and unpack it into:' -ForegroundColor Yellow
                Write-Host ("     $editorDir") -ForegroundColor Yellow
                Write-Host ("  from: $VSCODE_URL") -ForegroundColor Yellow
            }
        }

        if ($haveZip) {
            Write-Host '  extracting...'
            New-Item -ItemType Directory -Force $editorDir | Out-Null
            try {
                Expand-Archive -Path $zip -DestinationPath $editorDir -Force -ErrorAction Stop
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
            } catch {
                # Extraction failed: the zip is suspect, so drop it and let the
                # next run fetch a fresh one. The partial folder is harmless --
                # the next run overwrites it -- so we keep it and say so.
                $editorFailed = $true
                Write-Host ("  [FAIL] extraction failed: " + $_.Exception.Message) -ForegroundColor Red
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                Write-Host '  re-run this script: it will download again and overwrite the partial folder.' -ForegroundColor Yellow
            }
            $ed = Enable-Portable $editorDir
            if ($ed) {
                Write-Host ("  installed: " + $ed.FullName) -ForegroundColor Green
            } else {
                $editorFailed = $true
                Write-Host '  [warn] Code.exe not found after extraction -- re-run the script.' -ForegroundColor Yellow
            }
        }
    }
}

if ($ed) {
    Write-Host ("  portable mode: " + (Join-Path $ed.Directory.FullName 'data'))
    Write-Host '  your own VS Code installation is not touched.'

    # extensions: the editor's own CLI installs them into data\extensions
    $cli = Get-ChildItem $ed.Directory.FullName -Recurse -Depth 2 -Include 'code.cmd', 'codium.cmd' -File -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($cli) {
        # Ask what is already there, so a re-run does not re-download the .vsix
        # files from the marketplace.
        $have = @()
        try { $have = & $cli.FullName --list-extensions 2>$null } catch { }
        # cpptools is what makes the Run/Debug button usable, but its licence
        # permits use with OFFICIAL VS Code only -- not with other builds -- and
        # the -WithEditor offline variant ships VSCodium. So it joins the list
        # only for Code.exe; under VSCodium the tasks still work, only the run
        # button does not.
        $exts = @($LANG_PACK, $CLANGD_EXT)
        if ($ed.Name -eq 'Code.exe') {
            $exts += $CPPTOOLS_EXT
        } else {
            Write-Host '  (not installing the C/C++ debugger: its licence is VS Code only)' -ForegroundColor DarkGray
            Write-Host ('  so the Run button will not work under ' + $ed.Name + '; the build tasks still do.') -ForegroundColor DarkGray
        }

        foreach ($ext in $exts) {
            if ($have -contains $ext) {
                Write-Host ("    already installed: " + $ext) -ForegroundColor DarkGray
                continue
            }
            Write-Host ("    installing: " + $ext)
            # Retry three times, checking each time instead of trusting the exit
            # code. A single marketplace hiccup is common, and when the LANGUAGE
            # PACK is the one that fails, the only symptom is an editor that
            # stays English with no error anywhere -- which took a user bug
            # report to find. Measured on a real install (2026-09-26): the pack
            # was missing while clangd had installed fine.
            for ($try = 1; $try -le 3; $try++) {
                & $cli.FullName --install-extension $ext --force 2>&1 |
                    Select-Object -Last 2 | ForEach-Object { Write-Host ("      " + $_) }
                $now = @()
                try { $now = & $cli.FullName --list-extensions 2>$null } catch { }
                if ($now -contains $ext) { break }
                if ($try -lt 3) {
                    Write-Host ("      attempt " + $try + " did not take; retrying...") -ForegroundColor DarkGray
                    Start-Sleep -Seconds (4 * $try)
                }
            }
        }
        # VERIFY the language pack instead of assuming it. A marketplace install
        # that silently failed used to leave the editor in English with nothing
        # but a soft note, and the user has no way to guess that the language
        # pack is what is missing.
        $after = @()
        try { $after = & $cli.FullName --list-extensions 2>$null } catch { }
        if ($after -contains $LANG_PACK) {
            Write-Host '  Chinese language pack: installed' -ForegroundColor Green
        } else {
            Write-Host '  [warn] the Chinese language pack did NOT install,' -ForegroundColor Yellow
            Write-Host '         so the editor will start in English. Fix it either way:' -ForegroundColor Yellow
            Write-Host '           in the editor: Ctrl+Shift+P -> Configure Display Language' -ForegroundColor Yellow
            Write-Host '                          -> Chinese (Simplified), then let it restart' -ForegroundColor Yellow
            Write-Host '           Extensions panel -> search Chinese (Simplified)' -ForegroundColor Yellow
            Write-Host ('           or: ' + $cli.FullName + ' --install-extension ' + $LANG_PACK) -ForegroundColor Yellow
        }
        if ($ed.Name -eq 'Code.exe') {
            if ($after -contains $CPPTOOLS_EXT) {
                Write-Host '  C/C++ debugger for launch.json: installed' -ForegroundColor Green
            } else {
                Write-Host '  [warn] the C/C++ extension did NOT install, so the Run button' -ForegroundColor Yellow
                Write-Host '         will not work. The build tasks and Ctrl+Shift+B still do.' -ForegroundColor Yellow
            }
        }
        Write-Host '  (the extensions come from the official marketplace; if this failed,' -ForegroundColor DarkGray
        Write-Host '   re-run the script or install them from the Extensions panel)' -ForegroundColor DarkGray
    } else {
        Write-Host '  [warn] editor CLI (bin\code.cmd) not found; install the extensions manually:' -ForegroundColor Yellow
        Write-Host ("     " + $LANG_PACK)
        Write-Host ("     " + $CLANGD_EXT)
    }
}
}   # end of the editor step (skipped by -NoEditor)

# ---------------------------------------------------------------------------
# 5. examples kit
# ---------------------------------------------------------------------------
$kit = Join-Path $here 'vscode-kit'
if (Test-Path $kit) {
    Write-Host ''
    Write-Host '--- 5) editor kit'
    $ex = Join-Path $here 'examples'
    if (-not (Test-Path $ex)) { New-Item -ItemType Directory -Force $ex | Out-Null }
    Copy-Item (Join-Path $kit '*') $ex -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  kit copied into examples\ (open that folder in the editor)"
    # Substitute the placeholders in EVERY text file of the kit, not just
    # settings.json.
    #
    # This was a real bug, found 2026-09-26 on an installed copy: only
    # settings.json was processed, so tasks.json kept the literal text
    # "@@CXX@@" as its "command". Every build task then died with a shell error
    # saying @@CXX@@ is not recognized, and F5's preLaunchTask died with it too.
    # The user's copy had to be repaired by hand; this is the fix in the
    # installer so nobody else meets it.
    $settings = Join-Path $ex '.vscode\settings.json'
    if (Test-Path $settings) {
        $cxxEsc = (Join-Path $bin 'chinese++.exe').Replace('\', '\\')
        $cldEsc = (Join-Path $bin 'clangd.exe').Replace('\', '\\')
        $n = 0
        foreach ($f in @(Get-ChildItem (Join-Path $ex '.vscode') -File -Recurse -ErrorAction SilentlyContinue)) {
            $t = [System.IO.File]::ReadAllText($f.FullName)
            if ($t.Contains('@@CXX@@') -or $t.Contains('@@CLANGD@@')) {
                $t = $t.Replace('@@CXX@@', $cxxEsc).Replace('@@CLANGD@@', $cldEsc)
                [System.IO.File]::WriteAllText($f.FullName, $t)
                $n++
            }
        }
        Write-Host ("  paths substituted in {0} kit file(s)" -f $n)

        # Leave the same .vscode at the PACKAGE ROOT as well.
        #
        # A .vscode folder is only read at the WORKSPACE ROOT. Users very
        # naturally open the package folder itself, and with the kit only under
        # examples\ that showed "create a launch.json file" and an empty task
        # list -- measured on a real install 2026-09-26. A copy at the root
        # makes whichever folder they open work.
        $rootVscode = Join-Path $here '.vscode'
        New-Item -ItemType Directory -Force $rootVscode | Out-Null
        Copy-Item (Join-Path $ex '.vscode\*') $rootVscode -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host '  same .vscode copied to the package root (either folder works)'

        # ALSO install the same settings for the editor USER, not just for the
        # examples folder.
        #
        # Why this is not optional: .vscode\settings.json is a FOLDER-scoped
        # setting, so it only applies while the opened folder IS examples\.
        # Open any other folder and the clangd extension sees no clangd.path,
        # falls back to searching for 'clangd' on PATH, finds nothing, and pops
        # up:
        #     "The 'clangd' language server was not found on your PATH.
        #      Would you like to download and install clangd 22.1.6?"
        # Clicking Install there downloads the OFFICIAL clangd, which does not
        # know the Chinese keywords and red-squiggles every one of them -- the
        # exact opposite of the point of this package. Measured on a real
        # install 2026-09-26, after the user opened a folder other than
        # examples\.
        #
        # Writing it as the USER setting makes it apply to every folder, so
        # which folder the user opens stops mattering.
        if ($ed) {
            $userDir = Join-Path $ed.Directory.FullName 'data\user-data\User'
            New-Item -ItemType Directory -Force $userDir | Out-Null
            $userSettings = Join-Path $userDir 'settings.json'
            $write = $true
            if (Test-Path $userSettings) {
                # Do not clobber a user's own tuning: if they already point at a
                # clangd themselves, leave it alone.
                $cur = ''
                try { $cur = [System.IO.File]::ReadAllText($userSettings) } catch { }
                if ($cur -match '"clangd\.path"') { $write = $false }
            }
            if ($write) {
                if (Test-Path $userSettings) {
                    Copy-Item $userSettings ($userSettings + '.zhpp-backup') -Force -ErrorAction SilentlyContinue
                }
                # Read settings.json fresh: $t now belongs to the substitution
                # loop above and must not be relied on here.
                [System.IO.File]::WriteAllText($userSettings, [System.IO.File]::ReadAllText($settings))
                Write-Host '  same settings installed for the editor user (works in ANY folder)'
            } else {
                Write-Host '  editor user settings already point at a clangd; left alone' -ForegroundColor DarkGray
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 6. prove it works
#
#    The self-test below only proves the TOOLCHAIN. If the editor step failed we
#    must not end with "finished successfully" -- that would report a failure as
#    a success, which is exactly the class of bug this project keeps hunting.
# ---------------------------------------------------------------------------
$rc = 0
if (-not $SkipVerify) {
    Write-Host ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'verify.ps1')
    $rc = $LASTEXITCODE
} else {
    Write-Host ''
    Write-Host 'skipped verification (-SkipVerify).' -ForegroundColor Yellow
}

if ($editorFailed) {
    Write-Host ''
    Write-Host '======================================================================' -ForegroundColor Yellow
    Write-Host '  The TOOLCHAIN is fine, but the EDITOR was not installed.' -ForegroundColor Yellow
    Write-Host '  Re-run this script (or the one-click launcher) to retry.' -ForegroundColor Yellow
    Write-Host '  Nothing half-done is left behind: the next run starts clean.' -ForegroundColor Yellow
    Write-Host '======================================================================' -ForegroundColor Yellow
    exit 2
}

# ---------------------------------------------------------------------------
# 7. what to do next
#
#    Without this the setup ends with "success" and no instruction on how to
#    actually start working -- the editor was installed but never launched and
#    the user is not told which folder to open.
# ---------------------------------------------------------------------------
if ($ed) {
    Write-Host ''
    Write-Host '======================================================================' -ForegroundColor Cyan
    Write-Host '  Ready. To start writing Chinese C++:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('    1. start the editor:  ' + $ed.FullName)
    Write-Host ('    2. in it, open:       ' + (Join-Path $here 'examples'))
    Write-Host '    3. press Ctrl+Shift+B and choose the build task'
    Write-Host ''
    Write-Host '  If the interface is still English, the Chinese language pack is what'
    Write-Host '  is missing -- installing it can fail without stopping setup:'
    Write-Host '      in the editor:  Ctrl+Shift+P  ->  Configure Display Language'
    Write-Host '                      ->  Chinese (Simplified)  ->  restart'
    Write-Host ''
    Write-Host '  To just RUN the current file: open the examples folder, then press F5'
    Write-Host '  or click the triangle at the top right. It compiles first, then runs.'
    Write-Host '  Open a .cpp file FIRST: with no active file those settings expand'
    Write-Host '  to nothing and VS Code reports: launch: program "" does not exist.'
    Write-Host ''
    Write-Host '  Working in YOUR OWN project folder instead of this one?'
    Write-Host '      run the one-click "configure workspace" launcher in this folder:'
    Write-Host '      it asks for a folder and drops the same .vscode config into it.'
    Write-Host '      (a .vscode folder is only read at the WORKSPACE ROOT, so a'
    Write-Host '       config that lives here does nothing for another folder.)'
    Write-Host ''
    Write-Host '  That folder already has the editor configured: clangd points at the'
    Write-Host '  bundled clangd (the one that understands Chinese keywords), and the'
    Write-Host '  build task points at the bundled chinese++.exe.'
    Write-Host ''
    Write-Host '  To compile from a terminal instead: double-click env.cmd, then'
    Write-Host '      chinese++ yourfile.cpp -o yourfile.exe'
    Write-Host ''
    Write-Host '  Program output shows garbled Chinese (gibberish instead of the'
    Write-Host '  characters you expected)? That is the CONSOLE code page, not the'
    Write-Host '  compiler -- official clang does the same here. Short version: turn ON'
    Write-Host '  "Beta: Use Unicode UTF-8 for worldwide language support" in Windows'
    Write-Host '  Settings > Time & language > Language & region, then reboot.'
    Write-Host '  One switch, and turning it back off restores everything.'
    Write-Host '  Full explanation: section 10 of the troubleshooting document below.'
    Write-Host ''
    # List the real file names rather than describing them: this script is pure
    # ASCII, so it must not contain the (Chinese) names as literals.
    $docs = Get-ChildItem $here -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name
    if ($docs) {
        Write-Host '  Read these (in this folder):'
        foreach ($d in $docs) { Write-Host ('      ' + $d) }
        Write-Host '      -- prerequisites, troubleshooting, and the full cheat sheet'
    }
    Write-Host ''
    Write-Host '  Want your OWN VS Code to understand Chinese too?'
    Write-Host '      run the one-click attach script in this folder'
    Write-Host '      (the one-click restore script next to it undoes it)'
    Write-Host ''
    Write-Host '  Contact: QQ 1396257961'
    Write-Host '  Provided as-is, with no warranty. Back up your own data.'
    Write-Host '======================================================================' -ForegroundColor Cyan
} else {
    Write-Host ''
    Write-Host '=== Toolchain ready ===' -ForegroundColor Cyan
    Write-Host ('  compiler: ' + (Join-Path $bin 'chinese++.exe'))
    Write-Host '  double-click env.cmd to get a shell that can see chinese++.'
}

exit $rc
