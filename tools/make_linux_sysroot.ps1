# ============================================================================
#  make_linux_sysroot.ps1 -- build the Linux x86_64 sysroot FROM the target VM
#
#  WHY THIS SHAPE (18.49, "multi-architecture", system substrate)
#  ------------------------------------------------------------
#  Chinese++ already has the X86 backend, and the package already ships the ELF
#  linker (ld.lld.exe -- lld picks its flavour from argv[0]). What a Linux target
#  additionally needs is a SYSROOT: the target distribution's headers, its CRT
#  startup objects and its shared libraries.
#
#  We take it FROM THE TARGET MACHINE (the user's own Linux VM) on purpose:
#    * legally clean -- we redistribute NOTHING from glibc/libstdc++. The sysroot
#      is generated on the user's own machine, for the user's own machine. This
#      mirrors the Windows rule ("Windows SDK / MSVC CRT binaries are never
#      shipped"), so the same discipline applies on both targets.
#    * correct by construction -- the headers and the crt objects come from the
#      very distribution the program will run on (glibc 2.39 on Ubuntu 24.04).
#  The tgz and the extracted tree are BUILD INPUTS: they are NOT committed.
#  A fresh clone regenerates them by running this script.
#
#  WHAT IT DOES
#    1. refuses to run if the VM is unreachable, and says how to start it;
#    2. tars a DETERMINISTIC list of paths on the VM with `tar -h` (dereference):
#       a zip/tar that carries symlinks cannot be extracted on Windows without
#       special privileges, so we materialise them instead;
#    3. pulls the tgz over scp and extracts it beside the repo;
#    4. asserts the LAYOUT (a checklist of exactly the files clang/ld.lld need);
#    5. writes SYSROOT.txt: where it came from, and SHA256 of every library and
#       startup object (the header trees are summarised by count + size).
#
#  WHY THE LIST IS HAND-WRITTEN (and not "tar the whole /usr")
#    /usr/lib/x86_64-linux-gnu alone is 1.8 GB here. The list below is the
#    closure clang/ld.lld actually asks for, discovered empirically: the first
#    attempts failed one library at a time (Scrt1.o, then libmvec.so.1), which is
#    what the `-v` linker errors reported. Note that BOTH /lib/... and
#    /usr/lib/... copies are needed: Ubuntu's libc.so/libm.so are GNU ld SCRIPT
#    files whose GROUP() lines name ABSOLUTE paths, and LLD resolves those
#    relative to --sysroot (measured: "cannot find /lib/... inside <sysroot>").
#
#  USAGE
#    pwsh -NoProfile -File tools\make_linux_sysroot.ps1
#    pwsh -NoProfile -File tools\make_linux_sysroot.ps1 -Check      # verify only
#    pwsh -NoProfile -File tools\make_linux_sysroot.ps1 -VmHost ubuntu
#
#  ASCII-only on purpose (like tools\verify_third_party.ps1): PowerShell 5.1
#  reads a BOM-less file as ANSI, so a Chinese literal here would become a bad
#  path on a GBK machine.
# ============================================================================
param(
    [string] $VmHost  = 'ubuntu',
    [string] $Dest    = 'E:\Chinese++\build\sysroot-linux-x64',
    [string] $Tgz     = 'E:\Chinese++\build\sysroot-linux-x64.tgz',
    [string] $VmTgz   = '/tmp/zh-sysroot-linux-x64.tgz',
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'

$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$scp = Join-Path $env:SystemRoot 'System32\OpenSSH\scp.exe'
foreach ($t in @($ssh, $scp)) { if (-not (Test-Path $t)) { throw "missing $t (OpenSSH client)" } }

$ok = 0; $bad = 0
function Pass([string] $m) { $script:ok++;  if (-not $Quiet) { Write-Host ("  [ok]   " + $m) -ForegroundColor Green } }
function Fail([string] $m) { $script:bad++; Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }

#  The deterministic closure. Keep the order stable: SYSROOT.txt lists it.
$fileList = @(
    'usr/include'
    'usr/lib/gcc'
    'usr/lib/x86_64-linux-gnu/Scrt1.o'
    'usr/lib/x86_64-linux-gnu/crt1.o'
    'usr/lib/x86_64-linux-gnu/crti.o'
    'usr/lib/x86_64-linux-gnu/crtn.o'
    'usr/lib/x86_64-linux-gnu/rcrt1.o'
    'usr/lib/x86_64-linux-gnu/libc.so'
    'usr/lib/x86_64-linux-gnu/libc.so.6'
    'usr/lib/x86_64-linux-gnu/libc_nonshared.a'
    'usr/lib/x86_64-linux-gnu/libm.so'
    'usr/lib/x86_64-linux-gnu/libm.so.6'
    'usr/lib/x86_64-linux-gnu/libmvec.so.1'
    'usr/lib/x86_64-linux-gnu/libstdc++.so.6'
    'usr/lib/x86_64-linux-gnu/libgcc_s.so.1'
    'lib/x86_64-linux-gnu/libc.so.6'
    'lib/x86_64-linux-gnu/libm.so.6'
    'lib/x86_64-linux-gnu/libmvec.so.1'
    'lib/x86_64-linux-gnu/libstdc++.so.6'
    'lib/x86_64-linux-gnu/libgcc_s.so.1'
    'lib64/ld-linux-x86-64.so.2'
)

#  The layout checklist: without any one of these, a cross link either fails or
#  silently resolves against the wrong thing.
$mustHave = @(
    'usr/include/stdio.h'
    'usr/include/c++/13/vector'
    'usr/include/c++/13/iostream'
    'usr/lib/gcc/x86_64-linux-gnu/13/libstdc++.so'
    'usr/lib/x86_64-linux-gnu/Scrt1.o'
    'usr/lib/x86_64-linux-gnu/crt1.o'
    'usr/lib/x86_64-linux-gnu/crti.o'
    'usr/lib/x86_64-linux-gnu/crtn.o'
    'usr/lib/x86_64-linux-gnu/libc.so'
    'usr/lib/x86_64-linux-gnu/libc.so.6'
    'usr/lib/x86_64-linux-gnu/libm.so'
    'usr/lib/x86_64-linux-gnu/libm.so.6'
    'usr/lib/x86_64-linux-gnu/libmvec.so.1'
    'usr/lib/x86_64-linux-gnu/libstdc++.so.6'
    'usr/lib/x86_64-linux-gnu/libgcc_s.so.1'
    'lib/x86_64-linux-gnu/libc.so.6'
    'lib/x86_64-linux-gnu/libm.so.6'
    'lib/x86_64-linux-gnu/libmvec.so.1'
    'lib/x86_64-linux-gnu/libstdc++.so.6'
    'lib/x86_64-linux-gnu/libgcc_s.so.1'
    'lib64/ld-linux-x86-64.so.2'
)

function To-Win([string] $p) { return ($p -replace '/', '\') }

Write-Host '=== 18.49: Linux x86_64 sysroot (system substrate) ==='

# ---------------------------------------------------------------------------
# 1) is the VM reachable?
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 1) target VM ---'
$probe = & $ssh -o BatchMode=yes -o ConnectTimeout=8 $VmHost 'echo ZH_SYSROOT_UP; uname -m; uname -r; ldd --version | head -1; (g++ --version | head -1)' 2>&1
$probeText = @($probe | ForEach-Object { [string]$_ })
if (-not ($probeText -match 'ZH_SYSROOT_UP')) {
    Write-Host ''
    Write-Host ("  [FAIL] cannot reach the VM over SSH (host alias '" + $VmHost + ").") -ForegroundColor Red
    Write-Host '         The sysroot is generated FROM the target machine on purpose' -ForegroundColor Yellow
    Write-Host '         (nothing from glibc/libstdc++ is ever redistributed), so this' -ForegroundColor Yellow
    Write-Host '         script cannot run without it.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '         Start it (headless) and retry:' -ForegroundColor Yellow
    Write-Host '           "C:\Program Files\VMware\VMware Workstation\vmrun.exe" -T ws start "E:\VirtualMachines\VMs\Ubuntu-24.04\Ubuntu-24.04.vmx" nogui' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('         ssh said: ' + ($probeText -join ' ')) -ForegroundColor DarkGray
    exit 2
}
$vmLine = ($probeText | Where-Object { $_ -match 'x86_64|glibc|g\+\+' } | Select-Object -First 3 | ForEach-Object { $_.Trim() }) -join ' | '
Pass ('VM reachable: ' + $vmLine)
$vmFacts = ($probeText | Select-Object -Skip 1 | Where-Object { $_ } | ForEach-Object { $_.Trim() }) -join ' | '

# ---------------------------------------------------------------------------
# 2) -Check: verify the existing tree against the checklist, do not touch the VM
# ---------------------------------------------------------------------------
if ($Check) {
    Write-Host ''
    Write-Host '--- 2) -Check: layout only ---'
    if (-not (Test-Path $Dest)) { Fail ("no sysroot at " + $Dest + " -- run without -Check first"); exit 1 }
    $missing = @($mustHave | Where-Object { -not (Test-Path (Join-Path $Dest (To-Win $_))) })
    if ($missing.Count -eq 0) { Pass ("layout complete (" + $mustHave.Count + " required paths)") }
    else { Fail ("layout incomplete, missing: " + ($missing -join ', ')) }
    $man = Join-Path $Dest 'SYSROOT.txt'
    if (Test-Path $man) { Pass 'SYSROOT.txt present' } else { Fail 'SYSROOT.txt missing' }
    Write-Host ''
    Write-Host ("  ok=$ok fail=$bad")
    if ($bad -gt 0) { exit 1 } else { exit 0 }
}

# ---------------------------------------------------------------------------
# 3) pack on the VM (deterministic list, dereferenced) and pull it
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) pack on the VM and pull ---'
$listText = ($fileList -join "`n")
$remote = @'
set -e
cd /
: > /tmp/zh-sysroot-list.txt
while IFS= read -r p; do [ -e "/$p" ] && echo "$p" >> /tmp/zh-sysroot-list.txt; done <<'ZH_LIST'
###LIST###
ZH_LIST
echo "valid $(wc -l < /tmp/zh-sysroot-list.txt) of $(echo '###COUNT###') listed paths"
rm -f ###TGZ###
tar czhf ###TGZ### -T /tmp/zh-sysroot-list.txt
echo "tgz $(stat -c%s ###TGZ###) bytes"
'@
$remote = $remote.Replace('###LIST###', $listText).Replace('###TGZ###', $VmTgz).Replace('###COUNT###', [string]$fileList.Count)
$out = & $ssh -o BatchMode=yes $VmHost $remote 2>&1
$outText = @($out | ForEach-Object { [string]$_ })
$validLine = $outText | Where-Object { $_ -match '^valid ' } | Select-Object -First 1
if (-not $validLine) { Fail ('packing on the VM failed: ' + ($outText -join ' ')); exit 1 }
if ($validLine -match '^valid (\d+) of (\d+)') {
    $validN = [int]$Matches[1]; $wantN = [int]$Matches[2]
} else {
    Fail ('unparsable output from the VM: ' + $validLine); exit 1
}
if ($validN -eq $wantN) { Pass ("the VM has all $wantN listed paths") }
else { Fail ("the VM is missing $($wantN - $validN) of the $wantN listed paths -- it is not the distribution this list was measured on") }
$sizeLine = $outText | Where-Object { $_ -match '^tgz (\d+) bytes' } | Select-Object -First 1
if ($sizeLine -match '^tgz (\d+) bytes') { Pass ("tgz on the VM: " + [math]::Round([int]$Matches[1] / 1MB, 1) + " MB") }

if (Test-Path $Tgz) { Remove-Item $Tgz -Force }
& $scp -q "${VmHost}:$VmTgz" $Tgz
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Tgz)) { Fail 'scp of the tgz failed'; exit 1 }
Pass ("pulled: " + [math]::Round((Get-Item $Tgz).Length / 1MB, 1) + " MB")

