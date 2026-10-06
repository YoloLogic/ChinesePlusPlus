# ============================================================================
#  verify_linux.ps1 -- cross-compile a CHINESE program to Linux x86_64 and RUN it
#                      on the target machine (18.49)
#
#  WHAT IT PROVES
#    * our compiler emits a well-formed x86-64 ELF for a Linux target, offline;
#    * the produced binary really RUNS on the target distribution and its stdout
#      matches, BYTE FOR BYTE, a native g++ build of the same program;
#    * plain g++ cannot compile the Chinese source at all (which is the point of
#      this project) -- so the comparison above is a fair one.
#
#  WHY THE SPLIT (offline vs VM) MATTERS
#    The commit gate must NEVER depend on a virtual machine being powered on, or
#    "green" would mean "the VM happened to be up". So:
#      - this script's OFFLINE half (cross-compile + ELF header assertions) is what
#        a gate may run, with -NoVm;
#      - the VM half is run here, by hand, and its LOG is committed as evidence.
#
#  JUDGEMENT DISCIPLINE
#    Every claim below is backed by an exit code, a byte comparison or bytes read
#    out of the ELF header. Nothing is asserted from memory.
#
#  USAGE
#    pwsh -NoProfile -File tools\verify_linux.ps1                 # offline + VM
#    pwsh -NoProfile -File tools\verify_linux.ps1 -NoVm           # offline only
#    pwsh -NoProfile -File tools\verify_linux.ps1 -Keep           # keep temp files
#
#  ASCII-only on purpose (see tools\verify_third_party.ps1).
# ============================================================================
param(
    [string] $VmHost    = 'ubuntu',
    [string] $Sysroot   = 'E:\Chinese++\build\sysroot-linux-x64',
    [string] $Compiler  = 'E:\Chinese++\build\Release\bin\chinese++.exe',
    [string] $LdPath    = '',
    [string] $Work      = 'E:\Chinese++\build\_review_own\linux_verify',
    [switch] $ViaCfg,
    [switch] $NoVm,
    [switch] $Keep,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$scp = Join-Path $env:SystemRoot 'System32\OpenSSH\scp.exe'

$ok = 0; $bad = 0
function Pass([string] $m) { $script:ok++;  if (-not $Quiet) { Write-Host ("  [ok]   " + $m) -ForegroundColor Green } }
function Fail([string] $m) { $script:bad++; Write-Host ("  [FAIL] " + $m) -ForegroundColor Red }
function Info([string] $m) { if (-not $Quiet) { Write-Host ("         " + $m) -ForegroundColor DarkGray } }

# ---------------------------------------------------------------------------
# 1) preflight -- say exactly what is missing and how to fix it
# ---------------------------------------------------------------------------
Write-Host '=== 18.49: Linux x86_64 cross-compile + real run ==='
Write-Host ''
Write-Host '--- 1) preflight ---'
if (-not (Test-Path $Compiler)) { throw "compiler not found: $Compiler" }
Pass ('compiler: ' + $Compiler)

#  Find an ELF linker. It MUST be named ld.lld (.exe): lld selects its flavour from
#  argv[0], so handing it lld-link.exe would make it behave as a COFF linker and
#  silently produce a Windows binary. Never substitute one for the other.
if (-not $LdPath) {
    $cands = @(
        (Join-Path (Split-Path $Compiler -Parent) 'ld.lld.exe'),
        (Join-Path $root 'build-lld\Release\bin\ld.lld.exe'),
        (Join-Path $root 'build\Release\bin\ld.lld.exe')
    )
    foreach ($d in @(Get-ChildItem (Join-Path $root 'dist') -Directory -ErrorAction SilentlyContinue)) {
        $cands += (Join-Path $d.FullName 'bin\ld.lld.exe')
    }
    foreach ($c in $cands) { if (Test-Path $c) { $LdPath = $c; break } }
}

#  Missing prerequisites are NOT a failure of the target -- they just mean this
#  evidence cannot be produced here. Exit 2 says exactly that, so a commit gate
#  can skip honestly instead of turning red (or, worse, turning green by accident).
$missing = @()
if (-not $LdPath -or -not (Test-Path $LdPath)) { $missing += 'an ELF linker named ld.lld.exe' }
if (-not (Test-Path $Sysroot))                  { $missing += ('the sysroot at ' + $Sysroot) }
if ($missing.Count -gt 0) {
    Write-Host ''
    Write-Host '  [跳过] 前置件不全 —— 这不算失败，但也就拿不到这条证据：' -ForegroundColor Yellow
    foreach ($m in $missing) { Write-Host ('          缺少：' + $m) -ForegroundColor Yellow }
    Write-Host '         sysroot: pwsh -NoProfile -File tools\make_linux_sysroot.ps1 （从目标机生成，不入库）' -ForegroundColor DarkGray
    Write-Host '         Linux 目标（离线）：跳过' -ForegroundColor DarkGray
    exit 2
}
Pass ('ELF linker: ' + $LdPath)
$sysrootMb = [math]::Round(((Get-ChildItem $Sysroot -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)
Pass ("sysroot: $Sysroot ($sysrootMb MB)")

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

# ---------------------------------------------------------------------------
# 2) the sources. The Chinese one is built from CODE POINTS so this file stays
#    pure ASCII (a Chinese literal here would be mangled by PS 5.1 on GBK).
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) sources ---'
$zhInc  = '#' + [char]0x5305 + [char]0x542B                    # #include (Chinese directive)
$zhIO   = -join @([char]0x8F93, [char]0x51FA, [char]0x6D41)    # ostream-ish header name
$zhIn   = -join @([char]0x8F93, [char]0x5165)                  # "input"
$zhInt  = -join @([char]0x6574, [char]0x6570)                  # int
$zhMain = -join @([char]0x4E3B, [char]0x51FD, [char]0x6570)    # main
$zhStd  = -join @([char]0x6807, [char]0x51C6)                  # std
$zhCout = -join @([char]0x6807, [char]0x51C6, [char]0x8F93, [char]0x51FA, [char]0x6D41)  # std::cout alias
$zhEndl = -join @([char]0x884C, [char]0x5C3E, [char]0x6D41, [char]0x51B2, [char]0x5237)  # std::endl alias
$zhRet  = -join @([char]0x8FD4, [char]0x56DE)                  # return
$greet  = -join @([char]0x4F60, [char]0x597D, [char]0xFF0C, [char]0x004C, [char]0x0069, [char]0x006E, [char]0x0075, [char]0x0078)  # hello, Linux

$zhSrc = @(
    ($zhInc + ' <' + $zhIn + $zhIO + '>'),
    ($zhInt + ' ' + $zhMain + '() {'),
    ('    ' + $zhStd + '::' + $zhCout + ' << "' + $greet + '" << ' + $zhStd + '::' + $zhEndl + ';'),
    ('    ' + $zhRet + ' 0;'),
    '}'
) -join "`n"
$zhFile = Join-Path $Work 'zh_hello.cpp'
[System.IO.File]::WriteAllText($zhFile, $zhSrc, (New-Object System.Text.UTF8Encoding($false)))
Pass ('Chinese source written (' + $zhSrc.Length + ' chars)')
Info (($zhSrc -split "`n")[0])

#  The native control: the SAME program spelled in English, so g++ can build it.
$enSrc = @(
    '#include <iostream>',
    'int main() {',
    ('    std::cout << "' + $greet + '" << std::endl;'),
    '    return 0;',
    '}'
) -join "`n"
$enFile = Join-Path $Work 'en_hello.cpp'
[System.IO.File]::WriteAllText($enFile, $enSrc, (New-Object System.Text.UTF8Encoding($false)))
Pass 'English control source written'

# ---------------------------------------------------------------------------
# 3) cross-compile
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) cross-compile (offline) ---'
$exe = Join-Path $Work 'zh_hello'
Remove-Item $exe -ErrorAction SilentlyContinue
$log = Join-Path $Work 'compile.txt'
if ($ViaCfg) {
    #  The driver's own <name>.cfg already carries --target/--sysroot/--ld-path,
    #  so a USER writes nothing but the file name. Compiling with no target flags
    #  is therefore the thing being tested here.
    $cxxArgs = @('-std=c++20', $zhFile, '-o', $exe)
    Info 'target flags come from the driver cfg (no flags on this command line)'
} else {
    $cxxArgs = @('--target=x86_64-unknown-linux-gnu', "--sysroot=$Sysroot", "--ld-path=$LdPath",
                 '-fuse-ld=lld', '-std=c++20', $zhFile, '-o', $exe)
}
& $Compiler @cxxArgs 2>&1 | Set-Content -Encoding UTF8 $log
$rc = $LASTEXITCODE
if ($rc -eq 0 -and (Test-Path $exe)) { Pass ("cross-compile exit 0, produced " + [math]::Round((Get-Item $exe).Length / 1KB, 1) + " KB") }
else {
    Fail ("cross-compile failed (exit $rc)")
    Get-Content $log | Select-Object -First 6 | ForEach-Object { Info $_ }
}

# ---------------------------------------------------------------------------
# 4) OFFLINE assertions: read the ELF header ourselves (no external tool needed)
#    e_ident / e_type / e_machine, plus PT_INTERP from the program headers.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) ELF assertions (offline, bytes read from the file) ---'
function Get-ElfFacts([string] $Path) {
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 64) { return $null }
    if (-not ($b[0] -eq 0x7F -and $b[1] -eq 0x45 -and $b[2] -eq 0x4C -and $b[3] -eq 0x46)) { return $null }
    $f = [ordered]@{
        Path    = $Path
        Class   = $b[4]                                  # 1 = 32-bit, 2 = 64-bit
        Data    = $b[5]                                  # 1 = little endian
        Type    = [BitConverter]::ToUInt16($b, 16)       # 2 = EXEC, 3 = DYN (PIE)
        Machine = [BitConverter]::ToUInt16($b, 18)       # 62 = EM_X86_64
        Interp  = ''
    }
    $phoff  = [BitConverter]::ToUInt64($b, 32)
    $phent  = [BitConverter]::ToUInt16($b, 54)
    $phnum  = [BitConverter]::ToUInt16($b, 56)
    for ($i = 0; $i -lt $phnum; $i++) {
        $o = [int]$phoff + ($i * $phent)
        if ($o + 4 -gt $b.Length) { break }
        if ([BitConverter]::ToUInt32($b, $o) -ne 3) { continue }   # PT_INTERP
        $po = [int][BitConverter]::ToUInt64($b, $o + 8)
        $pf = [int][BitConverter]::ToUInt64($b, $o + 32)
        $s = [System.Text.Encoding]::ASCII.GetString($b, $po, $pf)
        $f.Interp = $s.TrimEnd([char]0)
    }
    return [pscustomobject]$f
}
if (Test-Path $exe) {
    $f = Get-ElfFacts $exe
    if (-not $f) { Fail 'the produced file is not an ELF' }
    else {
        if ($f.Class -eq 2)   { Pass 'ELFCLASS64' }                          else { Fail ('ELF class = ' + $f.Class + ' (want 2 = 64-bit)') }
        if ($f.Data  -eq 1)   { Pass 'ELFDATA2LSB (little endian)' }         else { Fail ('ELF data = ' + $f.Data + ' (want 1)') }
        if ($f.Machine -eq 62) { Pass 'EM_X86_64 (62)' }                     else { Fail ('e_machine = ' + $f.Machine + ' (want 62 = x86-64)') }
        if ($f.Type -eq 3)    { Pass 'ET_DYN (position independent executable)' } elseif ($f.Type -eq 2) { Pass 'ET_EXEC' } else { Fail ('e_type = ' + $f.Type) }
        if ($f.Interp -eq '/lib64/ld-linux-x86-64.so.2') { Pass ('PT_INTERP = ' + $f.Interp) }
        else { Fail ('PT_INTERP = "' + $f.Interp + '" (want /lib64/ld-linux-x86-64.so.2)') }
    }
} else { Fail 'no binary to inspect (the compile step failed)' }

