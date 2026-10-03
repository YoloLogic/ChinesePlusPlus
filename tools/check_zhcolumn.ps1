# ============================================================================
#  诊断列号口径守卫（§18.5：大检查 P-02 的回归判据）
#
#  背景（台账 P-02）：`文件:行:列` 里的列号一直是 **SourceManager 的字节偏移**。
#  汉语源码里一个汉字 3 个字节 ⇒ 报出来的数字既不是用户数出来的字符序，也不是
#  终端上的显示列。实测同一行：**字节 81 / 字符序 37 / 显示列 59**。
#  （插入符本身一直是对的 —— 它按显示宽度画。错的是这个数字，别一起改坏。）
#
#  判据（四条，全都要成立）：
#    ① 同一个错误位置，三种单位给出**三个不同的数**，且分别等于探针算出来的期望
#       —— 三者相等就说明探针没有区分力，守卫**直接判失败**
#       （项目纪律：跑 0 条的通过不是通过）。
#    ② 不写开关时 == `display`（默认口径）。
#    ③ 插入符的落点 == **显示列** —— 它本来就是对的，修列号时不许改坏。
#    ④ 纯英文行：三种单位必须相同（英文源码不该有任何变化）。
#  自带自测：期望值计算必须能区分三种口径（构造 ASCII 行必须三值相等）。
#
#  跑法：pwsh -NoProfile -File tools\check_zhcolumn.ps1
#  退出码：0 = 全对；1 = 有不对的（或自测/区分力检查失败）
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$exe  = Join-Path $Root 'build\Release\bin\chinese++.exe'
$work = Join-Path $Root 'build\_zhcolumn'
New-Item -ItemType Directory -Force $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }

if (-not (Test-Path $exe)) { 错 "找不到编译器：$exe"; exit 1 }

# ---- 期望值：给定一行与行内目标记号，算出三种口径的列（1 基）---------------
function 期望列([string]$行, [string]$目标) {
    $i = $行.IndexOf($目标)
    if ($i -lt 0) { return $null }
    $前缀 = $行.Substring(0, $i)
    $字节 = [System.Text.Encoding]::UTF8.GetByteCount($前缀) + 1
    $字符 = $i + 1
    $显示 = 1
    for ($k = 0; $k -lt $i; $k++) { $显示 += if ([int][char]$行[$k] -gt 127) { 2 } else { 1 } }
    return @{ 字节 = $字节; 字符 = $字符; 显示 = $显示 }
}

function 取列号([string]$输出) {
    $m = [regex]::Match($输出, ':(\d+):(\d+):\s*(?:error|warning|fatal error)')
    if ($m.Success) { return [int]$m.Groups[2].Value }
    return -1
}
function 取插入符位置([string]$输出) {
    foreach ($l in ($输出 -split "`n")) {
        if ($l -notmatch '\^') { continue }
        $i = $l.IndexOf('|')
        if ($i -lt 0) { continue }
        $c = $l.Substring($i + 1).IndexOf('^')
        if ($c -ge 0) { return $c }
    }
    return -1
}

# ---- 自测：期望值计算必须能区分（ASCII 行三值相等、汉字行三值不等）--------
$测英 = 期望列 'int abc = undeclared;' 'undeclared'
$测中 = 期望列 '整数 甲乙 = 未定义名字;' '未定义名字'
if ($测英.字节 -eq $测英.字符 -and $测英.字符 -eq $测英.显示) {
    过 ("自测：纯 ASCII 行三值相等（字节={0}）—— 期望值计算没有把英文弄歪" -f $测英.字节)
} else {
    错 ("自测失败：纯 ASCII 行三值应当相等，实际 字节={0} 字符={1} 显示={2}" -f $测英.字节, $测英.字符, $测英.显示)
}
if ($测中.字节 -ne $测中.字符 -and $测中.字符 -ne $测中.显示) {
    过 ("自测：汉字行三值互不相等（字节={0} / 字符={1} / 显示={2}）—— 探针有区分力" -f $测中.字节, $测中.字符, $测中.显示)
} else {
    错 ("★ 探针没有区分力：汉字行三值不该相等（字节={0} 字符={1} 显示={2}）—— 后面的通过不算数" -f $测中.字节, $测中.字符, $测中.显示)
}

