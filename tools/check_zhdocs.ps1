# ============================================================================
#  check_zhdocs.ps1 —— §17.19.55 手写文档数字守卫（第 15 道）
#
#  为什么加它（2026-09-30，用户提问"我们的各种 md 文档有没有跟随更新？"）：
#    · 五本**自动生成**的台账（用法对照表 / 头文件覆盖台账 / 汉化标尺台账 / 边界台账 / C 库汉化台账）
#      每次提交都被守卫强制重生成并校验 —— 它们不会漂。
#    · 但**手写的 md** 没人守：实测 `docs\使用说明.md` 还写着"已有 67 个汉语头"（实际 103/103），
#      `docs\汉字第一公民-路线图.md` 还把标准库记成"❌ 全英文（最大缺口）、已暂缓"。
#    · 手写文档里的**数字**是唯一能用机器对拍的部分 —— 那就对拍。
#
#  判据：允许清单里的手写文档，凡出现下列数字，必须与台账一致：
#    ① `NN / 103`（标准头覆盖）           → 覆盖台账的分子
#    ② `NN 个汉语头`（旧口径）             → 覆盖台账的分子
#    ③ `顶层 A/B`、`嵌套 A/B`、`成员 A/B`  → 汉化标尺台账的分子/分母
#    ④ `产物 N 个`、`N 个头`、`N 个中文头`  → 生成的用法台账（`共 N 个中文头`）+ 实际文件数
#    ⑤ `N 道守卫`（**不带"第"**；"第 14 道"是具体道号，不判）→ 闸门声明的 `$守卫道数`
#    ⑥ `N 项自测`、`verify.ps1 … N 项`      → `packaging\verify.ps1` 里的 $expectedChecks
#    ⑦ `第 N 道` 里的 N 必须 ≤ 最大道号（26）→ 防"引用了不存在的道号"
#    ⑧ `C 线头数 N`、`C 线中文名 N`、`C 线逻辑缺口 N` → **生成的** C 库汉化台账
#       （`docs\标准库汉化\C库汉化台账.md`，它自己由第 29 道守卫复算，见 §18.58）
#  允许清单之外的文档（尤其 `标准库汉化方案.md`：它**故意**保留历史数字）不检查。
#
#  为什么加 ④⑤⑥⑦（2026-10-06，§18.47）：
#    v0.2 重打包时暴露出**一整类没人守的数字** —— `产物 116 个`（实际 119）、
#    `26 道守卫`（实际 16 道，把最大道号当成了道数）、`verify.ps1 17 项`（实际 21 项）、
#    `windows系统\ 2`（实际 3）。老守卫只管覆盖数与标尺，这类"库存数字"全靠人记得。
#    三条新规则各有**真来源**：④ 生成的用法台账 + `zhstdlib\` 实际文件数；
#    ⑤ 闸门自己声明的 `$守卫道数`（**道数 16 ≠ 最大道号 26**，口径写在那行注释里）；
#    ⑥ `packaging\verify.ps1` 的 `$expectedChecks`（它跑完自证）。⇒ 不是又抄一遍数字。
#
#  自测：pwsh -File tools\check_zhdocs.ps1 -SelfTest
# ============================================================================
param([switch] $Check, [switch] $Quiet, [switch] $SelfTest)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')
$zhInc = Get-ZhIncludeArgs $root
$docs = @('README.md', 'docs\README.md', 'docs\使用说明.md', 'docs\汉字第一公民-路线图.md',
          'third_party\README.md', 'docs\宣传\介绍-面向投资者与合作方.md', 'docs\宣传\介绍-面向非技术读者.md',
          'packaging\常见问题.md', 'packaging\中文对照表.md')

