# ============================================================================
#  verify_clean_env.ps1 -- 「零 VS」在**本机能做到的最强证明**（§18.48 批5）
#
#  为什么不是"真干净机器"
#  ----------------------
#  本会话里做不到，两条路都实测堵死：
#    · Windows 沙箱：`Get-WindowsOptionalFeature -Online -FeatureName
#      Containers-DisposableClientVM` **被拒（需要提升）** ⇒ 无法启用/无法确认；
#    · WSL：`wsl -l -v` 报「没有已安装的分发」⇒ 装了也没法跑 Windows exe。
#  所以这里做**能在本机做的那部分**，做成可复跑脚本，并把做不到的那部分
#  如实登记在 docs\大检查\大检查问题台账.md §18.48 批5。
#
#  它证明什么 / 不证明什么（口径必须写清楚，不然就是自欺）
#  ------------------------------------------------------
#  ✅ 证明：在**最小环境**下、从**一个全新目录**（不是仓库、不是原解压位置）解出的发行包，
#     装得上（install.ps1）、自测全过（verify.ps1 26 项）、能真编真跑，
#     并且**头文件与库都没有一条来自 `Program Files`**。
#  ❌ 不证明：本机**装着** Visual Studio，clang 仍可能通过注册表"看得见"它。
#     所以这条证明的强度是「**我们没有用到它**」，不是「**它不存在**」。
#     要做到后者，得在一台真没有 VS 的机器上重跑本脚本（或启用沙箱后在里面跑）。
#
#  用法：
#    pwsh -NoProfile -File tools\verify_clean_env.ps1
#    pwsh -NoProfile -File tools\verify_clean_env.ps1 -Keep     # 保留临时目录便于翻看
#
#  ASCII-only 正文（中文只出现在注释里，PS 5.1 读无 BOM 文件按 ANSI 解码，
#  正文里出现中文字面量会被弄坏 —— 与 tools\verify_third_party.ps1 同一条纪律）。
# ============================================================================
param(
    [string] $Package = 'E:\Chinese++\dist\Chinese++-0.2-win64',
    [string] $Work    = 'E:\Chinese++\build\_review_own\batch5',
    [switch] $Keep
)
$ErrorActionPreference = 'Stop'

function Fail([string] $m) { Write-Host ("  [FAIL] " + $m) -ForegroundColor Red; $script:bad++ }
function Pass([string] $m) { Write-Host ("  [ok]   " + $m) -ForegroundColor Green;  $script:ok++ }
$script:ok = 0; $script:bad = 0

Write-Host '=== §18.48 批5：最小环境 + 全新目录 的零 VS 证明 ==='
Write-Host ("  源包：{0}" -f $Package)
if (-not (Test-Path (Join-Path $Package 'bin\chinese++.exe'))) { throw "不是发行包：$Package" }

# ---------------------------------------------------------------------------
# 1) 复制到一个**全新目录**（这一步同时验证"包能搬家"）
# ---------------------------------------------------------------------------
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force $Work | Out-Null
$dst = Join-Path $Work 'Chinese++-clean'
Write-Host ''
Write-Host '--- 1) 复制发行包到一个全新目录 ---'
Copy-Item -Recurse -Force $Package $dst
$exe = Join-Path $dst 'bin\chinese++.exe'
if (Test-Path $exe) { Pass ("copied to a brand-new path: " + $dst) } else { throw 'copy failed' }

# ---------------------------------------------------------------------------
# 2) 最小环境：PATH 只留包 + System32；把 VS/SDK 的环境变量全部清掉
#    （这些变量只要有人忘了清，"零 VS"就会变成假象）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 2) 收窄环境（PATH 只留包 + System32；清 VS/SDK 变量）---'
$vsEnv = @('INCLUDE', 'LIB', 'LIBPATH', 'VCINSTALLDIR', 'VSINSTALLDIR',
           'WindowsSdkDir', 'WindowsSDKVersion', 'VCToolsInstallDir', 'VCToolsVersion',
           'UniversalCRTSdkDir', 'UCRTVersion', 'CL', '_CL_', 'LINK', '_LINK_')
