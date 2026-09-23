# ============================================================================
#  Rebuild clang.exe and clangd.exe after changing the Chinese keyword tables.
#
#  Usage (close anything holding clangd.exe first, e.g. an IDE):
#      powershell -File E:\Chinese++\tools\rebuild_clang.ps1
#
#  WHY THESE FLAGS
#    MSBuild defaults to one project per CPU (32 here), and every project also
#    sets <MultiProcessorCompilation>true</MultiProcessorCompilation> (/MP), so
#    the number of concurrent compilers is multiplicative and blows the 36 GB
#    commit limit (observed: CL.exe 0xc00000fd in c1xx.dll, MSBuild
#    OutOfMemoryException). So we bound the product instead of killing it:
#      /p:CL_MPCount=3   at most 3 c1xx per project (this is what actually
#                        speeds a wide rebuild up -- MSBuild builds libraries
#                        in dependency order, so /m alone buys almost nothing)
#      /m:2              at most 2 projects, so at most ~6 concurrent c1xx
#                        (~12 GB, safe inside the observed ~25 GB headroom)
#    Raising /m back to 6 while keeping CL_MPCount=3 would allow 18 c1xx, which
#    is the OOM configuration this script exists to avoid.
#
#  clangd.exe must be relinked too: it links clangParse/clangSema/clangBasic,
#  so without a relink the IDE will not see the new Chinese spellings.
#
#  WHY chinese++.exe IS REFRESHED AT THE END
#    chinese++.exe is a hard link to clang++.exe; the driver only needs the file
#    name to end in "++" (clang/lib/Driver/ToolChain.cpp: {"++","--driver-mode=g++"}).
#    The linker rewrites clang++.exe by delete-then-create, which BREAKS the hard
#    link, leaving chinese++.exe on the previous build with no warning at all.
#    Hit for real on 2026-09-22 (new keywords silently missing). Do not remove.
#
#  ENCODING: THIS FILE IS INTENTIONALLY PURE ASCII -- do not add non-ASCII text.
#    PowerShell 5.1 reads a BOM-less file as GBK and mangles non-ASCII bytes.
#    Chinese in comments is mostly harmless, but Chinese in *code* (hash keys,
#    string literals) breaks the parser outright, and every tool that rewrites
#    this file tends to drop the UTF-8 BOM. Patching the BOM after each edit was
#    tried and forgotten three times, so the script is ASCII by construction.
#    Chinese design notes live in the usage guide at the repo root instead.
# ============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root    = 'E:\Chinese++'
$MsBuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe'
$LogDir  = Join-Path $Root 'build\_clangd_build'

