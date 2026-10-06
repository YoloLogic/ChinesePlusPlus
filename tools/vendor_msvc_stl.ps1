# ============================================================================
#  vendor_msvc_stl.ps1 -- 把【开源可再发行】的 MSVC STL 头搬进我们的仓库（§18.48 批1）
#
#  为什么能抄：
#    实测本机 `VC\Tools\MSVC\<ver>\include` 共 270 个文件，按文件头 SPDX 分成两类：
#      · 184 个带 `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception` ⇒ **开源、可再发行**
#        （微软 STL 的源码许可，保留声明即可）；
#      · 86 个不带（MSVC 编译器支撑头：vcruntime*.h / sal.h / crtdefs.h / eh.h / amp*.h …）
#        ⇒ **闭源，不许搬**（批2 用手搓等价物替代）。
#    所以本脚本只搬前一类，并且**只搬**——一个字节都不改（每个文件的 SPDX 头就是许可声明）。
#
#  做出来的东西：
#    vendor\msvc-stl\            184 个开源 STL 头（原样）
#    vendor\msvc-stl\SOURCE.txt  来源（VS 路径 / 工具集版本 / 文件数 / 每个文件的 SHA256）
#    之后 `tools\zh_includes.ps1` 会把 vendor\msvc-stl 加进搜索路径，于是
#    `#包含 <向量>`（它内部 `#include <vector>`）在**没有 VS 的机器上**也能解析。
#
#  用法：
#    pwsh -NoProfile -File tools\vendor_msvc_stl.ps1          # 从本机 VS 抄进 vendor\
#    pwsh -NoProfile -File tools\vendor_msvc_stl.ps1 -Check   # 核对 vendor\ 与 SOURCE.txt 一致
#    pwsh -NoProfile -File tools\vendor_msvc_stl.ps1 -From <include目录>   # 指定来源
# ============================================================================
param(
    [string] $From,
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$dest = Join-Path $root 'vendor\msvc-stl'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-MsvcIncludeDir {
    <#  找本机 MSVC 工具集的 include 目录（只读，不改任何东西） #>
    param([string] $Hint)
    if ($Hint) {
        if (-not (Test-Path $Hint)) { throw "没有这个目录：$Hint" }
        return (Resolve-Path $Hint).Path
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $p = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($p) {
            $inc = Get-ChildItem (Join-Path $p.Trim() 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'include' } |
                   Where-Object { Test-Path $_ } | Select-Object -First 1
            if ($inc) { return (Resolve-Path $inc).Path }
        }
    }
    throw '找不到 MSVC 的 include 目录 —— 用 -From 显式指定（本机需装 VS Build Tools 才能抄）'
}

function Test-OpenSource([string] $Path) {
    <#  判据：文件头 60 行里有没有 STL 的开源 SPDX 标记（不是"看起来像"，是许可证字段） #>
    $head = (Get-Content -LiteralPath $Path -TotalCount 60 -ErrorAction SilentlyContinue) -join "`n"
    return ($head -match 'SPDX-License-Identifier:\s*Apache-2\.0 WITH LLVM-exception')
}

if ($Check) {
    if (-not (Test-Path $dest)) { Write-Host '❌ vendor\msvc-stl 不存在 —— 先跑一次不带 -Check 的' -ForegroundColor Red; exit 1 }
    $srcTxt = Join-Path $dest 'SOURCE.txt'
    if (-not (Test-Path $srcTxt)) { Write-Host '❌ 缺 vendor\msvc-stl\SOURCE.txt' -ForegroundColor Red; exit 1 }
    $bad = @(); $n = 0
    foreach ($line in (Get-Content $srcTxt | Where-Object { $_ -match '^[0-9a-f]{64}  ' })) {
        $hash = $line.Substring(0, 64); $name = $line.Substring(66)
        $f = Join-Path $dest $name
        $n++
        if (-not (Test-Path -LiteralPath $f)) { $bad += "缺文件：$name"; continue }
        $h = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $hash) { $bad += "内容变了：$name" }
    }
    if ($bad.Count) {
        Write-Host '❌ 开源源代码头与 SOURCE.txt 不一致（§18.48）：' -ForegroundColor Red
        $bad | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Red }
        exit 1
    }
    if (-not $Quiet) { Write-Host ("MSVC STL 开源头：通过（{0} 个文件，逐文件 SHA256 一致）" -f $n) -ForegroundColor Green }
    exit 0
}

$src = Get-MsvcIncludeDir $From
Write-Host "来源：$src"
$all = Get-ChildItem -LiteralPath $src -File