# ---------------------------------------------------------------------------
# 4) extract
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) extract ---'
if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
New-Item -ItemType Directory -Force $Dest | Out-Null
& tar -xzf $Tgz -C $Dest 2>&1 | Select-Object -First 3 | ForEach-Object { Write-Host ("         " + $_) }
$bytes = (Get-ChildItem $Dest -Recurse -File | Measure-Object Length -Sum).Sum
Pass ("extracted " + [math]::Round($bytes / 1MB, 1) + " MB into " + $Dest)

# ---------------------------------------------------------------------------
# 5) layout checklist
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) layout ---'
$missing = @($mustHave | Where-Object { -not (Test-Path (Join-Path $Dest (To-Win $_))) })
if ($missing.Count -eq 0) { Pass ("layout complete (" + $mustHave.Count + " required paths)") }
else { Fail ("layout incomplete, missing: " + ($missing -join ', ')) }

# ---------------------------------------------------------------------------
# 6) SYSROOT.txt
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 5) SYSROOT.txt ---'
$rows = @()
foreach ($rel in $fileList) {
    $full = Join-Path $Dest (To-Win $rel)
    if (-not (Test-Path $full)) { continue }
    $item = Get-Item $full
    if ($item.PSIsContainer) {
        $n = (Get-ChildItem $full -Recurse -File | Measure-Object).Count
        $s = (Get-ChildItem $full -Recurse -File | Measure-Object Length -Sum).Sum
        $rows += ("DIR   {0}  {1} files  {2} bytes" -f $rel, $n, $s)
    } else {
        $rows += ("{0}  {1}" -f (Get-FileHash $full -Algorithm SHA256).Hash.ToLower(), $rel)
    }
}
$header = @(
    '# Linux x86_64 sysroot -- generated by tools\make_linux_sysroot.ps1 (18.49)',
    '#',
    '# NOT COMMITTED. It is a build input, regenerated from the target machine:',
    '#     pwsh -NoProfile -File tools\make_linux_sysroot.ps1',
    '#',
    '# WHY FROM THE TARGET MACHINE: nothing from glibc / libstdc++ is redistributed.',
    '#   The sysroot is produced on the user own machine, for that machine -- the',
    '#   same rule as on Windows (Windows SDK / MSVC CRT binaries are never shipped).',
    '#',
    '# TARGET (as measured when this file was written):',
    ('#   ' + $vmFacts),
    '#',
    '# Entries below: <SHA256>  <path>   for libraries and startup objects,',
    '#                DIR       <path>   <count> files <bytes>   for header trees.',
    ""
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $Dest 'SYSROOT.txt'), $header + ($rows -join "`n") + "`n",
    (New-Object System.Text.UTF8Encoding($false)))
Pass ("SYSROOT.txt written (" + $rows.Count + " entries)")

Write-Host ''
Write-Host '============================================================'
Write-Host ("  ok=$ok fail=$bad")
Write-Host '============================================================'
if ($bad -gt 0) { exit 1 } else { exit 0 }
