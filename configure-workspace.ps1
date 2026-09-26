# ============================================================================
#  configure-workspace.ps1 -- put this package's editor config into YOUR folder.
#
#  WHY THIS EXISTS
#    A .vscode\ folder is only read at the WORKSPACE ROOT. Baking the config into
#    the package root works only if you happen to open the package root.
#    Measured 2026-09-26: the user's workspace was the folder ONE LEVEL ABOVE the
#    package root (both folders had the same name), so the config sat one level
#    down, invisible -- "create a launch.json file" and an empty task list.
#    So do not guess: DETECT, and if detection fails, ask.
#
#  HOW IT FINDS YOUR WORKSPACE
#    VS Code records the folders it has opened, and both records are readable:
#      <user-data>\User\workspaceStorage\<hash>\workspace.json
#          {"folder":"file:///e%3A/Chinese%2B%2B-0.1-win64"}
#      <user-data>\User\globalStorage\storage.json
#          backupWorkspaces.folders[].folderUri
#    Verified against a real install 2026-09-26. It is not a public API, so a
#    miss simply falls back to a folder picker.
#
#  WHAT IT WRITES  (into <your folder>\.vscode\)
#    settings.json   clangd.path -> this package's clangd, UTF-8, exclusions
#    tasks.json      the three build tasks, command -> this package's chinese++
#    launch.json     the F5 / triangle debug config (cppvsdbg)
#    Any file it replaces is first copied to <name>.zhpp-backup.
#
#  USAGE
#    double-click the one-click launcher next to this script
#    powershell -File configure-workspace.ps1 -List          show what it detects
#    powershell -File configure-workspace.ps1                detect, then pick
#    powershell -File configure-workspace.ps1 -Workspace D:\proj\src
#
#  ENCODING: PURE ASCII on purpose (PowerShell 5.1 reads BOM-less files as GBK).
# ============================================================================

param(
    [string] $Workspace,
    [switch] $List
)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$kit  = Join-Path $here 'vscode-kit\.vscode'
$bin  = Join-Path $here 'bin'

if (-not (Test-Path $kit)) {
    throw "no editor kit at $kit -- is this script still inside the package?"
}
$cxx = Join-Path $bin 'chinese++.exe'
$cld = Join-Path $bin 'clangd.exe'
if (-not (Test-Path $cxx)) { throw "no compiler at $cxx" }
if (-not (Test-Path $cld)) { throw "no clangd at $cld" }

# ---------------------------------------------------------------------------
# detection helpers
# ---------------------------------------------------------------------------
function ConvertFrom-FolderUri([string] $uri) {
    if (-not $uri) { return $null }
    $s = $uri -replace '^file:///', ''
    try { $s = [System.Uri]::UnescapeDataString($s) } catch { }
    return ($s -replace '/', '\')
}

function Get-LastWorkspace {
    # The bundled portable editor first, then the user's own installations.
    $candidates = @(
        (Join-Path $here 'vscode\data\user-data\User'),
        (Join-Path $here 'vscode\data\user-data\User'),
        (Join-Path $env:APPDATA 'Code\User'),
        (Join-Path $env:APPDATA 'VSCodium\User')
    )
    $items = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($u in $candidates) {
        if (-not $u -or -not (Test-Path $u)) { continue }

        # Most recently written workspaceStorage entry = most recently used folder.
        $ws = Join-Path $u 'workspaceStorage'
        if (Test-Path $ws) {
            $dirs = @(Get-ChildItem $ws -Directory -ErrorAction SilentlyContinue)
            foreach ($d in $dirs) {
                $wj = Join-Path $d.FullName 'workspace.json'
                if (-not (Test-Path $wj)) { continue }
                $o = $null
                try { $o = Get-Content $wj -Raw | ConvertFrom-Json } catch { continue }
                $p = ConvertFrom-FolderUri $o.folder
                if ($p -and (Test-Path $p) -and -not $seen.ContainsKey($p)) {
                    $seen[$p] = $true
                    [void]$items.Add([pscustomobject]@{ Path = $p; When = $d.LastWriteTime })
                }
            }
        }

        $sj = Join-Path $u 'globalStorage\storage.json'
        if (Test-Path $sj) {
            $o = $null
            try { $o = Get-Content $sj -Raw | ConvertFrom-Json } catch { $o = $null }
            if ($o -and $o.backupWorkspaces -and $o.backupWorkspaces.folders) {
                foreach ($f in $o.backupWorkspaces.folders) {
                    $p = ConvertFrom-FolderUri $f.folderUri
                    if ($p -and (Test-Path $p) -and -not $seen.ContainsKey($p)) {
                        $seen[$p] = $true
                        [void]$items.Add([pscustomobject]@{ Path = $p; When = (Get-Item $sj).LastWriteTime })
                    }
                }
            }
        }
    }
    # ONE global order, newest first. The first version sorted only within each
    # source and then concatenated, so the printed "most recent first" claim was
    # not actually true once the bundled editor and the user's own installations
    # were merged.
    return @($items | Sort-Object When -Descending | ForEach-Object { $_.Path })
}

if ($List) {
    $d = @(Get-LastWorkspace)
    if ($d.Count -eq 0) { Write-Host 'no recorded VS Code workspace found'; exit 1 }
    $d | ForEach-Object { Write-Host $_ }
    exit 0
}

Write-Host ''
Write-Host '=== configure a VS Code workspace for Chinese++ ===' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. which folder?  detect first, ask only if that fails
# ---------------------------------------------------------------------------
$detected = @(Get-LastWorkspace)

if (-not $Workspace) {
    if ($detected.Count -gt 0) {
        Write-Host ''
        Write-Host '  VS Code has these folders on record (most recent first):' -ForegroundColor Cyan
        for ($i = 0; $i -lt $detected.Count; $i++) {
            Write-Host ("    [{0}] {1}" -f ($i + 1), $detected[$i])
        }
        Write-Host ''
        $pick = Read-Host "  Use which one?  Enter = 1,  p = pick another folder"
        if ($pick -eq 'p' -or $pick -eq 'P') {
            $Workspace = $null
        } elseif ([string]::IsNullOrWhiteSpace($pick)) {
            $Workspace = $detected[0]
        } else {
            $n = 0
            if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $detected.Count) {
                $Workspace = $detected[$n - 1]
            } else {
                $Workspace = $pick          # a pasted path is accepted here too
            }
        }
    }

    if (-not $Workspace) {
        Write-Host 'Pick the folder you OPEN in VS Code (the workspace root).'
        try {
            Add-Type -AssemblyName System.Windows.Forms | Out-Null
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'Pick the folder you open in VS Code (workspace root)'
            $dlg.ShowNewFolderButton = $true
            if ($detected.Count -gt 0) { $dlg.SelectedPath = $detected[0] }
            $res = $dlg.ShowDialog()
            if ($res -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Host 'cancelled -- nothing was changed.' -ForegroundColor Yellow
                exit 0
            }
            $Workspace = $dlg.SelectedPath
        } catch {
            Write-Host '  (no folder dialog available; type the path instead)' -ForegroundColor DarkGray
            $Workspace = Read-Host 'Path of the workspace folder'
        }
    }
}