function Get-LedgerNumbers {
    $cov = [System.IO.File]::ReadAllText((Join-Path $root 'docs\标准库汉化\头文件覆盖台账.md'))
    $led = [System.IO.File]::ReadAllText((Join-Path $root 'docs\标准库汉化\汉化标尺台账.md'))
    $c = [regex]::Match($cov, '已覆盖\s*(\d+)\s*/\s*(?:标准头\s*)?(\d+)')
    $t = [regex]::Match($led, '\| 顶层类型名 \| (\d+) \| (\d+) \|')
    $n = [regex]::Match($led, '\| 嵌套名 \| (\d+) \| (\d+) \|')
    $m = [regex]::Match($led, '\| 成员名 \| (\d+) \| (\d+) \|')
    if (-not ($c.Success -and $t.Success -and $n.Success -and $m.Success)) { throw '台账格式变了：取不到数字（守卫要先校准，见 §16.65.1b）' }
    return [pscustomobject]@{
        覆盖     = [int]$c.Groups[1].Value; 覆盖总 = [int]$c.Groups[2].Value
        顶层 = @([int]$t.Groups[1].Value, [int]$t.Groups[2].Value)
        嵌套 = @([int]$n.Groups[1].Value, [int]$n.Groups[2].Value)
        成员 = @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value)
    }
}

function Find-DocMismatch($text, $N) {
    $bad = @()
    foreach ($mm in [regex]::Matches($text, '(\d+)\s*/\s*(\d+)')) {
        $a = [int]$mm.Groups[1].Value; $b = [int]$mm.Groups[2].Value
        if ($b -eq $N.覆盖总 -and $a -ne $N.覆盖) { $bad += ("写了 {0}/{1}，覆盖台账是 {2}/{3}" -f $a, $b, $N.覆盖, $N.覆盖总) }
    }
    foreach ($mm in [regex]::Matches($text, '(\d+)\s*个汉语头')) {
        if ([int]$mm.Groups[1].Value -ne $N.覆盖) { $bad += ("写了' {0} 个汉语头'（旧口径），覆盖台账是 {1} 个标准头" -f $mm.Groups[1].Value, $N.覆盖) }
    }
    foreach ($pair in @(@('顶层', $N.顶层), @('嵌套', $N.嵌套), @('成员', $N.成员))) {
        foreach ($mm in [regex]::Matches($text, ($pair[0] + '\s*(\d+)\s*/\s*(\d+)'))) {
            $a = [int]$mm.Groups[1].Value; $b = [int]$mm.Groups[2].Value
            if ($a -ne $pair[1][0] -or $b -ne $pair[1][1]) { $bad += ("写了 {0} {1}/{2}，标尺台账是 {3}/{4}" -f $pair[0], $a, $b, $pair[1][0], $pair[1][1]) }
        }
    }
    return $bad
}

