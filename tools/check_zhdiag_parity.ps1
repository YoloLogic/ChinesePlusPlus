# ============================================================================
#  中英诊断对称性守卫（§18.6：大检查 P-03 + P-06 / P-11）
#
#  判据（三条，全都要成立）：
#    ① P-03 —— `#define override 1` 与 `#定义 重写 1` 在 `-Wkeyword-macro` 下
#       必须给出**同一条**警告（正文归一化后相等）。
#       改之前：英文报"关键字被宏定义隐藏"，中文**一条都没有** ⇒ 中英不对称。
#    ② P-06 —— GBK（Windows 中文环境的默认 ANSI）源码的诊断正文里必须有
#       **补救办法**（出现"另存为 UTF-8"），而不是只说一句"不是有效的 UTF-8"。
#       改之前实测：只能得到"源文件不是有效的 UTF-8"，用户不知道该怎么办。
#    ③ P-11 —— 同一个坏字节文件只能报**一条** err_invalid_utf8。
#       改之前实测：一个 17 个汉字的 GBK 文件报 **20 条**，最后还撞上
#       `-ferror-limit` 变成 "发出的错误过多，现在停止"。
#
#  自带自测：① 的归一化比较必须能区分（两侧不同必须判不等）；
#    ② 的"含补救"判断必须能失败（没有补救的正文必须判缺）。
#
#  跑法：pwsh -NoProfile -File tools\check_zhdiag_parity.ps1
#  退出码：0 = 三条都成立；1 = 有不对的（或自测失败）
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$exe  = Join-Path $Root 'build\Release\bin\chinese++.exe'
$work = Join-Path $Root 'build\_zhdiagparity'
New-Item -ItemType Directory -Force $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }

if (-not (Test-Path $exe)) { 错 "找不到编译器：$exe"; exit 1 }

function 取正文([string]$输出) {
    $行 = @()
    foreach ($l in ($输出 -split "`n")) {
        if ($l -match '\b(error|warning|note|fatal error)\s*:') {
            $m = [regex]::Match($l, '\b(?:error|warning|note|fatal error)\s*:\s*(.*)$')
            $b = if ($m.Success) { $m.Groups[1].Value } else { $l }
            $行 += ($b -replace '\s*\[-W[^\]]*\]\s*$', '').Trim()
        }
    }
    return $行
}

# ---- 自测 -----------------------------------------------------------------
$自测规 = { param($s) ($s -replace '重写', '<KW>') -replace 'override', '<KW>' }
$测A = & $自测规 '关键字被宏定义隐藏 重写'
$测B = & $自测规 '关键字被宏定义隐藏 override'
$测C = & $自测规 '关键字被宏定义隐藏 最终'
if ($测A -eq $测B -and $测A -ne $测C) {
    过 "自测①：归一化比较能区分（重写/override 归一后相同；最终 不同）"
} else {
    错 ("自测①失败：归一化不按预期（A='{0}' B='{1}' C='{2}'）" -f $测A, $测B, $测C)
}
$含补救 = { param($s) $s -like '*另存为 UTF-8*' }
if ((-not (& $含补救 '源文件不是有效的 UTF-8')) -and (& $含补救 '源文件不是有效的 UTF-8 —— 请把源文件另存为 UTF-8')) {
    过 "自测②：'含补救'判断能失败（没有补救判缺、有补救判有）"
} else {
    错 "自测②失败：'含补救'判断不按预期"
}

# ---- ① P-03：中文 virt-specifier 当宏名，必须与英文报同一条警告 ------------
$宏英 = Join-Path $work 'macro_en.cpp'
$宏中 = Join-Path $work 'macro_zh.cpp'
[System.IO.File]::WriteAllText($宏英, "#define override 1`n整数 主函数(){ 返回 0; }`n", $utf8)
[System.IO.File]::WriteAllText($宏中, "#定义 重写 1`n整数 主函数(){ 返回 0; }`n", $utf8)
$警英 = 取正文 (& $exe '-std=c++20' '-Wkeyword-macro' -fsyntax-only $宏英 2>&1 | Out-String)
$警中 = 取正文 (& $exe '-std=c++20' '-Wkeyword-macro' -fsyntax-only $宏中 2>&1 | Out-String)
if ($警英.Count -eq 0) {
    错 "英文对照 `#define override 1` 一条警告都没有 —— 探针坏了（后面的结论不算数）"
} elseif ($警中.Count -eq 0) {
    错 "★ P-03：`#定义 重写 1` 一条警告都没有，而英文 `#define override 1` 有 —— 中英不对称"
} else {
    $规英 = @($警英 | ForEach-Object { & $自测规 $_ })
    $规中 = @($警中 | ForEach-Object { & $自测规 $_ })
    $独中 = @($规中 | Where-Object { $规英 -notcontains $_ })
    $独英 = @($规英 | Where-Object { $规中 -notcontains $_ })
    if ($独中.Count -eq 0 -and $独英.Count -eq 0) {
        过 ("P-03：中文 `#定义 重写` 与英文 `#define override` 报同一条警告（{0}）" -f $规中[0])
    } else {
        错 ("★ P-03：中英警告不一致 —— 中文独有 [{0}]、英文独有 [{1}]" -f ($独中 -join ' / '), ($独英 -join ' / '))
    }
}

