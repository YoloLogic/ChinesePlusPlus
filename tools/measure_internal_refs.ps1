<#
  measure_internal_refs.ps1 —— 「动工前先把引用面量全」（方案 §16.51.1 的工具化）

  为什么要这个工具：
    §16.50 / §16.51 / §16.52 三次都是"抄下一个内部件时忘了跟上一层同步改名"，
    代价是一轮一个名字。判据已经写进方案：**先把引用面用 grep 量全，再一次性登记**。
    这个脚本就是把那次 grep 固化成一条命令，免得每换一个头就重新手写一遍正则。

  它输出两段（只读，不改任何产品）：

    【甲】本头引用了哪些**已经被我们汉化过**的名字 —— 这些是"必须同步"的：
          原头里写的英文名、我们某个条目给它定的中文名、以及是哪个条目定的。
          一个都不能漏：漏了就报「没有名为 X 的成员/类型」。

    【乙】本头**自己声明**的内部名（class/struct/using/typedef）还没进任何表的 ——
          这些是"本次要登记"的候选，也就是新条目 types 表的草稿。

  用法：
    pwsh -File tools\measure_internal_refs.ps1 -Header xstring
    pwsh -File tools\measure_internal_refs.ps1 -Header xstring -OnlyMissing   # 只看【乙】
    pwsh -File tools\measure_internal_refs.ps1 -Header xstring -MinCount 2   # 只看出现 >=2 次的
#>
param(
    [Parameter(Mandatory = $true)][string] $Header,
    [switch] $OnlyMissing,
    [int] $MinCount = 1
)

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$msvc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$tools = Join-Path $root 'tools'

$srcPath = Join-Path $msvc $Header
if (-not (Test-Path $srcPath)) { throw "找不到原头：$srcPath" }
$lines = [System.IO.File]::ReadAllLines($srcPath)
$text  = ($lines -join "`n")

# ---------------------------------------------------------------------------
#  1. 把三个生成器的表收成一张：英文名 -> @{ zh; owners }
#     ⚠ 用生成器自己的 -ExportJson（单一事实来源），不手写正则扫表 ——
#       扫正则会漂移，本项目已经栽过（§16.31 键名漏 `.`、§16.36 假残留）。
# ---------------------------------------------------------------------------
$table = @{}          # key = "kind/英文名"
function Add-Name([string]$kind, [string]$en, [string]$zh, [string]$owner) {
    $id = "$kind/$en"
    if (-not $table.ContainsKey($id)) { $table[$id] = @{ en = $en; zh = $zh; owners = @($owner) } }
    elseif ($table[$id].owners -notcontains $owner) { $table[$id].owners += $owner }
}
foreach ($gen in @('make_zhstdlib2.ps1', 'make_zhalias.ps1', 'make_zhc.ps1')) {
    $json = & pwsh -NoProfile -File (Join-Path $tools $gen) -ExportJson 2>$null
    if (-not $json) { continue }
    $obj = $json | ConvertFrom-Json
    foreach ($entry in $obj.PSObject.Properties) {
        $spec = $entry.Value
        $own  = if ($spec.PSObject.Properties.Name -contains 'zh') { [string]$spec.zh } else { $entry.Name }
        foreach ($kind in @('types', 'members', 'data')) {
            if (-not ($spec.PSObject.Properties.Name -contains $kind)) { continue }
            $m = $spec.$kind
            if (-not $m) { continue }
            foreach ($p in $m.PSObject.Properties) { Add-Name $kind $p.Name ([string]$p.Value) $own }
        }
    }
}

# ---------------------------------------------------------------------------
#  2.【甲】本头引用的、已被汉化过的名字
#     ⚠ 跳过 `#include` 行：那里的名字是文件名，不是标识符（§16.39 的坑）。
# ---------------------------------------------------------------------------
$body = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#\s*include') { continue }
    $body += $lines[$i]
}
$bodyText = ($body -join "`n")