# ---------------------------------------------------------------------------
# 5) the VM half
# ---------------------------------------------------------------------------
if ($NoVm) {
    Write-Host ''
    Write-Host '--- 5) VM half SKIPPED (-NoVm) ---'
    Info 'the offline half above is what a commit gate may run;'
    Info 'the real run is done by hand and its log is committed as evidence.'
} else {
    Write-Host ''
    Write-Host '--- 5) real run on the target machine ---'
    $probe = & $ssh -o BatchMode=yes -o ConnectTimeout=8 $VmHost 'echo ZH_VM_UP; uname -m; uname -r; ldd --version | head -1; g++ --version | head -1' 2>&1
    $pt = @($probe | ForEach-Object { [string]$_ })
    if (-not ($pt -match 'ZH_VM_UP')) {
        Fail ('VM unreachable (host alias ' + $VmHost + ')')
        Write-Host '         Start it headless and retry:' -ForegroundColor Yellow
        Write-Host '           "C:\Program Files\VMware\VMware Workstation\vmrun.exe" -T ws start "E:\VirtualMachines\VMs\Ubuntu-24.04\Ubuntu-24.04.vmx" nogui' -ForegroundColor Yellow
    } else {
        Pass ('VM up: ' + (($pt | Select-Object -Skip 1 | Where-Object { $_ -match 'x86_64|glibc|g\+\+' } | Select-Object -First 3 | ForEach-Object { $_.Trim() }) -join ' | '))
        $vmDir = '/tmp/zh-linux-verify'
        & $ssh -o BatchMode=yes $VmHost ("rm -rf $vmDir && mkdir -p $vmDir") 2>&1 | Out-Null
        & $scp -q $exe "${VmHost}:$vmDir/ours" 2>&1 | Out-Null
        & $scp -q $enFile "${VmHost}:$vmDir/native.cpp" 2>&1 | Out-Null
        & $scp -q $zhFile "${VmHost}:$vmDir/chinese.cpp" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'scp of the artifacts failed' }
        else { Pass 'artifacts copied into the VM' }

        #  One shell script on the far side, so quoting cannot bite us.
        $remote = @'
set -u
cd /tmp/zh-linux-verify
chmod +x ours
./ours > ours.out 2>&1
echo "RC_OURS=$?"
g++ -std=c++20 native.cpp -o native 2> native.build.err
echo "RC_GXX_ENGLISH=$?"
./native > native.out 2>&1
echo "RC_NATIVE=$?"
echo "SIZE_OURS=$(stat -c%s ours.out)"
echo "SIZE_NATIVE=$(stat -c%s native.out)"
echo "SHA_OURS=$(sha256sum ours.out | cut -d' ' -f1)"
echo "SHA_NATIVE=$(sha256sum native.out | cut -d' ' -f1)"
if cmp -s ours.out native.out; then echo "BYTE_IDENTICAL=yes"; else echo "BYTE_IDENTICAL=no"; fi
echo "OURS_OUTPUT_BEGIN"
cat ours.out
echo "OURS_OUTPUT_END"
g++ -std=c++20 chinese.cpp -o /dev/null 2> gxx_on_chinese.err
echo "RC_GXX_ON_CHINESE=$?"
head -1 gxx_on_chinese.err
'@
        $r = & $ssh -o BatchMode=yes $VmHost $remote 2>&1
        $lines = @($r | ForEach-Object { [string]$_ })
        function Field([string] $k) { ($lines | Where-Object { $_ -like "$k=*" } | Select-Object -First 1) -replace "^$k=", '' }
        $rcOurs = Field 'RC_OURS'; $rcNat = Field 'RC_NATIVE'
        $rcEn   = Field 'RC_GXX_ENGLISH'; $rcZh = Field 'RC_GXX_ON_CHINESE'
        $shaO   = Field 'SHA_OURS'; $shaN = Field 'SHA_NATIVE'
        $ident  = Field 'BYTE_IDENTICAL'; $szO = Field 'SIZE_OURS'; $szN = Field 'SIZE_NATIVE'

        if ($rcEn -eq '0') { Pass 'the VM can build the English control with g++ (control group is valid)' }
        else { Fail ("g++ failed on the English control (exit $rcEn) -- comparison would be meaningless") }
        if ($rcOurs -eq '0') { Pass 'our cross-compiled binary RUNS on the target: exit 0' }
        else { Fail ("our binary exited $rcOurs on the target") }
        if ($rcNat -eq '0') { Pass 'the native control runs: exit 0' } else { Fail ("native control exited $rcNat") }
        if ($ident -eq 'yes') { Pass ("stdout is BYTE-IDENTICAL to the native build ($szO bytes, sha256 " + $shaO.Substring(0, 16) + "...)") }
        else { Fail ("stdout differs from the native build (ours=$szO sha=$shaO / native=$szN sha=$shaN)") }
        if ($rcZh -ne '0') { Pass ("plain g++ cannot compile the Chinese source (exit $rcZh) -- the comparison above is therefore a fair one") }
        else { Fail 'g++ compiled the Chinese source, which should be impossible' }

        $i1 = [array]::IndexOf($lines, 'OURS_OUTPUT_BEGIN'); $i2 = [array]::IndexOf($lines, 'OURS_OUTPUT_END')
        if ($i1 -ge 0 -and $i2 -gt $i1) {
            $progOut = ($lines[($i1 + 1)..($i2 - 1)]) -join "`n"
            Pass ('program output: ' + $progOut)
        }
    }
}

Write-Host ''
Write-Host '============================================================'
Write-Host ("  ok=$ok fail=$bad")
if (-not $Keep) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host '============================================================'
if ($bad -gt 0) { exit 1 } else { exit 0 }