$Targets = @(
    @{ Name = 'clang.exe';  Proj = Join-Path $Root 'build\tools\clang\tools\driver\clang.vcxproj' },
    @{ Name = 'clangd.exe'; Proj = Join-Path $Root 'build\tools\clang\tools\extra\clangd\tool\clangd.vcxproj' }
)

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-CommitHeadroomGB {
    try {
        $s = (Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit' -ErrorAction Stop).CounterSamples
        $c = ($s | Where-Object Path -match 'committed').CookedValue
        $l = ($s | Where-Object Path -match 'limit').CookedValue
        return [math]::Round(($l - $c) / 1GB, 1)
    } catch { return $null }
}

# About 4 GB per concurrent compiler.
$headroom = Get-CommitHeadroomGB
if ($null -eq $headroom) { $first = 4 } else { $first = [math]::Floor($headroom / 4) }
if ($first -lt 1) { $first = 1 }
if ($first -gt 2) { $first = 2 }
$levels = @(); $n = $first
while ($n -ge 1) { $levels += $n; if ($n -eq 1) { break }; $n = [math]::Floor($n / 2) }

Write-Output "commit headroom: $(if($null -eq $headroom){'unknown'}else{"$headroom GB"})  ->  /m:$first"
Write-Output "attempt sequence: $($levels -join ' , ')"
Write-Output ""

if (-not (Test-Path $MsBuild)) { Write-Output "MSBuild not found: $MsBuild"; exit 2 }

foreach ($t in $Targets) {
    if (-not (Test-Path $t.Proj)) { Write-Output "[$($t.Name)] project not found: $($t.Proj)"; continue }
    $done = $false
    foreach ($m in $levels) {
        $log = Join-Path $LogDir ("rebuild_{0}_m{1}.log" -f ($t.Name -replace '\.exe$',''), $m)
        Remove-Item $log -Force -ErrorAction SilentlyContinue
        Write-Output "=============================================================="
        Write-Output "[$(Get-Date -Format 'HH:mm:ss')] building $($t.Name)  /m:$m /p:CL_MPCount=1"
        Write-Output "  log: $log"
        Write-Output "=============================================================="
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        # Redirect through cmd, NOT through a PowerShell pipeline.
        # MSBuild /m:N spawns worker nodes; piping its output through
        # Out-File made every /m:N>1 run die instantly with an EMPTY log and
        # exit code 1 (observed 2026-09-22, three times), while the same
        # command with cmd redirection works. Regressing to /m:1 turned the
        # build from minutes into hours, so this detail matters.
        $cmdline = '"{0}" "{1}" /p:Configuration=Release /p:Platform=x64 /m:{2} /p:CL_MPCount=3 /nodeReuse:false /nologo /v:m > "{3}" 2>&1' -f `
            $MsBuild, $t.Proj, $m, $log
        & cmd /c $cmdline
        $code = $LASTEXITCODE
        $sw.Stop()
        Write-Output ("[$(Get-Date -Format 'HH:mm:ss')] $($t.Name) exit=$code  {0:N1} min" -f $sw.Elapsed.TotalMinutes)
        if ($code -eq 0) { $done = $true; break }

        Write-Output "--- last errors ---"
        $errs = Select-String -Path $log -Pattern 'error [A-Z]+[0-9]+|fatal error|MSB[0-9]{4}|OutOfMemory' -ErrorAction SilentlyContinue
        $errs | Select-Object -Last 20 | ForEach-Object { '  ' + $_.Line.Trim() }
        Write-Output "--- end ---"

        # Distinguish "code is wrong" from "not enough memory". Retrying only
        # helps the latter, so stop the ladder early on a real compile error.
        $oom = $errs | Where-Object { $_.Line -match 'MSB[0-9]{4}|OutOfMemory|0xc00000fd|fatal error C1[0-9]{3}|not enough memory|LNK1102|LNK1181' }
        $codeErr = $errs | Where-Object { $_.Line -match ': error C[0-9]{4}|error LNK[0-9]{4}|error: ' }
        if ((-not $oom) -and $codeErr) {
            Write-Output ">> real compile error (not OOM); retrying cannot change the result, stopping."
            break
        }
    }
    if (-not $done) { Write-Output "!! $($t.Name) FAILED" }
    Write-Output ""
}

Write-Output "=== artifact timestamps ==="
Get-ChildItem (Join-Path $Root 'build\Release\bin') -Filter 'clang*.exe' |
    Select-Object Name,@{n='MB';e={[math]::Round($_.Length/1MB,1)}},LastWriteTime | Format-Table -AutoSize

# ---------------------------------------------------------------------------
# Refresh the chinese++.exe hard link. See the header: the linker breaks it.
# ---------------------------------------------------------------------------
$BinDir  = Join-Path $Root 'build\Release\bin'
$SrcExe  = Join-Path $BinDir 'clang++.exe'
$LinkExe = Join-Path $BinDir 'chinese++.exe'
if (Test-Path $SrcExe) {
    if (Test-Path $LinkExe) {
        $a = Get-Item $SrcExe
        $b = Get-Item $LinkExe
        if (($a.LastWriteTime -eq $b.LastWriteTime) -and ($a.Length -eq $b.Length)) {
            Write-Output "chinese++.exe is in sync with clang++.exe (hard link OK)"
        } else {
            Write-Output "!! chinese++.exe is stale ($($b.LastWriteTime)); relinking..."
            Remove-Item $LinkExe -Force
            New-Item -ItemType HardLink -Path $LinkExe -Target $SrcExe | Out-Null
            Write-Output "   relinked, now $((Get-Item $LinkExe).LastWriteTime)"
        }
    } else {
        New-Item -ItemType HardLink -Path $LinkExe -Target $SrcExe | Out-Null
        Write-Output "chinese++.exe was missing; hard link created"
    }
}
