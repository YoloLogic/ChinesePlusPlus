# ============================================================================
#  中文关键字当标识符：诊断必须【说出那个词】（§18.4：大检查 P-05 的回归判据）
#
#  判据：对 ChineseKeywords.def 里每一条 `ZH_KEYWORD`（86 条保留字），编译
#            整数 <中文名> = 1;
#        它的**诊断正文**里必须出现那个中文词。
#
#  为什么这么判（而不是"能不能编译失败"）：
#    现在（2026-10-03 实测）86 条里 **77 条**的消息是"缺少（种类） 非限定标识符" ——
#    它连**是哪个词**都不说。而汉语使用者的第一条报错几乎一定是这一条：
#    汉语词与标识符在视觉上没有任何区别（`如果` 看起来就是个普通词），
#    英文用户反而几乎不会踩（谁会拿 `if` 当变量名）。
#    所以判据是"**说不说得清**"，不是"失败不失败"——后者当然会失败，等于没查。
#
#  ⚠ 只扫【诊断正文】，**不扫源码回显行** —— 否则源码里的那个词会自己满足判据，
#    这条判据就成了永真式（第一版踩过，见台账"探针自己的 bug"一节）。
#
#  跑法：pwsh -NoProfile -File tools\check_zhkw_name.ps1
#  退出码：0 = 86 条都说得清；1 = 有说不清的（或自测失败）
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$exe  = Join-Path $Root 'build\Release\bin\chinese++.exe'
$def  = Join-Path $Root 'llvm-main\clang\include\clang\Basic\ChineseKeywords.def'
$work = Join-Path $Root 'build\_zhkwname'
New-Item -ItemType Directory -Force $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }
function 提($t) { Write-Host ("  [注意] $t") -ForegroundColor Yellow }

if (-not (Test-Path $exe)) { 错 "找不到编译器：$exe"; exit 1 }
if (-not (Test-Path $def)) { 错 "找不到关键字表：$def"; exit 1 }

# ---- 取诊断正文（只取 error/warning 行，且去掉 [-Wxxx] 开关名）------------
function 取诊断正文([string]$输出) {
    $行 = @()
    foreach ($l in ($输出 -split "`n")) {
        if ($l -match '\b(error|warning)\s*:') {
            $m = [regex]::Match($l, '\b(?:error|warning)\s*:\s*(.*)$')
            $b = if ($m.Success) { $m.Groups[1].Value } else { $l }
            $行 += ($b -replace '\s*\[-W[^\]]*\]\s*$', '').Trim()
        }
    }
    return $行
}

# ---- 自测：判据必须能失败 -------------------------------------------------
#  ① 正文里没有那个词 ⇒ 必须判"说不清"
#  ② 正文里有那个词   ⇒ 必须判"说得清"
function 说得清([string[]]$正文, [string]$词) {
    foreach ($b in $正文) { if ($b -like ("*" + $词 + "*")) { return $true } }
    return $false
}
$自测1 = 说得清 @('缺少（种类） 非限定标识符') '如果'
$自测2 = 说得清 @('（关键字） 如果 不能用作标识符') '如果'
if ((-not $自测1) -and $自测2) {
    过 '自测：判据确实能失败（不说词的判"说不清"，说词的判"说得清"）'
} else {
    错 ("自测失败：判据不按预期工作（不说词={0}、说词={1}）" -f $自测1, $自测2)
}

# ---- 逐条关键字跑 ---------------------------------------------------------
$rows = @()
foreach ($l in [System.IO.File]::ReadAllLines($def)) {
    if ($l -match '^\s*ZH_KEYWORD\(\s*([A-Za-z_0-9]+)\s*,\s*(\S+?)\s*,') { $rows += ,@($Matches[1], $Matches[2]) }
}
if ($rows.Count -eq 0) { 错 '一条 ZH_KEYWORD 都没解析出来（表格式变了？）'; exit 1 }

$说得清数 = 0; $说不清 = @(); $已知命中 = @(); $合法数 = 0

# 上下文关键字（module / import）：**当标识符是合法的、而且必须继续合法** ——
#   这不是"说不出词"，而是设计要求（ChineseKeywords.def 第八节原话：
#   为了 `int module = 1;` 这类既有代码继续合法）。所以对它们反过来断言。
$上下文关键字 = @('模块', '导入')

# 已知未修（命中不算失败，但会打印；修好后会报"条目已消失"）
$已知未修 = @{
    '运算符' = '走 operator-function-id 路径：消息里打印的是**修饰后的算子名** operator=（英文），' +
               '要说得清得让算子名的打印也走中文拼写 —— 与 P-04/P-09 同一类"打印器"问题，另记'
}