#  ---------------------------------------------------------------------------
#  【绝不能搬】clang 自己资源目录里也有的名字（实测 11 个：10 个内建 *mmintrin.h
#  + iso646.h + yvals_core.h）。为什么：我们把这些目录放在 `-isystem`（比 clang 的
#  资源目录 `-internal-isystem` **更靠前**）⇒ 会 shadow 掉 clang 自己的那份：
#    · immintrin.h 这类：clang 的 intrin.h/x86intrin.h/ia32intrin.h 与 MSVC 那份
#      声明冲突（实测报「_castf32_u32 的非常量表达式声明跟在常量表达式声明之后」，
#      整个 <vector> 都编不过）；
#    · yvals_core.h：clang 那份是 **#include_next 垫片**（25 行），MSVC 那份必须由它
#      去 include_next 找到 —— 我们抢在前面就把它整条路断了。
#  实测判据（不靠人记）：拿 clang 资源目录的文件名与候选取交集，交集一律不搬。
#  ⚠ 代价（记进台账 §18.48 批2）：yvals_core.h 因此仍要 VS；批2 要在**更靠后**的
#    搜索位置补上 MSVC 那份（让垫片的 include_next 找得到），而不是靠覆盖。
#  ---------------------------------------------------------------------------
$clangInc = $null
foreach ($cand in @('build\Release\lib\clang\24\include') + @(Get-ChildItem (Join-Path $root 'build\Release\lib\clang') -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'include' })) {
    if (Test-Path $cand) { $clangInc = (Resolve-Path $cand).Path; break }
}
if (-not $clangInc) { throw '找不到 clang 资源头目录（build\Release\lib\clang\<ver>\include）—— 无法判定"绝不能 shadow"的那批名字' }
$clangNames = @(Get-ChildItem $clangInc -File | ForEach-Object { $_.Name })
Write-Host ("  clang 资源目录：{0}（{1} 个头）" -f $clangInc, $clangNames.Count)

$open = @($all | Where-Object { (Test-OpenSource $_.FullName) -and ($clangNames -notcontains $_.Name) })
$shadow = @($all | Where-Object { (Test-OpenSource $_.FullName) -and ($clangNames -contains $_.Name) })
$closed = @($all | Where-Object { -not (Test-OpenSource $_.FullName) })
Write-Host ("  总共 {0} 个；可抄 {1} 个；**不抄**：闭源编译器支撑头 {2} 个 + 会被我们 shadow 的 {3} 个" -f $all.Count, $open.Count, $closed.Count, $shadow.Count)
Write-Host ("  绝不 shadow 的：{0}" -f (($shadow | ForEach-Object { $_.Name }) -join ' '))
if ($open.Count -lt 100) { throw "只认出 $($open.Count) 个可抄头，判据可能失效（期望 ~173）—— 先人工核对再跑" }

if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null
$rows = @()
foreach ($f in $open) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dest $f.Name) -Force
    $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    $rows += ("{0}  {1}" -f $h, $f.Name)
}
$toolset = Split-Path (Split-Path $src -Parent) -Leaf
$header = @(
    "# MSVC STL 开源头（原样搬运，一个字节没改）",
    "#",
    "# 来源：$src",
    "# 工具集版本：$toolset",
    "# 抄取时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "# 抄取脚本：tools\vendor_msvc_stl.ps1",
    "# 许可：每个文件头自带 SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception",
    "#       （微软 STL 的开源许可；Apache-2.0 要求保留声明 —— 本目录就是原样保留）",
    "# 数量：$($open.Count) 个",
    "#",
    "# 没有搬的（三条理由，逐条可查）：",
    "#   a) 闭源 MSVC 编译器支撑头 $($closed.Count) 个（vcruntime*.h / sal.h / crtdefs.h / eh.h / amp*.h ...）",
    "#      —— 批2 用手搓等价物替代。",
    "#   b) 会被我们 shadow 的 $($shadow.Count) 个（clang 资源目录里也有同名）：",
    "#      $((($shadow | ForEach-Object { $_.Name }) -join ' '))",
    "#   c) _来源 / 内部件等不属于本目录的，本来就不在这里。",
    "#",
    "# 下面每行：<SHA256>  <文件名>   （-Check 模式逐个核对）",
    ""
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $dest 'SOURCE.txt'), $header + ($rows -join "`n") + "`n", $utf8)

$sz = [math]::Round((((Get-ChildItem $dest -File) | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host ("✅ 搬好：{0} 个文件 / {1} MB → {2}" -f $open.Count, $sz, $dest) -ForegroundColor Green
