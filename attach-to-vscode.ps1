# ============================================================================
#  attach-to-vscode.ps1
#
#  WHAT THIS DOES  (run it via the one-click .cmd next to it)
#    Makes YOUR OWN VS Code (the one you normally use) understand Chinese++:
#      1. backs up your user settings.json  -> settings.json.zhpp-backup
#      2. adds two keys to it: clangd.path and clangd.arguments
#         (clangd.path must point at OUR clangd -- the stock one does not know
#          Chinese keywords, so every Chinese spelling would be marked red)
#      3. installs the clangd extension if it is not there yet
#
#  WHAT IT DOES *NOT* DO
#    * it does not touch the portable editor inside this folder
#    * it does not delete or rewrite anything else in your settings
#    * it does not uninstall anything
#
#  TO UNDO: run the one-click restore script next to this file. It puts your
#  settings.json back exactly as it was, from the backup made here.
#
#  ENCODING: THIS FILE IS PURE ASCII.  PowerShell 5.1 reads BOM-less files as
#  GBK, so non-ASCII in *code* (paths, literals) breaks the parser. The Chinese
#  explanations live in the .md documents in the package root.
# ============================================================================

param([switch] $Force)

$ErrorActionPreference = 'Continue'

$here = $PSScriptRoot
$bin  = Join-Path $here 'bin'
$cxx  = Join-Path $bin 'chinese++.exe'
$clangd = Join-Path $bin 'clangd.exe'

Write-Host ''
Write-Host '=== Chinese++ : attach to YOUR OWN VS Code ==='
Write-Host ''

