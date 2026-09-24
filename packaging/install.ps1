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
# 4. bundled portable editor (optional)
#
#    PORTABLE ONLY. The user's own VS Code is never touched: this package
#    always uses the editor inside its own folder, so behaviour is predictable
#    and nothing outside this folder changes.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) bundled portable editor'
$editor = Get-ChildItem $here -Recurse -Depth 2 -Include 'VSCodium.exe', 'Code.exe' -File -ErrorAction SilentlyContinue |
          Select-Object -First 1
if ($editor) {
    $edir = $editor.Directory.FullName
    $data = Join-Path $edir 'data'
    if (-not (Test-Path $data)) { New-Item -ItemType Directory -Force $data | Out-Null }
    Write-Host ("  portable mode enabled: " + $data) -ForegroundColor Green
    Write-Host ("  editor: " + $editor.Name)
    Write-Host '  your own VS Code installation is not touched.'
} else {
    Write-Host '  no bundled editor in this package (toolchain-only build).' -ForegroundColor DarkGray
    Write-Host '  the kit in vscode-kit\ works with any VS Code compatible editor.'
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