# ---- 探针 -----------------------------------------------------------------
# 汉字行要够长，让三种口径明显不同；错误落在 `未定义名字` 上。
$行中 = '整数 甲乙丙丁戊己庚辛 = 1; 整数 结果 = 甲乙丙丁戊己庚辛 + 未定义名字;'
$行英 = 'int abcdefgh = 1; int result = abcdefgh + undefinedname;'
$期望中 = 期望列 $行中 '未定义名字'
$期望英 = 期望列 $行英 'undefinedname'

function 编译取列([string]$名字, [string]$行, [string]$开关, [string]$目标) {
    $f = Join-Path $work ($名字 + '.cpp')
    [System.IO.File]::WriteAllText($f, "$行`n整数 主函数(){ 返回 0; }`n", $utf8)
    $额外 = @()
    if ($开关 -ne '') { $额外 = @($开关) }
    $out = (& $exe '-std=c++20' @额外 -fsyntax-only $f 2>&1 | Out-String)
    return [pscustomobject]@{ 列 = 取列号 $out; 插入符 = 取插入符位置 $out; 原文 = $out }
}

# ① 三种单位必须给出三个不同的数，且各自等于期望
$单位 = @(
    @{ 开关 = '-fdiagnostics-column-unit=byte';      期望 = $期望中.字节; 名 = 'byte' },
    @{ 开关 = '-fdiagnostics-column-unit=display';   期望 = $期望中.显示; 名 = 'display' },
    @{ 开关 = '-fdiagnostics-column-unit=character'; 期望 = $期望中.字符; 名 = 'character' }
)
$取到 = @{}
foreach ($u in $单位) {
    $r = 编译取列 ('zh_' + $u.名) $行中 $u.开关 '未定义名字'
    $取到[$u.名] = $r.列
    if ($r.列 -eq $u.期望) { 过 ("汉字行 {0}：列号 {1}（期望 {2}）" -f $u.名, $r.列, $u.期望) }
    else { 错 ("汉字行 {0}：列号 {1}，期望 {2}（原始输出见下）`n{3}" -f $u.名, $r.列, $u.期望, $r.原文.Trim()) }
}
if (($取到['byte'] -ne $取到['display']) -and ($取到['display'] -ne $取到['character']) -and ($取到['byte'] -ne $取到['character'])) {
    过 ("三种口径确实互不相同（byte={0} / display={1} / character={2}）" -f $取到['byte'], $取到['display'], $取到['character'])
} else {
    错 ("★ 三种口径没有区分（byte={0} display={1} character={2}）—— 这一条没查成" -f $取到['byte'], $取到['display'], $取到['character'])
}

# ② 默认 == display
$r默认 = 编译取列 'zh_默认' $行中 '' '未定义名字'
if ($r默认.列 -eq $期望中.显示) { 过 ("默认（不写开关）== display（{0}）" -f $r默认.列) }
else { 错 ("默认列号 {0}，期望 display {1}" -f $r默认.列, $期望中.显示) }

# ③ 插入符 == 显示列（它本来就是对的，不许改坏）
$r插 = 编译取列 'zh_插入符' $行中 '' '未定义名字'
if ($r插.插入符 -eq $期望中.显示) { 过 ("插入符落点 {0} == 显示列（它本来就是对的，没被改坏）" -f $r插.插入符) }
else { 错 ("插入符落点 {0}，期望显示列 {1} —— 插入符被改坏了" -f $r插.插入符, $期望中.显示) }

# ④ 纯英文行：三种单位必须相同
$英列 = @()
foreach ($u in $单位) {
    $r = 编译取列 ('en_' + $u.名) $行英 $u.开关 'undefinedname'
    $英列 += $r.列
    if ($r.列 -eq $期望英.字节) { 过 ("英文行 {0}：列号 {1}（三口径重合）" -f $u.名, $r.列) }
    else { 错 ("英文行 {0}：列号 {1}，期望 {2}（英文源码不该有任何变化）" -f $u.名, $r.列, $期望英.字节) }
}

Write-Host ''
if ($script:fail -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host '  => FAIL' -ForegroundColor Red
exit 1
