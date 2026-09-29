# ============================================================================
#  check_multiowner.ps1 -- 「多方定义边界」守卫（§17.27.40）
#
#  判据（§17.27.40）：
#    一个名字要"全面汉化"，必须让【它所有的定义方】都归我们并改完。
#    只要还有定义方在借来的头里，这个名字就只能是"局部汉化 + 记边界" ——
#    强行在部分条目里改，必然出现"半边汉语、半边英文"（§17.27.10 实测）。
#
#  本工具做的事：
#    1. 从生成器里读出【我们拥有的头】（条目键 = MSVC 头名）；
#    2. 扫描全部 MSVC 内部头，得到每个名字的【定义方集合】
#       （判据：`名字 ( … ) [const] [noexcept] {` 形态 = 有函数体）；
#    3. 对【我们已登记的名字】逐个判定：
#         定义方 > 1 且其中有"不归我们的头"  ->  多方定义边界（注册它必然花脸）
#
#  用法： pwsh -File tools\check_multiowner.ps1 [-Quiet]
#  退出码：恒为 0 —— 这是【疑点清单】，不是门禁（见 §17.27.41）
# ============================================================================
param(
    [string] $Generator = (Join-Path $PSScriptRoot 'make_zhstdlib2.ps1'),
    [string] $VsInc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include',
    [switch] $Quiet,
    # §17.27.63 边界台账（B/D 桶）：生成物路径 + 过期检查
    [string] $LedgerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\标准库汉化\边界台账.md'),
    [switch] $Check
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Generator)) { throw "找不到生成器：$Generator" }
if (-not (Test-Path $VsInc)) { throw "找不到微软头目录：$VsInc" }

$g = [System.IO.File]::ReadAllText($Generator)

# ---- 1) 我们拥有的头 = 条目键 ----
$owned = @{}
foreach ($m in [regex]::Matches($g, "(?m)^\s*'([A-Za-z_0-9.]+)'\s*=\s*@\{\s*$")) { $owned[$m.Groups[1].Value] = $true }

# ---- 2) 我们已登记的名字（任何 '名字' = '…' 的键，只留合法标识符）----
$names = @{}
foreach ($m in [regex]::Matches($g, "'([A-Za-z_][A-Za-z0-9_]*)'[ \t]*=[ \t]*'")) { $names[$m.Groups[1].Value] = $true }

# ---- 3) 扫描每个头的"定义了哪些名字" ----
#   一次正则取"标识符紧跟 (…) 再跟 { "的形态，避免逐名字 × 逐文件的双重循环。
$definers = @{}
$defRx = [regex]'(?m)\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;{}]{0,240}?\)\s*(?:const)?\s*(?:noexcept)?\s*(?:/\*.*?\*/)?\s*\{'
foreach ($f in (Get-ChildItem $VsInc -File)) {
    $s = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($m in $defRx.Matches($s)) {
        $n = $m.Groups[1].Value
        if (-not $names.ContainsKey($n)) { continue }
        if (-not $definers.ContainsKey($n)) { $definers[$n] = @{} }
        $definers[$n][$f.Name] = $true
    }
}

# ---- 4) 判定 ----
$bad = @()
foreach ($n in $definers.Keys) {
    $d = @($definers[$n].Keys)
    if ($d.Count -le 1) { continue }                       # 单一定义方：不是多方边界
    $notOurs = @($d | Where-Object { -not $owned.ContainsKey($_) } | Sort-Object)
    if ($notOurs.Count -eq 0) { continue }                 # 定义方全是我们的：可以改
    $bad += [pscustomobject]@{ 名字 = $n; 定义方 = $d.Count; 不归我们 = ($notOurs -join ', ') }
}

