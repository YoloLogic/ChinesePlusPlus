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
    [switch] $SkipVerify
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
    'echo.',
    'echo   chinese++ is ready in this window.',
    'echo   try:  chinese++ --version',
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
# 3. Visual Studio Build Tools
#
#    The toolchain needs the MSVC STL headers, the Windows SDK and link.exe.
#    None of them are in this package (see NOTICE.txt section 4).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) Visual Studio Build Tools'

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
} else {
    Write-Host '  [missing] Visual Studio C++ build tools were not found.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  This toolchain uses the MSVC standard library and the Windows SDK,' -ForegroundColor Yellow
    Write-Host '  which are NOT bundled. Install them with either:' -ForegroundColor Yellow
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

$VSCODE_URL   = 'https://update.code.visualstudio.com/latest/win32-x64-archive/stable'
$LANG_PACK    = 'MS-CEINTL.vscode-language-pack-zh-hans'
$CLANGD_EXT   = 'llvm-vs-code-extensions.vscode-clangd'
$editorDir    = Join-Path $here 'vscode'

function Enable-Portable($dir) {
    $ed = Get-ChildItem $dir -Recurse -Depth 2 -Include 'Code.exe', 'VSCodium.exe' -File -ErrorAction SilentlyContinue |
          Select-Object -First 1
    if (-not $ed) { return $null }
    $data = Join-Path $ed.Directory.FullName 'data'
    New-Item -ItemType Directory -Force $data | Out-Null
    # Chinese UI: the language pack extension plus this locale hint.
    $argv = '{"locale":"zh-cn"}'
    foreach ($p in @((Join-Path $data 'argv.json'),
                     (Join-Path $data 'user-data\argv.json'))) {
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        if (-not (Test-Path $p)) { [System.IO.File]::WriteAllText($p, $argv) }
    }
    return $ed
}

$bundled = Get-ChildItem $here -Recurse -Depth 2 -Include 'VSCodium.exe', 'Code.exe' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Directory.FullName -notlike "$editorDir*" } | Select-Object -First 1

if ($bundled) {
    Write-Host ("  using the portable editor already in this package: " + $bundled.Name)
    $ed = Enable-Portable $bundled.Directory.FullName
} else {
    Write-Host '  this package has no editor bundled.'
    Write-Host '  downloading the OFFICIAL Visual Studio Code (about 320 MB) into this folder...'
    Write-Host '  (we do not redistribute it; Microsoft serves it directly to you)'
    $zip = Join-Path $here 'vscode-download.zip'
    $ok = $false
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $VSCODE_URL -OutFile $zip -UseBasicParsing -TimeoutSec 3600
        $ok = $true
    } catch {
        Write-Host ("  [FAIL] download failed: " + $_.Exception.Message) -ForegroundColor Red
        Write-Host '  you can download it manually and unpack it into: ' -ForegroundColor Yellow
        Write-Host ("     $editorDir") -ForegroundColor Yellow
        Write-Host ("  from: $VSCODE_URL") -ForegroundColor Yellow
    }
    if ($ok) {
        Write-Host '  extracting...'
        New-Item -ItemType Directory -Force $editorDir | Out-Null
        Expand-Archive -Path $zip -DestinationPath $editorDir -Force
        Remove-Item $zip -Force
        $ed = Enable-Portable $editorDir
        if ($ed) { Write-Host ("  installed: " + $ed.FullName) -ForegroundColor Green }
        else     { Write-Host '  [warn] Code.exe not found after extraction' -ForegroundColor Yellow }
    }
}

if ($ed) {
    Write-Host ("  portable mode: " + (Join-Path $ed.Directory.FullName 'data'))
    Write-Host '  your own VS Code installation is not touched.'

    # extensions: the editor's own CLI installs them into data\extensions
    $cli = Get-ChildItem $ed.Directory.FullName -Recurse -Depth 2 -Include 'code.cmd', 'codium.cmd' -File -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($cli) {
        Write-Host '  installing extensions into the portable data folder:'
        foreach ($ext in @($LANG_PACK, $CLANGD_EXT)) {
            Write-Host ("    " + $ext)
            & $cli.FullName --install-extension $ext --force 2>&1 |
                Select-Object -Last 2 | ForEach-Object { Write-Host ("      " + $_) }
        }
        Write-Host '  (requires network access to the extension marketplace; if this' -ForegroundColor DarkGray
        Write-Host '   failed, install them later from the Extensions panel)' -ForegroundColor DarkGray
    } else {
        Write-Host '  [warn] editor CLI (bin\code.cmd) not found; install the extensions manually:' -ForegroundColor Yellow
        Write-Host ("     " + $LANG_PACK)
        Write-Host ("     " + $CLANGD_EXT)
    }
}

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
    # substitute the placeholders with this package's real paths
    $settings = Join-Path $ex '.vscode\settings.json'
    if (Test-Path $settings) {
        $t = [System.IO.File]::ReadAllText($settings)
        $t = $t.Replace('@@CLANGD@@', (Join-Path $bin 'clangd.exe').Replace('\', '\\'))
        $t = $t.Replace('@@CXX@@',    (Join-Path $bin 'chinese++.exe').Replace('\', '\\'))
        [System.IO.File]::WriteAllText($settings, $t)
        Write-Host '  paths substituted into .vscode\settings.json'
    }
}

# ---------------------------------------------------------------------------
# 6. prove it works
# ---------------------------------------------------------------------------
if (-not $SkipVerify) {
    Write-Host ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'verify.ps1')
    exit $LASTEXITCODE
}
Write-Host ''
Write-Host 'skipped verification (-SkipVerify).' -ForegroundColor Yellow