$hit = @()
# ---------------------------------------------------------------------------
#  ⚠ 光数"出现过几次"没用（第一版就栽在这）：`_Elem` / `_Traits` / `_Alloc` /
#    `size_type` 这些高频命中大多是【本头自己的模板形参】和【本头自己声明的别名】，
#    它们跟"必须跟别的条目同步"毫无关系。所以每个命中要分三类：
#      · 模板形参   —— 本头 template <...> 里的名字 -> 本条目自己决定译名
#      · 本头声明   —— 本头 class/struct/using/typedef 出来的 -> 本条目自己翻
#      · 真借用     —— 本头既没声明、也不是形参 -> **这才是必须同步的清单**
# ---------------------------------------------------------------------------
$tparams = @{}
foreach ($m in [regex]::Matches($text, '(?s)template\s*<(.+?)>\s*(?=[^\s])')) {
    foreach ($t in [regex]::Matches($m.Groups[1].Value, '(?<![\w])(?:class|typename)\s+(_?\w+)')) {
        $tparams[$t.Groups[1].Value] = $true
    }
    foreach ($t in [regex]::Matches($m.Groups[1].Value, '(?<![\w])(?:(?:class|typename)\s+_?\w+\s*,\s*)?(_?\w+)\s+(_?\w+)\s*(?=[,>=])')) {
        $tparams[$t.Groups[2].Value] = $true      # 非类型形参：_Size_type _Max
    }
}
$declared = @{}
foreach ($m in [regex]::Matches($text, '(?m)^[ \t]*(?:template\s*<[^>]*>\s*)?(?:struct|class|union)\s+(_?\w+)')) {
    $n = $m.Groups[1].Value; if (-not $declared.ContainsKey($n)) { $declared[$n] = 'class/struct' }
}
foreach ($m in [regex]::Matches($text, '(?m)^[ \t]*using\s+(_?\w+)\s*=')) {
    $n = $m.Groups[1].Value; if (-not $declared.ContainsKey($n)) { $declared[$n] = 'using' }
}
foreach ($m in [regex]::Matches($text, '(?m)^[ \t]*typedef\s+.*?[ \t\*&](_?\w+)\s*;')) {
    $n = $m.Groups[1].Value; if (-not $declared.ContainsKey($n)) { $declared[$n] = 'typedef' }
}

foreach ($id in $table.Keys) {
    $en = $table[$id].en
    $rx = '(?<![\w])' + [regex]::Escape($en) + '(?![\w])'
    $c  = ([regex]::Matches($bodyText, $rx)).Count
    if ($c -lt [Math]::Max($MinCount, 1)) { continue }
    $cls = if ($tparams.ContainsKey($en)) { '模板形参' }
           elseif ($declared.ContainsKey($en)) { '本头声明' }
           else { '真借用★' }
    $hit += [pscustomobject]@{
        次数 = $c; 英文 = $en; 中文 = $table[$id].zh
        类   = $id.Split('/')[0]; 分类 = $cls; 既定于 = ($table[$id].owners -join '/')
    }
}

$borrowed = @($hit | Where-Object { $_.分类 -eq '真借用★' })
Write-Host ("=== 【甲】<$Header> 引用了 {0} 个已被汉化的名字；其中【真借用】{1} 个（必须同步）===" -f $hit.Count, $borrowed.Count) -ForegroundColor Cyan
if (-not $OnlyMissing) {
    $hit | Sort-Object -Property 次数 -Descending | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
}
Write-Host '  ↑ 只有【真借用★】那一类是本条目必须跟着改的；模板形参/本头声明由本条目自己定译名。' -ForegroundColor Yellow

# ---------------------------------------------------------------------------
#  3.【乙】本头自己声明、还没进任何表的内部名（新条目 types 表的草稿）
# ---------------------------------------------------------------------------
$skip = @('std', 'size_t', 'ptrdiff_t', 'true_type', 'false_type', 'void', 'int', 'char', 'bool')
$missing = @()
foreach ($n in ($declared.Keys | Sort-Object)) {
    if ($skip -contains $n) { continue }
    $known = $false
    foreach ($kind in @('types', 'members', 'data')) { if ($table.ContainsKey("$kind/$n")) { $known = $true; break } }
    if ($known) { continue }
    $rx = '(?<![\w])' + [regex]::Escape($n) + '(?![\w])'
    $missing += [pscustomobject]@{
        出现 = ([regex]::Matches($bodyText, $rx)).Count
        名字 = $n; 声明形式 = $declared[$n]
    }
}
Write-Host ("`n=== 【乙】<$Header> 自己声明、还没进任何表的内部名：{0} 个（本次要登记的候选）===" -f $missing.Count) -ForegroundColor Cyan
$missing | Sort-Object -Property 出现 -Descending | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host '注意：英文名带 `_` 前缀的一律要翻（§六第 6 条）；不带 `_` 的是公开名（top-level 类型/成员），按 §16.35.5 四类判据逐名判定。' -ForegroundColor Yellow