if (-not $Workspace) { Write-Host 'no folder given -- nothing done.' -ForegroundColor Yellow; exit 1 }
if (-not (Test-Path $Workspace)) {
    Write-Host ("that folder does not exist: " + $Workspace) -ForegroundColor Red
    exit 1
}
$Workspace = (Resolve-Path $Workspace).Path
Write-Host ("  workspace: " + $Workspace)

# ---------------------------------------------------------------------------
# 2. write .vscode\  with this package's real paths substituted in
# ---------------------------------------------------------------------------
$dst = Join-Path $Workspace '.vscode'
New-Item -ItemType Directory -Force $dst | Out-Null

# JSON needs the backslashes doubled, exactly as the kit's placeholders expect.
$cxxEsc = $cxx.Replace('\', '\\')
$cldEsc = $cld.Replace('\', '\\')

$written = @()
foreach ($f in @(Get-ChildItem $kit -File -Recurse)) {
    $target = Join-Path $dst $f.Name
    if (Test-Path $target) {
        Copy-Item $target ($target + '.zhpp-backup') -Force -ErrorAction SilentlyContinue
        Write-Host ("  backed up existing " + $f.Name + " -> " + $f.Name + ".zhpp-backup") -ForegroundColor DarkGray
    }
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $t = $t.Replace('@@CXX@@', $cxxEsc).Replace('@@CLANGD@@', $cldEsc)
    if ($t.Contains('@@')) {
        # Never write a file that still holds a placeholder: a task whose command
        # is literally "@@CXX@@" fails at run time with a confusing shell error.
        throw ("placeholder left in " + $f.Name + " -- the kit is malformed")
    }
    [System.IO.File]::WriteAllText($target, $t)
    $written += $f.Name
}

Write-Host ''
Write-Host ("  wrote into " + $dst + ":") -ForegroundColor Green
foreach ($w in $written) { Write-Host ("      " + $w) }

# An older copy of this package ships a kit WITHOUT launch.json, and then F5 and
# the debug triangle have no configuration at all. Say so rather than leaving a
# silent gap -- measured on a real 2026-09-25 package, where only two files were
# written and nothing indicated the third was missing.
foreach ($need in @('settings.json', 'tasks.json', 'launch.json')) {
    if ($written -notcontains $need) {
        Write-Host ("  [warn] the kit in this copy has no " + $need + ".") -ForegroundColor Yellow
        Write-Host '         This package copy predates that file, so that part of' -ForegroundColor Yellow
        Write-Host '         the editor setup will be missing.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 3. say what to do next
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Next, in VS Code:'
Write-Host '  1. open this folder as the workspace (File > Open Folder)'
Write-Host '  2. open a .cpp file -- some actions need an active file'
Write-Host '  3. Ctrl+Shift+B  build      F5  build + run + debug'
Write-Host '     or Ctrl+Shift+P > Tasks: Run Task > the build-and-run task'
Write-Host ''
Write-Host "clangd needs no PATH: settings.json points it straight at this"
Write-Host "package's clangd, so the window can be opened from anywhere."
Write-Host ''
Write-Host 'NOTE: the written files contain ABSOLUTE paths into this package.'
Write-Host '      If you move or rename the package, run this script again.'
Write-Host ''