# ---- ②③ P-06 / P-11：GBK 源码 -------------------------------------------------
$gbk = [System.Text.Encoding]::GetEncoding(936)
$源码 = "整数 主函数(){`r`n    整数 甲乙丙丁 = 1;`r`n    返回 甲乙丙丁 - 1;`r`n}`r`n"
$gbkFile = Join-Path $work 'gbk.cpp'
[System.IO.File]::WriteAllBytes($gbkFile, $gbk.GetBytes($源码))
$gbkOut = (& $exe '-std=c++20' -fsyntax-only $gbkFile 2>&1 | Out-String)
$gbk正文 = 取正文 $gbkOut
$编码条 = @($gbk正文 | Where-Object { $_ -like '*有效的 UTF-8*' })

if ($编码条.Count -eq 0) {
    错 "★ 探针没打中：GBK 源码一条编码诊断都没有"
} else {
    # ③ 只报一条
    if ($编码条.Count -eq 1) { 过 ("P-11：GBK 源码只报 1 条编码诊断（改之前是 20 条 + 撞 -ferror-limit）") }
    else { 错 ("★ P-11：GBK 源码报了 {0} 条编码诊断（应当只有 1 条）—— 首条：{1}" -f $编码条.Count, $编码条[0]) }
    # ② 正文里要有补救办法
    if (& $含补救 $编码条[0]) { 过 ("P-06：诊断里带了补救办法 —— {0}" -f $编码条[0]) }
    else { 错 ("★ P-06：诊断里没有补救办法（应出现「另存为 UTF-8」）—— 实际：{0}" -f $编码条[0]) }
}
if ($gbk正文 -match '发出的错误过多') { 错 "★ 仍然撞上了 -ferror-limit（说明刷屏没治好）" }

# ---- ④ P-07：主文件是 UTF-16 时**不许崩** ---------------------------------
# 症状（改之前）：Exception Code 0xC0000005 + "PLEASE submit a bug report" + 堆栈转储，
#   而上游 clang 19.1.5 对同一个文件只是干净报错（fatal error + 1 error generated）。
# 判据：四种模式都要 ① 退出码 1、② 报出那条 UTF-16 致命诊断、③ **不许有崩溃痕迹**。
$崩标 = { param($s) ($s -match 'Exception Code') -or ($s -match 'PLEASE submit') -or ($s -match 'Stack dump') }
if ((& $崩标 'x Exception Code: 0xC0000005 y') -and -not (& $崩标 'fatal error: 干净报错')) {
    过 "自测③：'崩溃痕迹'判断能失败（有 Exception Code 判崩、干净报错判不崩）"
} else {
    错 "自测③失败：'崩溃痕迹'判断不按预期"
}

$u16 = Join-Path $work 'utf16.cpp'
# ⚠ 必须**自己加 BOM**：`Encoding.Unicode.GetBytes()` 只编码、**不写前导码**，
#    少了 BOM 它只是一段非法 UTF-8，走的完全是另一条诊断路（探针就"没打中"了）。
[System.IO.File]::WriteAllBytes($u16,
    ([byte[]](0xFF, 0xFE)) + [System.Text.Encoding]::Unicode.GetBytes("整数 主函数(){ 返回 0; }`r`n"))
foreach ($m in @('-fsyntax-only', '-E', '-S', '-c')) {
    $out = (& $exe '-std=c++20' $m $u16 '-o' (Join-Path $work 'u16.bin') 2>&1 | Out-String)
    $码 = $LASTEXITCODE
    if (& $崩标 $out) {
        错 ("★ P-07：{0} 时编译器**崩了**（出现 Exception Code / PLEASE submit / Stack dump）" -f $m)
    } elseif ($码 -ne 1) {
        错 ("★ P-07：{0} 退出码 {1}（应当 1）" -f $m, $码)
    } elseif ($out -notmatch 'UTF-16') {
        错 ("★ P-07：{0} 没报出那条 UTF-16 诊断 —— 探针没打中" -f $m)
    } else {
        过 ("P-07：{0} 干净收场（退出码 1 + 一条致命诊断，无崩溃痕迹）" -f $m)
    }
}
# 对照：合法的 UTF-8 with BOM 必须照常编过（别把正常路径一起改了）
$u8b = Join-Path $work 'utf8bom.cpp'
[System.IO.File]::WriteAllBytes($u8b, ([byte[]](0xEF, 0xBB, 0xBF)) + [System.Text.Encoding]::UTF8.GetBytes("整数 主函数(){ 返回 0; }`n"))
$exeU8 = Join-Path $work 'u8bom.exe'
& $exe '-std=c++20' $u8b '-o' $exeU8 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { & $exeU8 | Out-Null; $r = $LASTEXITCODE } else { $r = 99 }
if ($r -eq 0) { 过 "对照：UTF-8 with BOM 照常编译并运行（退出码 0）" }
else { 错 ("对照失败：UTF-8 with BOM 的退出码是 {0}（应当 0）" -f $r) }

Write-Host ''
if ($script:fail -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host '  => FAIL' -ForegroundColor Red
exit 1