# 语言模式：同一个关键字在不同标准下可能**根本不是关键字**（`受限`=restrict 是 C99 的，
# 在 C++ 里它就是普通标识符，`整数 受限 = 1;` 合法、自然没有诊断）。
# 所以逐个试，取第一个"这个关键字确实存在"的模式 —— 自动挑，不写死清单。
$模式 = @(
    @{ 标准 = 'c++20';   扩展 = '.cpp'; 额外 = @() },
    @{ 标准 = 'c++23';   扩展 = '.cpp'; 额外 = @() },
    @{ 标准 = 'gnu++20'; 扩展 = '.cpp'; 额外 = @() },
    @{ 标准 = 'c11';     扩展 = '.c';   额外 = @('-x', 'c') },
    @{ 标准 = 'c23';     扩展 = '.c';   额外 = @('-x', 'c') }
)
foreach ($r in $rows) {
    $en = $r[0]; $zh = $r[1]

    if ($上下文关键字 -contains $zh) {
        # 必须【合法】：一条诊断都不许有
        $f = Join-Path $work ("ctx_$en.cpp")
        [System.IO.File]::WriteAllText($f, "整数 $zh = 1;`n整数 主函数(){ 返回 $zh - 1; }`n", $utf8)
        $out = (& $exe '-std=c++20' -fsyntax-only $f 2>&1 | Out-String)
        $d = 取诊断正文 $out
        if ($d.Count -eq 0) { $合法数++ }
        else { $说不清 += ("{0}（{1}）：★ 上下文关键字【必须】能当标识符，却报了诊断 → {2}" -f $zh, $en, ($d -join ' || ')) }
        continue
    }

    $正文 = @(); $用的模式 = ''
    foreach ($m in $模式) {
        $f = Join-Path $work ("n_$en" + $m.扩展)
        [System.IO.File]::WriteAllText($f, "整数 $zh = 1;`n整数 主函数(){ 返回 0; }`n", $utf8)
        $out = (& $exe @($m.额外) ('-std=' + $m.标准) -fsyntax-only $f 2>&1 | Out-String)
        $正文 = 取诊断正文 $out
        if ($正文.Count -gt 0) { $用的模式 = $m.标准; break }
    }
    if ($正文.Count -eq 0) { $说不清 += ("{0}（{1}）：★ 试过 5 种标准都没有诊断（探针没打中）" -f $zh, $en); continue }
    if (说得清 $正文 $zh) { $说得清数++ }
    elseif ($已知未修.ContainsKey($zh)) { $已知命中 += ("{0}（{1}）[{2}] → {3}   ← 已知未修：{4}" -f $zh, $en, $用的模式, ($正文 -join ' || '), $已知未修[$zh]) }
    else { $说不清 += ("{0}（{1}）[{2}] → {3}" -f $zh, $en, $用的模式, ($正文 -join ' || ')) }
}

Write-Host ("  查了 {0} 条关键字（每条真编一次）：{1} 条保留字 + {2} 条上下文关键字" -f $rows.Count, ($rows.Count - $上下文关键字.Count), $上下文关键字.Count)
if ($已知命中.Count -gt 0) {
    提 ("已知未修（登记在案，不算失败）{0} 条：" -f $已知命中.Count)
    $已知命中 | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor DarkYellow }
}
if ($说不清.Count -eq 0) {
    过 ("{0} 条保留字当标识符时，诊断正文里都【说出了那个词】；{1} 条上下文关键字仍可当标识符（设计要求）" -f $说得清数, $合法数)
} else {
    Write-Host ("  有 {0} 条关键字的诊断【没说出那个词】：" -f $说不清.Count) -ForegroundColor Red
    $说不清 | Select-Object -First 25 | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor Red }
    if ($说不清.Count -gt 25) { Write-Host ("         …（共 {0} 条，只列前 25）" -f $说不清.Count) -ForegroundColor Red }
}

# 已知未修条目必须【仍然存在】—— 修好了就要把登记删掉（分子不许偷偷变）
$已消失 = @()
foreach ($k in $已知未修.Keys) {
    if (-not ($已知命中 | Where-Object { $_ -like ($k + "（*") })) { $已消失 += $k }
}
if ($已消失.Count -gt 0) {
    提 ("这些'已知未修'条目已经查不到了（修好了就把登记删掉）：{0}" -f ($已消失 -join '、'))
}

Write-Host ''
if ($script:fail -eq 0 -and $说不清.Count -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host '  => FAIL' -ForegroundColor Red
exit 1
