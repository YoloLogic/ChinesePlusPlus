# ============================================================================
#  中文诊断「英文残留」守卫（§18.3：大检查 P-04 的回归判据）
#
#  判据（两条，都要成立）：
#    ① 中文诊断（默认）的**正文里不得残留英文关键字名**
#       —— 如 `不能与前面的声明说明符（关键字） 'int' 组合`：用户写的是 `整数`。
#    ② 同一份源码在 -fno-chinese-diagnostics 下**必须仍然是英文那套**
#       —— 证明我们只是"中文模式给中文"，没有把英文模式也改坏。
#
#  为什么需要一条单独的守卫：
#    项目现有的汉化覆盖率口径是"这句正文里有没有汉字"（docs\README.md 第四节）。
#    而漏出来的消息 **都含汉字** —— `不能与前面的声明说明符（关键字） 'int' 组合`
#    里汉字俱全，按那个口径它算【已汉化】。口径看不见"中文句子里夹英文"，
#    这条守卫补的就是这个盲区。
#
#  已知未修：类型打印器（TypePrinter）输出的类型名仍是英文（`'double' 与 'int'`），
#    那是另一个面（台账 P-09），本守卫**登记但不判失败**，并且会打印出来；
#    哪天修好了，它会报"已知未修条目已消失"，提醒把登记删掉（分子不许偷偷变）。
#
#  跑法：pwsh -NoProfile -File tools\check_zhdiag_leak.ps1
#  退出码：0 = 无残留且自测通过；1 = 有残留 / 有探针没打中 / 自测失败
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$exe  = Join-Path $Root 'build\Release\bin\chinese++.exe'
$work = Join-Path $Root 'build\_zhdiagleak'
New-Item -ItemType Directory -Force $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }
function 提($t) { Write-Host ("  [注意] $t") -ForegroundColor Yellow }

if (-not (Test-Path $exe)) { 错 "找不到编译器：$exe"; exit 1 }

# ---------------------------------------------------------------------------
#  黑名单：这些英文名【不许】出现在中文诊断正文里
#  （每一条都是"语言构造名"，中文关键字表里都有对应拼写）
# ---------------------------------------------------------------------------
$黑名单 = @(
    'int', 'char', 'double', 'float', 'void', 'bool',
    'class', 'struct', 'union', 'enum',
    'auto', 'const', 'static', 'extern', 'register', 'inline',
    'signed', 'unsigned', 'long', 'short', 'typedef',
    'override', 'final',
    'identifier'
)

# 有意【不】列入黑名单的（写明理由，免得后来者以为是漏了）：
#   template        —— `'template<>'` 是用户要【照写】的语法，中文消息里保留英文有据
#                      （`模板` 也可以写，但两种拼写在源码里并存，回显哪个都不算错）
#   and/or/not/…    —— 运算符替代拼写，`运算符&&` 与 `运算符 并且` 并存
#   __int128 / _BitInt / _Accum / _Fract / __vector / __interface / half
#                   —— 实现拼写，中文关键字表里【本来就没有】对应译名
#   ISO / C++ / C2y / OpenACC / HLSL / GCC / MSVC —— 专名与标准名

# 已知未修（命中不算失败，但会打印；修好后会报"条目已消失"）
$已知未修 = @(
    @{ 探针 = 'L09-重复定义类型不同'; 词 = 'int';    因 = 'P-09 类型打印器未汉化' },
    @{ 探针 = 'L09-重复定义类型不同'; 词 = 'double'; 因 = 'P-09 类型打印器未汉化' }
)

# ---------------------------------------------------------------------------
#  自测：这条判据必须【能失败】（项目纪律：永远返回"通过"的检查等于没有检查）
# ---------------------------------------------------------------------------
function 扫英文残留([string]$正文) {
    $命中 = @()
    foreach ($w in $黑名单) {
        if ($正文 -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($w) + '(?![A-Za-z0-9_])')) { $命中 += $w }
    }
    return $命中
}

