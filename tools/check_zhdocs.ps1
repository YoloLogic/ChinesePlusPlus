# ============================================================================
#  check_zhdocs.ps1 —— §17.19.55 手写文档数字守卫（第 15 道）
#
#  为什么加它（2026-09-30，用户提问"我们的各种 md 文档有没有跟随更新？"）：
#    · 三本**自动生成**的台账（用法对照表 / 头文件覆盖台账 / 汉化标尺台账 / 边界台账）
#      每次提交都被守卫强制重生成并校验 —— 它们不会漂。
#    · 但**手写的 md** 没人守：实测 `docs\使用说明.md` 还写着"已有 67 个汉语头"（实际 103/103），
#      `docs\汉字第一公民-路线图.md` 还把标准库记成"❌ 全英文（最大缺口）、已暂缓"。
#    · 手写文档里的**数字**是唯一能用机器对拍的部分 —— 那就对拍。
#
#  判据：允许清单里的手写文档，凡出现下列数字，必须与台账一致：
#    ① `NN / 103`（标准头覆盖）           → 覆盖台账的分子
#    ② `NN 个汉语头`（旧口径）             → 覆盖台账的分子
#    ③ `顶层 A/B`、`嵌套 A/B`、`成员 A/B`  → 汉化标尺台账的分子/分母
#  允许清单之外的文档（尤其 `标准库汉化方案.md`：它**故意**保留历史数字）不检查。
#
#  自测：pwsh -File tools\check_zhdocs.ps1 -SelfTest
# ============================================================================
param([switch] $Check, [switch] $Quiet, [switch] $SelfTest)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
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

if ($SelfTest) {
    $fake = [pscustomobject]@{ 覆盖=103; 覆盖总=103; 顶层=@(388,422); 嵌套=@(363,419); 成员=@(1028,1196) }
    $pass = 0; $total = 4
    if ((Find-DocMismatch '标准头 103 / 103 全覆盖' $fake).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检1 正确数字被误报' -ForegroundColor Red }
    if ((Find-DocMismatch '已有 67 个汉语头' $fake).Count -eq 1) { $pass++ } else { Write-Host '  ❌ 自检2 漏报旧口径' -ForegroundColor Red }
    if ((Find-DocMismatch '顶层 269/444 = 60.6%' $fake).Count -eq 1) { $pass++ } else { Write-Host '  ❌ 自检3 漏报旧标尺' -ForegroundColor Red }
    if ((Find-DocMismatch 'cases=8  pass=2  same=6  fail=0' $fake).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检4 误报第三方 cases=8' -ForegroundColor Red }
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

$N = Get-LedgerNumbers
$bad = @()
foreach ($d in $docs) {
    $p = Join-Path $root $d
    if (-not (Test-Path $p)) { continue }
    foreach ($b in (Find-DocMismatch ([System.IO.File]::ReadAllText($p)) $N)) { $bad += ("  [{0}] {1}" -f $d, $b) }
}
if ($bad.Count) {
    Write-Host '❌ 手写文档数字与台账不一致（§17.19.55）：' -ForegroundColor Red
    $bad | Sort-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host '   修法：把过期数字改成台账里的当前值（台账由守卫自动生成，不许改台账）。' -ForegroundColor Yellow
    exit 1
}
if (-not $Quiet) { Write-Host ("  手写文档数字守卫：通过（覆盖 {0}/{1}、顶层 {2}/{3}、嵌套 {4}/{5}、成员 {6}/{7}；检查 {8} 个文档）" -f $N.覆盖, $N.覆盖总, $N.顶层[0], $N.顶层[1], $N.嵌套[0], $N.嵌套[1], $N.成员[0], $N.成员[1], $docs.Count) -ForegroundColor Green }
exit 0