if (-not (Test-Path $clangd)) {
    Write-Host ("  [FAIL] not found: " + $clangd) -ForegroundColor Red
    Write-Host '  run the one-click setup in this folder first.' -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
# 1. locate the user's settings.json
#    %APPDATA%\Code\User\settings.json is where stable VS Code keeps it.
#    VSCodium uses %APPDATA%\VSCodium\User\. We only handle VS Code here.
# ---------------------------------------------------------------------------
$userDir = Join-Path $env:APPDATA 'Code\User'
$settings = Join-Path $userDir 'settings.json'

if (-not (Test-Path $userDir)) {
    Write-Host '  [FAIL] no VS Code user folder found at:' -ForegroundColor Red
    Write-Host ("     " + $userDir) -ForegroundColor Red
    Write-Host '  (this script targets the standard VS Code install)' -ForegroundColor Yellow
    exit 1
}
Write-Host ("  your settings: " + $settings)

$backup = $settings + '.zhpp-backup'

if ((Test-Path $backup) -and -not $Force) {
    Write-Host ''
    Write-Host '  This looks like it has ALREADY been attached:' -ForegroundColor Yellow
    Write-Host ("     backup exists: " + $backup) -ForegroundColor Yellow
    Write-Host '  Run the one-click RESTORE script first if you want to start over.' -ForegroundColor Yellow
    Write-Host '  (or re-run this script; it will refresh the settings)' -ForegroundColor Yellow
} else {
    # 2. back up FIRST -- restore depends on this file
    if (Test-Path $settings) {
        Copy-Item $settings $backup -Force
        Write-Host ("  backed up -> " + $backup) -ForegroundColor Green
    } else {
        # no settings yet: create the folder, and remember that there was none
        New-Item -ItemType Directory -Force $userDir | Out-Null
        Set-Content -Path $backup -Value '__CHINESE_PLUS_PLUS_NO_SETTINGS_EXISTED__' -Encoding UTF8
        Write-Host '  (you had no settings.json; a marker was written so restore can remove it again)'
    }
}

# ---------------------------------------------------------------------------
# 3. merge our two keys in
#
#    settings.json is JSONC -- it may contain // comments. ConvertFrom-Json
#    would drop them, so we do a minimal TEXT edit instead: insert our key
#    block right after the opening brace. Everything else is left untouched.
# ---------------------------------------------------------------------------
$clangdEsc = $clangd.Replace('\', '\\')
$cxxEsc    = $cxx.Replace('\', '\\')
$block = @"
  // ---- added by Chinese++ (restore removes exactly this) ----
  "clangd.path": "$clangdEsc",
  "clangd.arguments": [
    "--background-index",
    "--header-insertion=iwyu",
    "--completion-style=detailed",
    "--pch-storage=memory",
    "--fallback-style=LLVM",
    "--query-driver=$cxxEsc"
  ]
  // ---- end of Chinese++ block ----
"@
# NOTE the block does NOT end with a comma: the insertion below supplies the
# separating comma. Ending with one produced ",," and made settings.json invalid
# JSON -- caught by validating the result with a strict parser on 2026-09-25.

$text = ''
if (Test-Path $settings) { $text = [System.IO.File]::ReadAllText($settings) }

if ($text -match 'added by Chinese\+\+') {
    Write-Host '  our block is already in settings.json; refreshing it'
    # strip the old block, then insert the new one
    $text = [regex]::Replace($text,
        '(?s)\s*// ---- added by Chinese\+\+.*?// ---- end of Chinese\+\+ block ----',
        '')
}

# ALSO drop any pre-existing clangd.path / clangd.arguments.
#
# Without this we would insert a SECOND "clangd.path" and the file would end up
# with a duplicate key -- VS Code would silently use whichever one wins.
# Found in testing on 2026-09-25: the test machine already had a clangd.path
# left over from earlier work.
#
# We may take over these two keys because the whole original file was backed up
# a few lines above, and the restore script puts it back byte for byte.
$beforeText = $text
$text = [regex]::Replace($text, '"clangd\.arguments"\s*:\s*\[[^\]]*\]\s*,?', '')
$text = [regex]::Replace($text, '"clangd\.path"\s*:\s*"[^"]*"\s*,?', '')
$text = [regex]::Replace($text, ',\s*(\r?\n\s*)\}', '$1}')
if ($text -ne $beforeText) {
    Write-Host '  removed the previous clangd.path / clangd.arguments entries'
    Write-Host '  (the original file is in the backup; the restore script brings them back)'
}

$open = $text.IndexOf('{')
if ($open -lt 0) {
    # no object at all -> write a fresh one
    $new = "{`r`n$block`r`n}`r`n"
} else {
    $head = $text.Substring(0, $open + 1)
    $tail = $text.Substring($open + 1)
    $tailTrim = $tail.TrimStart()
    if ($tailTrim.StartsWith('}')) {
        # empty object: { }  ->  { our block }
        $new = "$head`r`n$block`r`n$($tail.Substring($tail.Length - $tailTrim.Length))"
    } else {
        $new = "$head`r`n$block`r`n,$tail"
    }
}
[System.IO.File]::WriteAllText($settings, $new)
Write-Host '  wrote clangd.path / clangd.arguments into your settings' -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. clangd extension
# ---------------------------------------------------------------------------
Write-Host ''
$codeCmd = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
if (-not (Test-Path $codeCmd)) { $codeCmd = 'code' }
$have = @()
try { $have = & $codeCmd --list-extensions 2>$null } catch { }
if ($have -contains 'llvm-vs-code-extensions.vscode-clangd') {
    Write-Host '  clangd extension: already installed in your VS Code'
} else {
    Write-Host '  installing the clangd extension into your VS Code...'
    & $codeCmd --install-extension llvm-vs-code-extensions.vscode-clangd --force 2>&1 |
        Select-Object -Last 2 | ForEach-Object { Write-Host ("    " + $_) }
}

Write-Host ''
Write-Host '  Done. Restart VS Code, then open any .cpp file.' -ForegroundColor Green
Write-Host '  To undo everything: run the one-click RESTORE script in this folder.' -ForegroundColor Green
Write-Host ''
exit 0