if (-not $Quiet) {
    Write-Host ("多方定义边界检查（§17.27.40）：扫描 {0} 个头、我们登记 {1} 个名字；命中 {2} 条" -f `
        (Get-ChildItem $VsInc -File).Count, $names.Count, $bad.Count)
    foreach ($b in ($bad | Sort-Object 名字)) {
        Write-Host ("  ⚠ {0} —— 定义方 {1} 个，其中不归我们的：{2}" -f $b.名字, $b.定义方, $b.不归我们)
    }
    if ($bad.Count -eq 0) { Write-Host "  没有多方定义边界式登记" -ForegroundColor Green }
}

# 只报告，不作门禁（§17.27.41）

# ---------------------------------------------------------------------------
#  §17.27.41 为什么只报告、不作门禁：
#    判据方向是对的（§17.27.40），但【粒度太粗】：size/begin/clear/swap 这类名字在 std 各处都有定义，
#    而我们改的是"自己拷贝里那个类的成员" —— 合法。首跑 122 条里绝大多数属此类。
#    真正该问的是 §16.53 的那个问题：**这个调用点上，实例属于谁？**（谁定义的不重要）
#    所以本工具定位为【triage 辅助】：给出"名字 × 定义方"的分布，供进一步判定。
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
#  §17.27.42 四类分桶（可改 / 边界 两张表的来源）
#    A 单一定义方 且归我们      -> 可直接改
#    B 单一定义方 但不归我们    -> 边界（定义在借来的头里）
#    C 多定义方 且全归我们      -> 可链式改（我方组件之间）
#    D 多定义方 且含不归我们的  -> 边界（多方定义）
# ---------------------------------------------------------------------------
$cats = [ordered]@{ 'A 单一定义方·我们的' = @(); 'B 单一定义方·借来的' = @(); 'C 多定义方·全是我们的' = @(); 'D 多定义方·含借来的' = @(); 'E 无函数体定义（宏/变量/typedef）' = @() }
foreach ($n in $names.Keys) {
    if (-not $definers.ContainsKey($n)) { $cats['E 无函数体定义（宏/变量/typedef）'] += $n; continue }
    $d = @($definers[$n].Keys)
    $notOurs = @($d | Where-Object { -not $owned.ContainsKey($_) } | Sort-Object)
    if ($d.Count -eq 1) { if ($notOurs.Count -eq 0) { $cats['A 单一定义方·我们的'] += $n } else { $cats['B 单一定义方·借来的'] += $n } }
    else { if ($notOurs.Count -eq 0) { $cats['C 多定义方·全是我们的'] += $n } else { $cats['D 多定义方·含借来的'] += $n } }
}
Write-Host ''
Write-Host '=== §17.27.42 四类分桶（我们登记过的名字）==='
$bucketDir = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'build'
foreach ($k in $cats.Keys) {
    $v = @($cats[$k] | Sort-Object)
    Write-Host ("  {0,-32} {1,5} 个{2}" -f $k, $v.Count, $(if ($v.Count) { '   例：' + (($v | Select-Object -First 8) -join ' ') } else { '' }))
    # -----------------------------------------------------------------------
    #  §17.27.62 导出四张表（阶段(3) 的【工作表】）——
    #  动机：分桶判据一直只打在屏幕上（每次滚过去就没了），而阶段(3) 是**按桶成批做**，
    #  批量作业需要一份【可 diff、可核对数量】的清单。判据：**判据要能变成工作表**，
    #  否则"按桶推进"实际还是靠人肉回忆。
    #  ⚠ 只写 build\（不进版本库）；每行一个名字，另起一行写定义方/不归我们的，便于销账。
    # -----------------------------------------------------------------------
    if (-not (Test-Path $bucketDir)) { New-Item -ItemType Directory -Force $bucketDir | Out-Null }
    $letter = ($k -split ' ')[0]
    $out = @("# $k", "# 生成：tools\check_multiowner.ps1（§17.27.42/§17.27.62）—— 只报告，不作门禁")
    foreach ($n in $v) {
        $line = "  $n"
        if ($definers.ContainsKey($n)) {
            $d = @($definers[$n].Keys)
            $notOurs = @($d | Where-Object { -not $owned.ContainsKey($_) } | Sort-Object)
            $line += ("    # 定义方 {0} 个{1}" -f $d.Count, $(if ($notOurs.Count) { '，不归我们的：' + ($notOurs -join ', ') } else { '' }))
        }
        $out += $line
    }
    [System.IO.File]::WriteAllLines((Join-Path $bucketDir ("bucket_$letter.txt")), $out, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host ("  工作表已导出到 {0}\bucket_[ABCDE].txt（§17.27.62：判据要能变成工作表）" -f $bucketDir) -ForegroundColor Gray

# ---------------------------------------------------------------------------
#  §17.27.63 边界台账（B/D 桶）—— 【生成物】+ 过期检查
#
#  为什么还要一份台账：§17.27.42 判出了四类桶，但 B/D（= 边界）一直只打在屏幕上，
#  **屏幕上的东西滚过去就没了**。而边界台账是"欠账的登记表"：它必须可 diff、可核对数量、
#  可被门禁检查 —— 否则"记了"只是"我以为记了"。
#  判据同 §16.40（用法对照表）：**手写的登记表一定会漂移，所以要由机器生成、由机器核对。**
# ---------------------------------------------------------------------------
$mkd = New-Object System.Collections.ArrayList
[void]$mkd.Add('# 边界台账（B 桶 / D 桶）')
[void]$mkd.Add('')
[void]$mkd.Add('> **本文件是生成物**，手改无效。生成：`pwsh -File tools\check_multiowner.ps1`；')
[void]$mkd.Add('> 过期检查由 `tools\regen_zhstdlib.ps1` 执行（同"用法对照表守卫"的做法）。')
[void]$mkd.Add('>')
[void]$mkd.Add('> **边界的含义**：这个名字在【借来的头】里也有定义方。所以在我们把那个头也抄下来之前，')
[void]$mkd.Add('> **两侧都必须保持英文** —— 这是 §17.27.43 用两侧实验夹出来的结论，不是保守。')
[void]$mkd.Add('')
$totalNames = (($cats.Values | ForEach-Object { @($_).Count } | Measure-Object -Sum).Sum)
$bNames = @($cats['B 单一定义方·借来的'] | Sort-Object)
$dNames = @($cats['D 多定义方·含借来的'] | Sort-Object)
[void]$mkd.Add(("**指纹**：B 桶 {0} 个 / D 桶 {1} 个（我们登记的名字共 {2} 个；生成时扫描 {3} 个头）" -f `
    $bNames.Count, $dNames.Count, $totalNames, (Get-ChildItem $VsInc -File).Count))
