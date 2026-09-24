# ============================================================================
#  detach-from-vscode.ps1
#
#  WHAT THIS DOES  (run it via the one-click .cmd next to it)
#    Puts YOUR OWN VS Code back exactly as it was before the attach script ran:
#      1. restores settings.json from the backup made at attach time
#      2. or, if you had no settings.json at all, removes the one we created
#
#  WHAT IT DOES *NOT* DO
#    * it does not uninstall the clangd extension (you may want to keep it).
#      Remove it by hand from the Extensions panel if you do not.
#    * it does not touch the portable editor inside this folder
#    * it does not touch anything else
#
#  ENCODING: THIS FILE IS PURE ASCII (see the note in attach-to-vscode.ps1).
# ============================================================================

$ErrorActionPreference = 'Continue'

$userDir  = Join-Path $env:APPDATA 'Code\User'
$settings = Join-Path $userDir 'settings.json'
$backup   = $settings + '.zhpp-backup'

Write-Host ''
Write-Host '=== Chinese++ : restore YOUR OWN VS Code ==='
Write-Host ''

if (-not (Test-Path $backup)) {
    Write-Host '  Nothing to restore: no backup found at' -ForegroundColor Yellow
    Write-Host ("     " + $backup) -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  That means the attach script was never run (or you already restored).'
    Write-Host '  Your settings.json has not been touched by us.'
    Write-Host ''
    exit 0
}

$marker = '__CHINESE_PLUS_PLUS_NO_SETTINGS_EXISTED__'
$content = ''
try { $content = [System.IO.File]::ReadAllText($backup) } catch { }

if ($content.Trim() -eq $marker) {
    # You had no settings.json before; remove the one we created.
    if (Test-Path $settings) {
        Remove-Item $settings -Force
        Write-Host '  removed the settings.json that we created (you had none before)' -ForegroundColor Green
    } else {
        Write-Host '  settings.json was already gone'
    }
} else {
    Copy-Item $backup $settings -Force
    Write-Host ("  restored your settings.json from " + $backup) -ForegroundColor Green
}

Remove-Item $backup -Force -ErrorAction SilentlyContinue
Write-Host '  backup file removed'
Write-Host ''
Write-Host '  Done. Restart VS Code.' -ForegroundColor Green
Write-Host '  Note: the clangd extension is left installed on purpose --' -ForegroundColor DarkGray
Write-Host '  remove it from the Extensions panel if you do not want it.' -ForegroundColor DarkGray
Write-Host ''
exit 0
