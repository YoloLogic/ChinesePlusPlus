# ============================================================================
#  check_zhkwlen.ps1 -- 中文【关键字拼写】守卫（第 26 道）
#
#  为什么（2026-10-05 用户问「汉语关键字字长全部在 2–6，你还记得吗」）：实测 101 条拼写**全部**
#  落在 2–6 字，但 tools\ 里**没有任何守卫在查这个** —— 一直是"靠人记得"。本项目反复吃过这个亏
#  （§15.1 / §16.30 / §16.31）：规矩必须落成判据。
#
#  判据（口径由用户 2026-10-05 亲自定；读 ChineseKeywords.def，**不依赖字段顺序**：
#        四个宏的参数顺序不同，取"含汉字的那个字段"）：
#    ① 拼写**默认全是汉字**；**例外**：英文关键字本来**有数字**时，中文必须**原样保留同一个数字串**
#       （实测 3 条全合规：`char8_t`→`字符8位`、`char16_t`→`字符16位`、`char32_t`→`字符32位`）。
#       ⚠ **下划线不强制**（用户裁定）：英文带下划线的 11 条保持全汉字（`const_cast`→`常量转换`、
#         `static_assert`→`静态断言`、`co_await`→`协程等待`、`thread_local`→`线程局部`、
#         `typeof_unqual`→`取无修饰类型` …）—— 中文已用汉字表达同一信息。
#    ② 字长 **2–6**（实测分布 2 字 64 / 3 字 17 / 4 字 15 / 5 字 4 / 6 字 1）。
#    ③ **小节内**不重复：`import`/`module` 在两张小节里刻意各登记一次（第一～五节那两行是照抄
#       英文的空操作，真正生效的是第八节上下文关键字）⇒ 按 (小节, 英文, 中文) 判重，正好不报。
#    ⇒ 现有 101 条在这三条判据下**全绿**（实测 ✓）。若报红，是表真坏了或判据要与用户重新对齐，
#      **不要往白名单里塞东西**。
#
#  ⚠ PowerShell 的三个坑（本项目都踩过，本文件全部绕开）：
#    · `$bad += @('类别','说明')` 会**摊平**；`return $bad`（数组的数组）进管道**再摊平一次** ——
#      所以本文件**返回扁平字符串** `'类别|说明'`，判据里用 `-match '^类别\|'` 过滤，不做嵌套数组。
#    · 计分/配对不要用 `@(@($ok,'名'), …)`，同样摊平 ⇒ 逐个 if/else。
#
#  用法：pwsh -NoProfile -File tools\check_zhkwlen.ps1 [-Quiet] [-SelfTest]
# ============================================================================
param([switch] $Quiet, [switch] $SelfTest)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$def = Join-Path $root 'LLVM-main\clang\include\clang\Basic\ChineseKeywords.def'