# 黑名单不许凭空造词：每个词都必须是关键字表里的英文名（identifier 例外，它是记号名）
$defPath = Join-Path $Root 'llvm-main\clang\include\clang\Basic\ChineseKeywords.def'
$defTxt  = if (Test-Path $defPath) { [System.IO.File]::ReadAllText($defPath) } else { '' }
$造词 = @()
foreach ($w in $黑名单) {
    if ($w -eq 'identifier') { continue }
    if ($defTxt -notmatch ("ZH_KEYWORD\(\s*" + [regex]::Escape($w) + "\s*,") -and
        $defTxt -notmatch ("ZH_VIRT_SPECIFIER\(\s*" + [regex]::Escape($w) + "\s*,")) { $造词 += $w }
}
if ($造词.Count -gt 0) { 错 ("黑名单里有 {0} 个词不是关键字表里的英文名（判据不许凭空造词）：{1}" -f $造词.Count, ($造词 -join ' ')) }
else { 过 ("黑名单 {0} 个词都能在 ChineseKeywords.def 里对上（identifier 是记号名，单独说明）" -f $黑名单.Count) }

$自测有 = 扫英文残留 "不能与前面的声明说明符（关键字） 'int' 组合"
$自测无 = 扫英文残留 "不能与前面的声明说明符（关键字） '整数' 组合"
if ($自测有.Count -ge 1 -and $自测无.Count -eq 0) {
    过 "自测：判据确实能失败（构造的英文残留被抓到 'int'，纯中文不误报）"
} else {
    错 ("自测失败：判据不按预期工作（该抓的抓了 {0} 个、纯中文误报 {1} 个）" -f $自测有.Count, $自测无.Count)
}

# ---------------------------------------------------------------------------
#  探针：每条都要【真的产生诊断】，否则不算查过
# ---------------------------------------------------------------------------
$探针 = @(
    @('L01-声明说明符组合',   '结构 甲 { 整数 整数; }; 整数 主函数(){ 返回 0; }'),
    @('L02-匿名类型定义',     '类型 类型 { }; 整数 主函数(){ 返回 0; }'),
    @('L03-重写用错位置',     '结构 甲 { 整数 取() 重写 { 返回 1; } }; 整数 主函数(){ 返回 0; }'),
    @('L04-最终用错位置',     '结构 甲 { 整数 取() 最终 { 返回 1; } }; 整数 主函数(){ 返回 0; }'),
    @('L05-模板参数名用关键字','模板 <类型名 类型名> 结构 甲 { }; 整数 主函数(){ 返回 0; }'),
    @('L06-名域名字用关键字', '名域 名域 { 整数 值 = 0; } 整数 主函数(){ 返回 0; }'),
    @('L07-枚举量用关键字',   '枚举 甲 { 默认 = 1 }; 整数 主函数(){ 返回 0; }'),
    @('L08-存储类冲突',       '类型别名 静态 整数 甲; 整数 主函数(){ 返回 0; }'),
    @('L09-重复定义类型不同', '整数 甲 = 1; 双精度 甲 = 2; 整数 主函数(){ 返回 0; }'),
    @('L10-访问私有成员',     '类型 甲 { 私有: 整数 值; }; 整数 主函数(){ 甲 对象; 返回 对象.值; }'),
    @('L11-纯虚未实现',       '类型 接口 { 公开: 虚拟 整数 取() = 0; }; 类型 实现 : 公开 接口 { }; 整数 主函数(){ 实现 甲; 返回 0; }')
)

function 取诊断正文([string]$输出) {
    $行 = @()
    foreach ($l in ($输出 -split "`n")) {
        if ($l -match '\b(error|warning|note|fatal error)\s*:') {
            $m = [regex]::Match($l, '\b(?:error|warning|note|fatal error)\s*:\s*(.*)$')
            $b = if ($m.Success) { $m.Groups[1].Value } else { $l }
            # 去掉 [-Wxxx] 开关名（它不是正文）
            $b = $b -replace '\s*\[-W[^\]]*\]\s*$', ''
            $行 += $b.Trim()
        }
    }
    return $行
}

