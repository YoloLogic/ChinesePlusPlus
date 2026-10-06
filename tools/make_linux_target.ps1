# ============================================================================
#  make_linux_target.ps1 -- register a "chinese++-linux" driver for the Linux
#                           x86_64 target (18.49)
#
#  THE IDEA (and why it needs no compiler change)
#    clang reads a configuration file named after the driver that was invoked:
#    chinese++.exe reads chinese++.cfg, clang.exe reads clang.cfg. That is a
#    documented clang feature this project already relies on for the Chinese
#    include paths. So a NEW TARGET is just a new driver name with its own cfg:
#
#        bin\chinese++-linux.exe   (HARDLINK to chinese++.exe -- no extra bytes)
#        bin\chinese++-linux.cfg   (absolute paths: zhstdlib + --target + --sysroot
#                                   + --ld-path)
#
#    and the user writes:      chinese++-linux  你好.cpp -o 你好
#
#  WHY IT IS NOT SHIPPED PRE-WIRED IN THE PACKAGE
#    The sysroot must come from the target machine itself (see
#    tools\make_linux_sysroot.ps1: nothing from glibc/libstdc++ is redistributed).
#    So the package cannot know the path in advance; the user generates the
#    sysroot, then registers the target with this script. Same trade-off as the
#    existing <driver>.cfg files: absolute paths mean "re-run install after moving
#    the folder".
#
#  USAGE
#    pwsh -NoProfile -File tools\make_linux_target.ps1 -BinDir <pkg>\bin
#    pwsh -NoProfile -File tools\make_linux_target.ps1 -BinDir <pkg>\bin -Check
#    pwsh -NoProfile -File tools\make_linux_target.ps1 -BinDir <pkg>\bin -Verify
#
#  ASCII-only on purpose.
# ============================================================================
param(
    [Parameter(Mandatory = $true)][string] $BinDir,
    [string] $Triple  = 'x86_64-unknown-linux-gnu',
    [string] $Sysroot = 'E:\Chinese++\build\sysroot-linux-x64',
    [string] $LdPath,
    [switch] $Check,
    [switch] $Verify,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')

#  ---------------------------------------------------------------------------
#  THE DRIVER NAME IS NOT FREE-FORM -- MEASURED 2026-10-06, and it cost a hunt.
#
#  clang builds the config-file name from the *driver mode* it derives from
#  argv[0] (clang/lib/Driver/Driver.cpp, ~line 1418: it tries
#  "<triple>-<mode>.cfg", then "<mode>.cfg", then "<triple>.cfg"), NOT from the
#  raw file name. Consequences, all measured with a marker -D in each candidate:
#
#    chinese++.exe                        -> reads chinese++.cfg        (works)
#    chinese++-linux.exe                  -> reads clang++.cfg          (!)
#    chinese++linux.exe                   -> reads clang++.cfg          (!)
#    chineselinux++.exe                   -> reads clang++.cfg          (!)
#    linuxzh++.exe                        -> reads clang++.cfg          (!)
#    x86_64-unknown-linux-gnu-chinese++.exe -> reads ITS OWN cfg, and the
#                                            leading triple also sets the
#                                            target triple (upstream's own
#                                            documented pattern: "the name is
#                                            <triple>-clang++").
#
#  So a per-target driver MUST look like <triple>-chinese++. Anything else
#  silently loads clang++.cfg and happily produces a WINDOWS binary -- the
#  "looks configured, does nothing" failure this project keeps hunting for.
#  ---------------------------------------------------------------------------
$driver = "$Triple-chinese++"
$ok = 0; $bad = 0
function Pass([string] $m) { $script:ok++;  if (-not $Quiet) { Write-Host ("  [ok]   " + $m) -ForegroundColor Green } }
function Fail([string] $m) { $script:bad++; Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }

if (-not (Test-Path $BinDir)) { throw "no such directory: $BinDir" }

#  The ELF linker: lld picks its flavour from argv[0], so ld.lld.exe is the same
#  binary as lld-link.exe. Prefer the one sitting beside the driver.
if (-not $LdPath) {
    foreach ($c in @((Join-Path $BinDir 'ld.lld.exe'), (Join-Path $BinDir 'lld-link.exe'))) {
        if (Test-Path $c) { $LdPath = $c; break }
    }
}
if (-not $LdPath) { throw "no ld.lld.exe / lld-link.exe in $BinDir (pass -LdPath)" }

$exePath = Join-Path $BinDir "$driver.exe"
$cfgPath = Join-Path $BinDir "$driver.cfg"
$realExe = Join-Path $BinDir 'chinese++.exe'
$utf8 = New-Object System.Text.UTF8Encoding($false)

#  Which zhstdlib do the include paths point at? If the driver lives inside a
#  distribution package (<pkg>\bin), it must be THAT package's zhstdlib, not the
#  development tree's. Same rule make_zhcfg.ps1 follows via -ZhRoot.
$zhRoot = $root
$pkgRoot = Split-Path $BinDir -Parent
if (Test-Path (Join-Path $pkgRoot 'zhstdlib')) { $zhRoot = $pkgRoot }

Write-Host '=== 18.49: register the Linux x86_64 driver ==='

# ---------------------------------------------------------------------------
# -Check: does the pair exist and match what we would write?
# ---------------------------------------------------------------------------
if ($Check) {
    if (Test-Path $exePath) { Pass ("$driver.exe present") } else { Fail "$driver.exe missing" }
    if (Test-Path $cfgPath) { Pass ("$driver.cfg present") } else { Fail "$driver.cfg missing" }
    if ((Test-Path $cfgPath) -and (Test-Path $Sysroot)) {
        $cfg = [System.IO.File]::ReadAllText($cfgPath)
        $want = ($Sysroot -replace '\\', '/')
        if ($cfg -like "*$want*") { Pass 'the cfg names the current sysroot' }
        else { Fail ("the cfg does not name $want -- re-run without -Check") }
    }
    Write-Host ''
    Write-Host ("  ok=$ok fail=$bad")
    if ($bad -gt 0) { exit 1 } else { exit 0 }
}

# ---------------------------------------------------------------------------
# 1) the alias (hardlink; copy only if the filesystem refuses)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 1) driver alias ---'
if (-not (Test-Path $realExe)) { throw "no $realExe to link to" }
if (Test-Path $exePath) { Remove-Item $exePath -Force }
try {
    New-Item -ItemType HardLink -Path $exePath -Target $realExe -ErrorAction Stop | Out-Null
    Pass ("hardlink created: $driver.exe -> chinese++.exe (0 extra bytes)")
} catch {
    Copy-Item $realExe $exePath -Force
    Pass ("copied $driver.exe (this filesystem refused a hardlink)")
}

# ---------------------------------------------------------------------------
# 2) the cfg -- exactly the shape make_zhcfg.ps1 writes, plus the target plumbing
#    (absolute paths, forward slashes, whitespace-split => quote what has spaces)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) driver cfg ---'
if (-not (Test-Path $Sysroot)) {
    Fail ("no sysroot at $Sysroot")
    Write-Host '         Generate it from the target machine first:' -ForegroundColor Yellow
    Write-Host '           pwsh -NoProfile -File tools\make_linux_sysroot.ps1' -ForegroundColor Yellow
    exit 1
}
$lines = @()
foreach ($p in (Get-ZhIncludeDirs $zhRoot)) {
    $lines += '-isystem'
    $lines += ('"' + ($p.Replace('\', '/')) + '"')
}
$lines += '--target=x86_64-unknown-linux-gnu'
$lines += ('--sysroot=' + ($Sysroot.Replace('\', '/')))
$lines += ('--ld-path=' + ($LdPath.Replace('\', '/')))
$lines += '-fuse-ld=lld'
[System.IO.File]::WriteAllText($cfgPath, (($lines -join "`n") + "`n"), $utf8)
Pass ("cfg written: $($lines.Count) lines (zh includes + target + sysroot + ld-path)")
if (-not $Quiet) { $lines | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor DarkGray } }

# ---------------------------------------------------------------------------
# 3) optional: prove it works, through the normal verification path
# ---------------------------------------------------------------------------
if ($Verify) {
    Write-Host ''
    Write-Host '--- 3) verify through the driver (offline half) ---'
    & pwsh -NoProfile -File (Join-Path $root 'tools\verify_linux.ps1') -ViaCfg -Compiler $exePath -NoVm -Quiet
    if ($LASTEXITCODE -eq 0) { Pass 'verify_linux.ps1 -ViaCfg -NoVm passed' }
    else { Fail 'verify_linux.ps1 -ViaCfg -NoVm failed' }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ("  ok=$ok fail=$bad")
Write-Host ("  the user now writes:   $driver  你好.cpp -o 你好")
Write-Host '============================================================'
if ($bad -gt 0) { exit 1 } else { exit 0 }