function Get-InventoryNumbers {
    # ④ 产物数：以**生成的**用法台账为准，再与实际文件数对拍（两者不一致本身就判红）
    $usage = [System.IO.File]::ReadAllText((Join-Path $root 'docs\标准库汉化\汉语标准库-用法.md'))
    $m = [regex]::Match($usage, '共\s*(\d+)\s*个中文头')
    if (-not $m.Success) { throw '用法台账格式变了：取不到「共 N 个中文头」（守卫要先校准，见 §18.47）' }
    $ledger = [int]$m.Groups[1].Value
    $actual = @(Get-ChildItem (Join-Path $root 'zhstdlib') -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($actual -ne $ledger) {
        throw ("产物台账与实际不符：用法台账写 {0} 个，`zhstdlib\` 里实际 {1} 个（先重生成台账）" -f $ledger, $actual)
    }
    # ⑤ 守卫道数：**唯一事实来源** = 闸门自己声明的 `$守卫道数`（在 regen_zhstdlib.ps1 里，紧挨着本守卫的调用处）。
    #    为什么不自动数：本仓的"道" = **带道号的编号守卫**（9、10、13、14–26 共 16 个；11/12 已并号），
    #    而闸门完整环节有 22 个（含用法对照表 / 边界台账 / 孤儿产物 / 公开层转发 … 它们**没有道号**）。
    #    自动数"调用行"会把 `-SelfTest` 那一行也数进去；自动数"道号"又会漏掉只在别处标号的 9/10/13。
    #    ⇒ 让闸门声明一个数、守卫盯住"声明与文档一致"，比自动猜更准（口径就写在那一行注释里）。
    $regen = [System.IO.File]::ReadAllText((Join-Path $root 'tools\regen_zhstdlib.ps1'))
    $g = [regex]::Match($regen, '\$守卫道数\s*=\s*(\d+)')
    if (-not $g.Success) { throw '取不到 $守卫道数（闸门的道数声明没了？见 §18.47）' }
    $guards = [int]$g.Groups[1].Value
    if ($guards -le 0) { throw '闸门声明的道数不是正数（见 §18.47）' }
    # ⑦ 道号上限：**道数 ≠ 最大道号**（本仓 16 道、道号一直编到 26：第 9/10/13 道另在别处标号）
    $nums = [regex]::Matches($regen, '第\s*(\d+)\s*道') | ForEach-Object { [int]$_.Groups[1].Value }
    if (-not $nums) { throw '取不到道号（regen 里的「第 N 道」都掉了？见 §18.47）' }
    $maxNo = ($nums | Measure-Object -Maximum).Maximum
    if ($maxNo -lt $guards) { throw ("道号上限 {0} 小于道数 {1}：编号乱了（见 §18.47）" -f $maxNo, $guards) }
    # ⑥ 自测项数：verify.ps1 自己声明并在跑完时自证
    $ver = [System.IO.File]::ReadAllText((Join-Path $root 'packaging\verify.ps1'))
    $v = [regex]::Match($ver, '\$expectedChecks\s*=\s*(\d+)')
    if (-not $v.Success) { throw '取不到 $expectedChecks（verify.ps1 的写法变了，见 §18.47）' }
    # ⑧ C 线数字：**唯一事实来源** = 生成的 `C库汉化台账.md`（第 29 道守卫 `make_c_ledger.ps1 -Check` 复算它）。
    #    这里只做"手写文档 ↔ 台账"对拍，**不重算** —— 重算一次要读 26 个头的源码，没必要跑两遍。
    $clFile = Join-Path $root 'docs\标准库汉化\C库汉化台账.md'
    $clText = [System.IO.File]::ReadAllText($clFile)
    $ch = [regex]::Match($clText, '共\s*\*{0,2}(\d+)\*{0,2}\s*个头')
    $ct = [regex]::Match($clText, '\|\s*\*{0,2}合计\*{0,2}\s*\|[^|]*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|[^|]*\|[^|]*\|\s*\*{0,2}(\d+)\*{0,2}\s*\|')
    if (-not ($ch.Success -and $ct.Success)) { throw 'C 库汉化台账格式变了：取不到「共 N 个头」或合计行（守卫要先校准，见 §18.58）' }
    $cNames = [int]$ct.Groups[4].Value; $cGap = [int]$ct.Groups[5].Value
    if ($cNames -ne ([int]$ct.Groups[1].Value + [int]$ct.Groups[2].Value + [int]$ct.Groups[3].Value)) {
        throw 'C 库汉化台账合计行自相矛盾（类型+函数+值宏 ≠ 合计）；先重生成台账（见 §18.58）'
    }
    return [pscustomobject]@{ 产物 = $ledger; 守卫 = $guards; 道号上限 = $maxNo; 自测 = [int]$v.Groups[1].Value
                             C头 = [int]$ch.Groups[1].Value; C中文名 = $cNames; C缺口 = $cGap }
}

function Find-InventoryMismatch($text, $inv) {
    $bad = @()
    # ④ 产物数（三种写法）
    foreach ($mm in [regex]::Matches($text, '产物\s*\*{0,2}(\d+)\*{0,2}\s*个')) {
        if ([int]$mm.Groups[1].Value -ne $inv.产物) { $bad += ("写了'产物 {0} 个'，实际产物 {1} 个" -f $mm.Groups[1].Value, $inv.产物) }
    }
    foreach ($mm in [regex]::Matches($text, '(?<!\d)(\d+)\s*个头(?![文件])')) {
        if ([int]$mm.Groups[1].Value -ne $inv.产物) { $bad += ("写了'{0} 个头'，实际产物 {1} 个" -f $mm.Groups[1].Value, $inv.产物) }
    }
    foreach ($mm in [regex]::Matches($text, '(?<!\d)(\d+)\s*个中文头')) {
        if ([int]$mm.Groups[1].Value -ne $inv.产物) { $bad += ("写了'{0} 个中文头'，实际产物 {1} 个" -f $mm.Groups[1].Value, $inv.产物) }
    }
    # ⑤ 守卫道数（带"第"的是具体道号，交给 ⑦）
    foreach ($mm in [regex]::Matches($text, '(?<!\d)(?<!第 )(\d+)\s*道守卫')) {
        if ([int]$mm.Groups[1].Value -ne $inv.守卫) { $bad += ("写了'{0} 道守卫'，闸门实际 {1} 道" -f $mm.Groups[1].Value, $inv.守卫) }
    }
    # ⑥ 自测项数
    foreach ($mm in [regex]::Matches($text, '(?<!\d)(\d+)\s*项自测')) {
        if ([int]$mm.Groups[1].Value -ne $inv.自测) { $bad += ("写了'{0} 项自测'，verify.ps1 是 {1} 项" -f $mm.Groups[1].Value, $inv.自测) }
    }
    foreach ($mm in [regex]::Matches($text, 'verify\.ps1[^\r\n]{0,30}?(\d+)\s*项')) {
        if ([int]$mm.Groups[1].Value -ne $inv.自测) { $bad += ("写了'verify.ps1 … {0} 项'，verify.ps1 是 {1} 项" -f $mm.Groups[1].Value, $inv.自测) }
    }
    # ⑦ 具体道号不许超过最大道号（防"引用了不存在的道号"）
    foreach ($mm in [regex]::Matches($text, '第\s*(\d+)\s*道')) {
        if ([int]$mm.Groups[1].Value -gt $inv.道号上限) { $bad += ("写了'第 {0} 道'，但道号最大只到 {1}" -f $mm.Groups[1].Value, $inv.道号上限) }
    }
    # ⑧ C 线三个数字（口径写在 C 库汉化台账里；**必须带 `C 线…` 前缀**才判，
    #    否则会去咬标准库那边的"146 个中文名"之类无关数字）
    foreach ($mm in [regex]::Matches($text, 'C\s*线头数\s*\*{0,2}(\d+)')) {
        if ([int]$mm.Groups[1].Value -ne $inv.C头) { $bad += ("写了'C 线头数 {0}'，C 库台账是 {1} 个" -f $mm.Groups[1].Value, $inv.C头) }
    }
    foreach ($mm in [regex]::Matches($text, 'C\s*线中文名\s*\*{0,2}(\d+)')) {
        if ([int]$mm.Groups[1].Value -ne $inv.C中文名) { $bad += ("写了'C 线中文名 {0}'，C 库台账是 {1} 个" -f $mm.Groups[1].Value, $inv.C中文名) }
    }
    foreach ($mm in [regex]::Matches($text, 'C\s*线逻辑缺口\s*\*{0,2}(\d+)')) {
        if ([int]$mm.Groups[1].Value -ne $inv.C缺口) { $bad += ("写了'C 线逻辑缺口 {0}'，C 库台账是 {1} 个" -f $mm.Groups[1].Value, $inv.C缺口) }
    }
    return $bad
}

if ($SelfTest) {
    $fake = [pscustomobject]@{ 覆盖=103; 覆盖总=103; 顶层=@(388,422); 嵌套=@(363,419); 成员=@(1028,1196) }
    $inv = [pscustomobject]@{ 产物=119; 守卫=16; 道号上限=26; 自测=21; C头=26; C中文名=146; C缺口=211 }
    $pass = 0; $total = 14
    if ((Find-DocMismatch '标准头 103 / 103 全覆盖' $fake).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检1 正确数字被误报' -ForegroundColor Red }
    if ((Find-DocMismatch '已有 67 个汉语头' $fake).Count -eq 1) { $pass++ } else { Write-Host '  ❌ 自检2 漏报旧口径' -ForegroundColor Red }
    if ((Find-DocMismatch '顶层 269/444 = 60.6%' $fake).Count -eq 1) { $pass++ } else { Write-Host '  ❌ 自检3 漏报旧标尺' -ForegroundColor Red }
    if ((Find-DocMismatch 'cases=8  pass=2  same=6  fail=0' $fake).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检4 误报第三方 cases=8' -ForegroundColor Red }
    # ---- §18.47 库存数字（④⑤⑥⑦）：每条都要有"对的不误报 + 错的必须报" ----
    if ((Find-InventoryMismatch '产物 **119** 个' $inv).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检5 正确产物数被误报' -ForegroundColor Red }
    if ((Find-InventoryMismatch '（产物 116 个）' $inv).Count -eq 1) { $pass++ } else { Write-Host '  ❌ 自检6 漏报过期产物数' -ForegroundColor Red }
    if ((Find-InventoryMismatch '总判据（**16 道守卫**）每次提交都跑' $inv).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检7 正确守卫道数被误报' -ForegroundColor Red }
    if ((Find-InventoryMismatch '四轨生成器 + 14 道守卫' $inv).Count -eq 1) { $pass++ } else { Write-Host '  ❌ 自检8 漏报过期守卫道数' -ForegroundColor Red }
    if ((Find-InventoryMismatch '第 14 道守卫每次提交跑' $inv).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检9 把具体道号「第 14 道」误当成道数' -ForegroundColor Red }
    if (((Find-InventoryMismatch '第 26 道守卫' $inv).Count -eq 0) -and ((Find-InventoryMismatch '第 30 道' $inv).Count -eq 1)) { $pass++ } else { Write-Host '  ❌ 自检10 道号上限没判对' -ForegroundColor Red }
    if (((Find-InventoryMismatch '21 项自测全过' $inv).Count -eq 0) -and ((Find-InventoryMismatch '17 项自测' $inv).Count -eq 1) -and
        ((Find-InventoryMismatch 'verify.ps1`（**21 项**）' $inv).Count -eq 0) -and ((Find-InventoryMismatch 'verify.ps1`（**17 项**）' $inv).Count -eq 1)) { $pass++ } else { Write-Host '  ❌ 自检11 自测项数没判对' -ForegroundColor Red }
    if (((Find-InventoryMismatch '（119 个头，2.7 MB）' $inv).Count -eq 0) -and ((Find-InventoryMismatch '（118 个头）' $inv).Count -eq 1) -and
        ((Find-InventoryMismatch '包里有 12 个头文件' $inv).Count -eq 0)) { $pass++ } else { Write-Host '  ❌ 自检12 头数口径没判对（个头 / 个头文件 / 个中文头）' -ForegroundColor Red }
    # ---- §18.58 C 线数字（⑧）：对的不误报 + 错的必须报 ----
    if (((Find-InventoryMismatch 'C 线头数 26、C 线中文名 146、C 线逻辑缺口 211' $inv).Count -eq 0)) { $pass++ } else { Write-Host '  ❌ 自检13 正确 C 线数字被误报' -ForegroundColor Red }
    if (((Find-InventoryMismatch 'C 线中文名 196' $inv).Count -eq 1) -and ((Find-InventoryMismatch 'C 线逻辑缺口 197' $inv).Count -eq 1) -and
        ((Find-InventoryMismatch '标准库有 146 个中文名' $inv).Count -eq 0)) { $pass++ } else { Write-Host '  ❌ 自检14 C 线过期数字没判对（或误咬不带 C 线前缀的句子）' -ForegroundColor Red }
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

$N = Get-LedgerNumbers
$inv = Get-InventoryNumbers
$bad = @()
foreach ($d in $docs) {
    $p = Join-Path $root $d
    if (-not (Test-Path $p)) { continue }
    $txt = [System.IO.File]::ReadAllText($p)
    foreach ($b in (Find-DocMismatch $txt $N)) { $bad += ("  [{0}] {1}" -f $d, $b) }
    foreach ($b in (Find-InventoryMismatch $txt $inv)) { $bad += ("  [{0}] {1}" -f $d, $b) }
}
if ($bad.Count) {
    Write-Host '❌ 手写文档数字与台账不一致（§17.19.55）：' -ForegroundColor Red
    $bad | Sort-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host '   修法：把过期数字改成台账里的当前值（台账由守卫自动生成，不许改台账）。' -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
#  §17.19.60 文档代码块编译守卫：README / 使用说明 里的 ```cpp 块必须真能编过。
#  为什么加它（2026-09-30 外部复核）：README 首页示例写着 `标准::输出 << 标准::换行;`
#  —— 这两个名字在 116 个产物里**根本不存在**，而且没有 `#包含`；读者照抄就报错。
#  `examples\汉语库示例.cpp` 在总判据里会被编，**README 里的示例不在**，所以可以长期是错的。
#  判据：允许清单文档里的每个 ```cpp 块，用发行编译器 `-std=c++20 -isystem zhstdlib -fsyntax-only` 编一遍；
#        想跳过就写 ```cpp 不编译（用于"故意展示错误"的片段）。
# ---------------------------------------------------------------------------
$cxx = Join-Path $root 'build\Release\bin\chinese++.exe'
$outDir = Join-Path $root 'build\_zhdocs'
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force $outDir | Out-Null
$blkBad = @(); $blkOK = 0; $blkSkip = 0
foreach ($d in $docs) {
    $p = Join-Path $root $d
    if (-not (Test-Path $p)) { continue }
    $txt = [System.IO.File]::ReadAllText($p)
    $i = 0
    foreach ($m in [regex]::Matches($txt, '(?s)```cpp([^\r\n]*)\r?\n(.*?)```')) {
        $i++
        if ($m.Groups[1].Value -match '不编译') { $blkSkip++; continue }
        # 校准（§17.19.60）：只查 README（门面，一律查）与【含 主函数】的完整程序；
        #   文档里大量"语法片段"（只有几行、或故意展示旧写法）不该被要求能编译 —— 假报会逼人加噪声标注。
        if ($d -ne 'README.md' -and $m.Groups[2].Value -notmatch '主函数') { $blkSkip++; continue }
        $blkFile = Join-Path $outDir ("blk_{0}_{1}.cpp" -f ($d -replace '[\\/\.]', '_'), $i)
        [System.IO.File]::WriteAllText($blkFile, $m.Groups[2].Value, (New-Object System.Text.UTF8Encoding($false)))
        & cmd /c "`"$cxx`" -std=c++20 $zhInc -I`"$root\examples`" -fsyntax-only `"$blkFile`" > `"$outDir\o.txt`" 2>&1"
        if ($LASTEXITCODE -eq 0) { $blkOK++ }
        else {
            $err = (Get-Content "$outDir\o.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' } | Select-Object -First 1)
            $blkBad += ("  [{0} 第 {1} 个 cpp 块] {2}" -f $d, $i, ([string]$err).Trim())
        }
    }
}
if ($blkBad.Count) {
    Write-Host '❌ 文档里的代码块编不过（§17.19.60）—— 读者会照抄：' -ForegroundColor Red
    $blkBad | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host '   修法：把示例改成能编过的（或用 ```cpp 不编译 明确标注"这是错的示例"）。' -ForegroundColor Yellow
    exit 1
}
if (-not $Quiet) { Write-Host ("  文档代码块编译守卫：通过（编过 {0} 块，跳过 {1} 块）" -f $blkOK, $blkSkip) -ForegroundColor Green }
if (-not $Quiet) { Write-Host ("  手写文档数字守卫：通过（覆盖 {0}/{1}、顶层 {2}/{3}、嵌套 {4}/{5}、成员 {6}/{7}；产物 {8} 个、守卫 {9} 道（道号到 {10}）、自测 {11} 项；C 线 {12} 头 / 中文名 {13} / 逻辑缺口 {14}；检查 {15} 个文档）" -f $N.覆盖, $N.覆盖总, $N.顶层[0], $N.顶层[1], $N.嵌套[0], $N.嵌套[1], $N.成员[0], $N.成员[1], $inv.产物, $inv.守卫, $inv.道号上限, $inv.自测, $inv.C头, $inv.C中文名, $inv.C缺口, $docs.Count) -ForegroundColor Green }
exit 0