$诊断行数 = 0; $命中数 = 0; $残留 = @(); $没打中 = @(); $已知命中 = @()
foreach ($p in $探针) {
    $名 = $p[0]; $源码 = $p[1]
    $src = Join-Path $work ($名 + '.cpp')
    [System.IO.File]::WriteAllText($src, $源码, $utf8)

    $中 = (& $exe '-std=c++20' -fsyntax-only $src 2>&1 | Out-String)
    $正文 = 取诊断正文 $中
    if ($正文.Count -eq 0) { $没打中 += $名; continue }
    $诊断行数 += $正文.Count
    foreach ($b in $正文) {
        $hit = 扫英文残留 $b
        foreach ($w in $hit) {
            $命中数++
            $已知 = @($已知未修 | Where-Object { $_.探针 -eq $名 -and $_.词 -eq $w })
            if ($已知.Count -gt 0) { $已知命中 += ("{0}：'{1}'（{2}）" -f $名, $w, $已知[0].因) }
            else { $残留 += ("{0}：{1}   ← 残留 '{2}'" -f $名, $b, $w) }
        }
    }

    # ② 对称检查：同一份源码在英文模式下必须还是英文那套
    $英 = (& $exe '-std=c++20' -fno-chinese-diagnostics -fsyntax-only $src 2>&1 | Out-String)
    $英正文 = 取诊断正文 $英
    if ($正文.Count -gt 0 -and $英正文.Count -eq 0) { 错 ("{0}：英文模式下一条诊断都没有 —— 开关或探针坏了" -f $名) }
}

# 英文模式没有被改坏的正面证据：挑 L01 确认英文模式仍然显示 'int'
$l01 = Join-Path $work 'L01-声明说明符组合.cpp'
$英01 = 取诊断正文 (& $exe '-std=c++20' -fno-chinese-diagnostics -fsyntax-only $l01 2>&1 | Out-String)
if (($英01 -join ' ') -match "'int'") { 过 "对称检查：英文模式（-fno-chinese-diagnostics）仍然显示 'int'（没有把英文也改坏）" }
else { 错 ("对称检查失败：英文模式下看不到 'int' —— 输出：{0}" -f ($英01 -join ' / ')) }

if ($没打中.Count -gt 0) { 错 ("有 {0} 条探针一条诊断都没产生（探针没打中 = 没查过）：{1}" -f $没打中.Count, ($没打中 -join '、')) }

Write-Host ("  查了 {0} 条诊断正文（{1} 条探针）" -f $诊断行数, $探针.Count)
if ($已知命中.Count -gt 0) {
    提 ("已知未修（登记在案，不算失败）{0} 处：" -f $已知命中.Count)
    $已知命中 | Select-Object -Unique | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor DarkYellow }
}
if ($残留.Count -gt 0) {
    Write-Host ("  英文残留 {0} 处：" -f $残留.Count) -ForegroundColor Red
    $残留 | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor Red }
} else {
    过 "中文诊断正文里没有英文关键字名残留"
}

# 已知未修条目必须【仍然存在】—— 修好了就要把登记删掉（分子不许偷偷变）
$已消失 = @()
foreach ($k in $已知未修) {
    if (-not ($已知命中 | Where-Object { $_ -like ($k.探针 + "：*") })) { $已消失 += ("{0} / '{1}'" -f $k.探针, $k.词) }
}
if ($已消失.Count -gt 0) {
    提 ("这些'已知未修'条目已经查不到了（修好了就把登记删掉，别让欠账表虚着）：{0}" -f ($已消失 -join '、'))
}

Write-Host ''
if ($script:fail -eq 0 -and $残留.Count -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host '  => FAIL' -ForegroundColor Red
exit 1