$cleared = @()
foreach ($n in $vsEnv) {
    if (Test-Path ("env:" + $n)) { Remove-Item ("env:" + $n) -Force; $cleared += $n }
}
$psExeDir = $PSHOME
$psWin  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0'
$rtWin  = @(Get-ChildItem (Join-Path $dst 'lib\clang') -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'lib\windows' } | Where-Object { Test-Path $_ })
$env:PATH = (@((Join-Path $dst 'bin')) + $rtWin + @(
                (Join-Path $env:SystemRoot 'System32'),
                $env:SystemRoot, $psWin)) -join ';'
Pass ("cleared {0} Microsoft env vars: {1}" -f $cleared.Count, ($(if ($cleared) { $cleared -join ', ' } else { '(none were set)' })))
$vsOnPath = @($env:PATH -split ';' | Where-Object { $_ -match 'Visual Studio|Windows Kits' })
if ($vsOnPath.Count -eq 0) { Pass 'PATH contains no Visual Studio / Windows Kits directory' }
else { Fail ('PATH still has: ' + ($vsOnPath -join '; ')) }
Write-Host ("         PATH = " + $env:PATH)

# ---------------------------------------------------------------------------
# 3) 在这个环境里装 —— install.ps1 会把 cfg 重写到新路径（搬家的关键一步）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 3) install.ps1（最小环境 + 全新路径）---'
$o = & "$psExeDir\pwsh.exe" -NoProfile -File (Join-Path $dst 'install.ps1') -NoEditor 2>&1
$inst = @($o | ForEach-Object { [string]$_ })
if ($LASTEXITCODE -eq 0 -and ($inst -match 'toolchain mode recorded').Count -gt 0) { Pass 'install.ps1 completed' }
else { Fail 'install.ps1 failed'; $inst | Select-Object -Last 6 | ForEach-Object { Write-Host "         $_" } }
$tc = Join-Path $dst 'bin\toolchain.txt'
if (Test-Path $tc) {
    $m = [regex]::Match([System.IO.File]::ReadAllText($tc), 'mode\s*=\s*(\w+)')
    if ($m.Success) { Pass ('toolchain.txt records mode = ' + $m.Groups[1].Value) }
    else { Fail 'toolchain.txt has no usable mode = line' }
} else { Fail 'bin\toolchain.txt missing' }
$cfgTxt = [System.IO.File]::ReadAllText((Join-Path $dst 'bin\chinese++.cfg'))
if ($cfgTxt -notmatch 'E:/Chinese\+\+/(zhstdlib|vendor|lib/(stl|compiler|mingw))') { Pass 'the regenerated cfg points at the NEW package, not at the repository' }
else { Fail 'the cfg still points at the repository (the -ZhRoot / dot-source bug of 18.48 batch 4)' }

# ---------------------------------------------------------------------------
# 4) 包内自测（26 项）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 4) verify.ps1（包内自测）---'
$o2 = & "$psExeDir\pwsh.exe" -NoProfile -File (Join-Path $dst 'verify.ps1') 2>&1
$v = @($o2 | ForEach-Object { [string]$_ })
$sum = @($v | Where-Object { $_ -match 'passed, .* failed' })
if ($sum.Count -gt 0 -and $sum[-1] -match '(\d+) passed, (\d+) failed' -and [int]$Matches[2] -eq 0) {
    Pass ('package self-test: ' + $sum[-1].Trim())
} else {
    Fail 'package self-test did not report a clean pass'
    $v | Select-Object -Last 8 | ForEach-Object { Write-Host "         $_" }
}

# ---------------------------------------------------------------------------
# 5) 真编真跑 + 来源断言（头 -H / 库 lld-link /verbose）
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '--- 5) 最小环境里真编真跑，并断言头与库都不来自 Program Files ---'
$t = Join-Path $Work 'src'
New-Item -ItemType Directory -Force $t | Out-Null

#  中文源码用码点拼，正文保持 ASCII（与 verify.ps1 同一套写法）
$zhMain = -join @([char]0x4E3B, [char]0x51FD, [char]0x6570)   # 主函数
$zhVec  = -join @([char]0x5411, [char]0x91CF)                 # 向量
$zhStd  = -join @([char]0x6807, [char]0x51C6)                 # 标准
$zhTail = -join @([char]0x5C3E, [char]0x63D2)                 # 尾插
$zhSize = -join @([char]0x5C3A, [char]0x5BF8)                 # 尺寸
$zhInc  = -join @([char]0x5305, [char]0x542B)                 # 包含