function Get-ZhKeywordRows([string] $Text) {
    $rows = @()
    foreach ($m in [regex]::Matches($Text, '(?m)^(ZH_[A-Z_]+)\(([^)\r\n]*)\)')) {
        $fields = @(($m.Groups[2].Value -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $zh = @($fields | Where-Object { $_ -match '[\u4e00-\u9fff]' })
        $en = @($fields | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*$' -and $_ -notmatch '^KEY[A-Z0-9_]*$' })
        if ($zh.Count -eq 1 -and $en.Count -ge 1) { $rows += [pscustomobject]@{ Mac = $m.Groups[1].Value; En = $en[0]; Zh = $zh[0] } }
    }
    return $rows
}

function Test-ZhKeywordRows($Rows) {
    <#  返回**扁平字符串**清单（'类别|说明'）—— 不要返回数组的数组，管道会把它摊平（实测踩过）#>
    $bad = @(); $seen = @{}
    foreach ($r in $Rows) {
        if ($r.Zh.Length -lt 2 -or $r.Zh.Length -gt 6) { $bad += ('字长|{0}（{1} 字，英文 {2}）' -f $r.Zh, $r.Zh.Length, $r.En) }
        foreach ($m in [regex]::Matches($r.Zh, '[A-Za-z_0-9]')) {
            if ($m.Value -match '^[0-9]$') {
                if ($r.En -notmatch [regex]::Escape($m.Value)) { $bad += ('数字无出处|{0} 里的 {1} 在英文 {2} 里没有' -f $r.Zh, $m.Value, $r.En) }
            } else {
                $bad += ('夹了非数字 ASCII|{0} 里的 {1}（英文 {2}）' -f $r.Zh, $m.Value, $r.En)
            }
        }
        $key = "$($r.Mac)|$($r.En)|$($r.Zh)"
        if ($seen.ContainsKey($key)) { $bad += ('重复|' + $key) } else { $seen[$key] = '已见' }
    }
    return $bad
}

if ($SelfTest) {
    $pass = 0; $total = 5
    $f1 = @([pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'if'; Zh = '甲' })
    $f2 = @([pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'if'; Zh = '如果x' })
    $f3 = @([pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'char8_t'; Zh = '字符16位' })
    $f4 = @([pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'if'; Zh = '如果' }, [pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'if'; Zh = '如果' })
    $f5 = @([pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'if'; Zh = '如果' }, [pscustomobject]@{ Mac = 'ZH_KEYWORD'; En = 'char16_t'; Zh = '字符16位' })
    if (@(Test-ZhKeywordRows $f1 | Where-Object { $_ -match '^字长\|' }).Count) { $pass++ } else { Write-Host '  ❌ 自检1 漏报 1 字' -ForegroundColor Red }
    if (@(Test-ZhKeywordRows $f2 | Where-Object { $_ -match '^夹了非数字 ASCII\|' }).Count) { $pass++ } else { Write-Host '  ❌ 自检2 漏报夹字母' -ForegroundColor Red }
    if (@(Test-ZhKeywordRows $f3 | Where-Object { $_ -match '^数字无出处\|' }).Count) { $pass++ } else { Write-Host '  ❌ 自检3 漏报数字无出处' -ForegroundColor Red }
    if (@(Test-ZhKeywordRows $f4 | Where-Object { $_ -match '^重复\|' }).Count) { $pass++ } else { Write-Host '  ❌ 自检4 漏报重复' -ForegroundColor Red }
    if (@(Test-ZhKeywordRows $f5).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检5 误报合规条目' -ForegroundColor Red }
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

$rows = Get-ZhKeywordRows ([System.IO.File]::ReadAllText($def))
if ($rows.Count -eq 0) { Write-Host '❌ 一条中文拼写都没扫到 —— 跑 0 条的通过不是通过（§15.3）' -ForegroundColor Red; exit 1 }
$bad = @(Test-ZhKeywordRows $rows)
if (-not $Quiet) {
    Write-Host ("=== 中文关键字拼写守卫（第 26 道）：{0} 条 ===" -f $rows.Count) -ForegroundColor Cyan
    $g = $rows | Group-Object { $_.Zh.Length } | Sort-Object { [int]$_.Name }
    Write-Host ('    字长分布：' + (($g | ForEach-Object { "{0} 字 {1}" -f $_.Name, $_.Count }) -join ' / '))
    $wd = @($rows | Where-Object { $_.Zh -match '\d' })
    if ($wd.Count) { Write-Host ('    含数字（英文本来就有）：' + (($wd | ForEach-Object { "{0}<-{1}" -f $_.Zh, $_.En }) -join '、')) }
}
if ($bad.Count) {
    Write-Host '❌ 中文关键字拼写违反判据（全汉字或对应数字 / 字长 2–6 / 小节内不重复）：' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host ('    ' + $_) -ForegroundColor Red }
    exit 1
}
if (-not $Quiet) { Write-Host '    ✓ 全部通过' -ForegroundColor Green }
exit 0