[void]$mkd.Add('')
[void]$mkd.Add('## B 桶：单一定义方 · 借来的')
[void]$mkd.Add('')
[void]$mkd.Add('消除路径：**把那个借用头也抄成我们的内部件**（抄完即变成 A 桶，可整批翻）。')
[void]$mkd.Add('')
[void]$mkd.Add('| 名字 | 借来的定义方 | 消除路径 |')
[void]$mkd.Add('| --- | --- | --- |')
foreach ($n in $bNames) {
    $notOurs = @($definers[$n].Keys | Where-Object { -not $owned.ContainsKey($_) } | Sort-Object)   # 排序：台账必须可复现（哈希表枚举顺序不稳定）
    [void]$mkd.Add(("| ``{0}`` | {1} | 抄 ``{2}`` |" -f $n, ($notOurs -join ', '), ($notOurs -join '`` / ``')))
}
[void]$mkd.Add('')
[void]$mkd.Add('## D 桶：多定义方 · 含借来的')
[void]$mkd.Add('')
[void]$mkd.Add('消除路径：**抄完所有借用定义方后整批翻**（在那之前保持英文）。')
[void]$mkd.Add('')
[void]$mkd.Add('| 名字 | 借来的定义方 | 我方定义方数 | 消除路径 |')
[void]$mkd.Add('| --- | --- | --- | --- |')
foreach ($n in $dNames) {
    $all = @($definers[$n].Keys | Sort-Object)
    $notOurs = @($all | Where-Object { -not $owned.ContainsKey($_) })
    $ours = @($all | Where-Object { $owned.ContainsKey($_) } | Sort-Object)
    [void]$mkd.Add(("| ``{0}`` | {1} | {2} | 抄完借用方后整批翻 |" -f $n, ($notOurs -join ', '), $ours.Count))
}
$mkdText = ($mkd -join "`r`n") + "`r`n"
if ($Check) {
    $old = if (Test-Path $LedgerPath) { [System.IO.File]::ReadAllText($LedgerPath) } else { '' }
    if ($old.Replace("`r`n", "`n") -eq $mkdText.Replace("`r`n", "`n")) {
        Write-Host ("边界台账：最新（B {0} / D {1}）" -f $bNames.Count, $dNames.Count)
        exit 0
    } else {
        Write-Host ("❌ 边界台账【已过期】：{0}" -f $LedgerPath) -ForegroundColor Red
        Write-Host "   修法：pwsh -File tools\check_multiowner.ps1  然后一起提交。" -ForegroundColor Yellow
        exit 1
    }
} else {
    $ldir = Split-Path -Parent $LedgerPath
    if (-not (Test-Path $ldir)) { New-Item -ItemType Directory -Force $ldir | Out-Null }
    [System.IO.File]::WriteAllText($LedgerPath, $mkdText, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  边界台账已写入 {0}（B {1} / D {2}）" -f $LedgerPath, $bNames.Count, $dNames.Count) -ForegroundColor Gray
}