$cases = [ordered]@{
    'c'   = @{ args = @('-std=c++20');          body = "int main(){ return 0; }" }
    'cpp' = @{ args = @('-std=c++20');          body = "#include <iostream>`nint main(){ std::cout << 1; return 0; }" }
    'zh'  = @{ args = @('-std=c++20');          body = ($zhInc + ' <' + $zhVec + ">`n" + $zhMain + '(){ ' + $zhStd + '::' + $zhVec + '<int> v; v.' + $zhTail + '(1); return (int)v.' + $zhSize + '()-1; }') }
    'asan'= @{ args = @('-std=c++20', '-fsanitize=address'); body = "#include <vector>`nint main(){ std::vector<int> v{1,2}; return (int)v.size()-2; }" }
    'rtti'= @{ args = @('-std=c++20');          body = "#include <typeinfo>`nstruct B{virtual ~B(){}}; struct D:B{int x=7;};`nint main(){ D d; B* p=&d; return dynamic_cast<D*>(p) && typeid(*p)==typeid(D) ? 0 : 1; }" }
}

foreach ($k in $cases.Keys) {
    $c    = $cases[$k]
    $src  = Join-Path $t "$k.cpp"
    $exeK = Join-Path $t "$k.exe"
    $hLog = Join-Path $t "$k.h.txt"
    $lLog = Join-Path $t "$k.link.txt"
    [System.IO.File]::WriteAllText($src, $c.body, (New-Object System.Text.UTF8Encoding($false)))
    #  -H 看头从哪来；/verbose 看库从哪来。两者都真跑一次。
    & cmd /c "`"$exe`" $($c.args -join ' ') -H -Wl,/verbose `"$src`" -o `"$exeK`" > `"$hLog`" 2>&1"
    $code = $LASTEXITCODE
    $lines = @(Get-Content $hLog -ErrorAction SilentlyContinue)
    $hMs = @($lines | Where-Object { $_ -match '^\s*\.+\s' -and $_ -match 'Program Files' })
    $lMs = @($lines | Where-Object { $_ -match 'lld-link: Reading' -and $_ -match 'Program Files' })
    $readN = @($lines | Where-Object { $_ -match 'lld-link: Reading' }).Count
    if ($code -ne 0) {
        Fail ("[$k] link failed")
        $lines | Where-Object { $_ -match 'error|错误' } | Select-Object -First 3 | ForEach-Object { Write-Host "         $_" }
        continue
    }
    & cmd /c "`"$exeK`" > `"$(Join-Path $t "$k.run.txt")`" 2>&1"
    $rc = $LASTEXITCODE
    $flags = @()
    if ($hMs.Count -eq 0) { $flags += 'headers 0 Microsoft' } else { $flags += ("headers " + $hMs.Count + " Microsoft !") }
    if ($lMs.Count -eq 0) { $flags += ("libs 0/" + $readN + " Microsoft") } else { $flags += ("libs " + $lMs.Count + " Microsoft !") }
    if ($rc -eq 0 -and $hMs.Count -eq 0 -and $lMs.Count -eq 0) { Pass ("[$k] links, runs, " + ($flags -join ', ')) }
    else { Fail ("[$k] run=$rc  " + ($flags -join ', ')) }
    $hMs | Select-Object -First 1 | ForEach-Object { Write-Host "         $_" }
    $lMs | Select-Object -First 1 | ForEach-Object { Write-Host "         $_" }
}

# ---------------------------------------------------------------------------
$dstKb = [math]::Round(((Get-ChildItem $dst -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 0)
Write-Host ''
Write-Host '============================================================'
Write-Host ("  ok={0}  fail={1}   （包 {2} MB，装在 {3}）" -f $script:ok, $script:bad, $dstKb, $dst)
Write-Host '  口径：这证明「我们没用机器上的 VS」，不证明「机器上没有 VS」。'
Write-Host '============================================================'
if (-not $Keep) { Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue }
if ($script:bad -gt 0) { exit 1 } else { exit 0 }
