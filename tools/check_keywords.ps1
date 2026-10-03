# ============================================================================
#  check_keywords.ps1 —— 大检查第 0 层：中文关键字（§18.1）
#
#  为什么需要：`tests\checks\verify_chinese_keywords.py` 只做**源码级**交叉校验
#  （名称存在 / 译名唯一 / 标志合法 / 可切分）。它证明不了三件事：
#    ① 我们**手上这个二进制**（build\Release\bin\chinese++.exe）里真的有这些拼写
#       —— 文档 §九 坑二记过一次"硬链接断了，chinese++.exe 停在上一次构建"，
#          静态检查对那种情况**完全无感** ✗；
#    ② 每条拼写在**词法层真的被当成关键字**（负例：拿它当标识符必须报错）；
#    ③ `ZH_CONTEXTUAL_KEYWORD` 那一族（模块/导入）**根本没进** py 校验器的视野 ✗。
#
#  判据（纪律：跑 0 条的通过不是通过；每条都要能变成工作表）：
#    A 静态：4 种宏族逐条解析；中文名 2–6 汉字 / 无数字开头 / 纯 CJK / 唯一；
#            英文名必须在 TokenKinds.def 里；上下文族的 SETTER 必须在 IdentifierInfo 里；
#            上下文族的中文名必须与同名 ZH_KEYWORD 行逐字一致。
#    B 二进制：每个中文名的 UTF-8 字节必须能在 chinese++.exe 里搜到（漏一个 = 二进制是旧的）。
#    C 负例（真编）：每个中文名拿来当标识符 ——
#            真关键字（ZH_KEYWORD 除 module/import、ZH_OPERATOR_KEYWORD）**必须报错**；
#            上下文关键字（module/import、重写、最终）**必须编过**（设计如此）。
#    D 正例 + 中英对照：每条关键字一个最小 TU（中文）与一个等价 TU（英文），
#            两个都必须**编过并跑出 0**（§K0-1 / K0-2）。
#    E 覆盖：每条关键字都必须在 tests\ / examples\ 里至少出现一次（"登记了但没人用"也是缺口）。
#
#  用法：
#    pwsh -NoProfile -File tools\check_keywords.ps1            # 全跑
#    pwsh -NoProfile -File tools\check_keywords.ps1 -Only A,B,C
#    退出码：0 = 全过；非 0 = 有失败（可直接接进闸门）
# ============================================================================
param(
    [string]   $Root    = 'E:\Chinese++',
    [string[]] $Only    = @('A','B','C','D','E'),
    [string]   $Cxx     = 'build\Release\bin\chinese++.exe',
    [string]   $WorkDir = 'build\_zhkw'
)
$ErrorActionPreference = 'Stop'
# ⚠ `pwsh -File x.ps1 -Only A,B` **不会**按逗号拆数组（本项目踩过的坑，见 §17.x 工具注记）
#   ⇒ 在这里自己拆一次，否则 -Only A,B 会被当成一个叫 "A,B" 的字符串 ⇒ 一段都不跑 ✗。
$Only = @($Only | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
$fail = 0
function 标题($t) { Write-Host ''; Write-Host ("=== $t ===") -ForegroundColor Cyan }
function 过($t)   { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t)   { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }
function 提($t)   { Write-Host ("  [注意] $t") -ForegroundColor Yellow }

$kwDef  = Join-Path $Root 'LLVM-main\clang\include\clang\Basic\ChineseKeywords.def'
$tkDef  = Join-Path $Root 'LLVM-main\clang\include\clang\Basic\TokenKinds.def'
$idInfo = Join-Path $Root 'LLVM-main\clang\include\clang\Basic\IdentifierTable.h'   # IdentifierInfo 的声明在这里（不在 Lex 下）
$exe    = Join-Path $Root $Cxx
$work   = Join-Path $Root $WorkDir
foreach ($p in @($kwDef, $tkDef, $idInfo, $exe)) {
    if (-not (Test-Path $p)) { Write-Host "❌ 缺文件：$p" -ForegroundColor Red; exit 2 }
}
if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work -Force | Out-Null }
# TokenKinds.def 的正文在顶层读一次：A 相要用它做"英文名存在性"，D 相要用它取**运算符的源码拼写**
# （`CXX_KEYWORD_OPERATOR(and, ampamp)` 的第一个字段才是能写进源码的 `and`）。
# ⚠ 第一版把它写在 A 相块里 ⇒ 只跑 `-Only D` 时它是空的 ⇒ 运算符的英文版全编不过（假失败）✗。
$tk = [System.IO.File]::ReadAllText($tkDef)
$操作符拼写 = @{}
foreach ($m in [regex]::Matches($tk, 'CXX_KEYWORD_OPERATOR\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)')) { $操作符拼写[$m.Groups[2].Value] = $m.Groups[1].Value }
$C标准 = @('c89','c90','c99','c11','c17','c18','c23','gnu89','gnu90','gnu99','gnu11','gnu17','gnu23')

# ---------------------------------------------------------------------------
#  解析 ChineseKeywords.def（4 种宏族，一个不漏）
# ---------------------------------------------------------------------------
$kw = @()   # 每条：@{ 中=; 英=; 类=; 标志=; setter= }
foreach ($line in [System.IO.File]::ReadAllLines($kwDef)) {
    $l = $line.Trim()
    if ($l -match '^ZH_KEYWORD\(\s*([A-Za-z_]\w*)\s*,\s*(\S+?)\s*,\s*([^)]+?)\s*\)') {
        $kw += [pscustomobject]@{ 英 = $Matches[1]; 中 = $Matches[2]; 类 = 'ZH_KEYWORD'; 标志 = $Matches[3].Trim(); setter = '' }
    }
    elseif ($l -match '^ZH_OPERATOR_KEYWORD\(\s*(\S+?)\s*,\s*([A-Za-z_]\w*)\s*\)') {
        $kw += [pscustomobject]@{ 英 = $Matches[2]; 中 = $Matches[1]; 类 = 'ZH_OPERATOR_KEYWORD'; 标志 = ''; setter = '' }
    }
    elseif ($l -match '^ZH_VIRT_SPECIFIER\(\s*([A-Za-z_]\w*)\s*,\s*(\S+?)\s*\)') {
        $kw += [pscustomobject]@{ 英 = $Matches[1]; 中 = $Matches[2]; 类 = 'ZH_VIRT_SPECIFIER'; 标志 = ''; setter = '' }
    }
    elseif ($l -match '^ZH_CONTEXTUAL_KEYWORD\(\s*([A-Za-z_]\w*)\s*,\s*(\S+?)\s*,\s*(\w+)\s*\)') {
        $kw += [pscustomobject]@{ 英 = $Matches[1]; 中 = $Matches[2]; 类 = 'ZH_CONTEXTUAL_KEYWORD'; 标志 = ''; setter = $Matches[3] }
    }
}
$kw = @($kw | Sort-Object 类, 英)
$nK = @($kw | Where-Object { $_.类 -eq 'ZH_KEYWORD' }).Count
$nO = @($kw | Where-Object { $_.类 -eq 'ZH_OPERATOR_KEYWORD' }).Count
$nV = @($kw | Where-Object { $_.类 -eq 'ZH_VIRT_SPECIFIER' }).Count
$nC = @($kw | Where-Object { $_.类 -eq 'ZH_CONTEXTUAL_KEYWORD' }).Count
if (@($Only) -contains 'A') {
    标题 'A 静态检查（表本身 + 与 TokenKinds.def / IdentifierInfo.h 对账）'
    Write-Host ("  解析：共 {0} 条 = ZH_KEYWORD {1} + ZH_OPERATOR_KEYWORD {2} + ZH_VIRT_SPECIFIER {3} + ZH_CONTEXTUAL_KEYWORD {4}" -f $kw.Count, $nK, $nO, $nV, $nC)
    if ($kw.Count -eq 0) { 错 '解析到 0 条 —— 表读不出来（跑 0 条的通过不是通过）' }
    if ($nC -eq 0) { 错 'ZH_CONTEXTUAL_KEYWORD 一条都没解析到 —— py 校验器也不查它，正好是盲区' }

    # A1 中文名：汉字 + 数字（但**不得以数字开头**，铁律④）/ 2–6 个汉字 / 唯一
    #    ⚠ 不是"纯汉字"：`字符16位` / `字符32位` / `字符8位` 是**故意带数字**的（char16_t 一族），
    #      项目定则是"不得以数字开头 + 至少两个汉字"，不是"不许有数字"。
    $取汉字 = { param($s) ([regex]::Matches($s, '[\u4e00-\u9fff]')).Count }
    $非法字 = @($kw | Where-Object { $_.中 -notmatch '^[\u4e00-\u9fff0-9]+$' })
    if ($非法字.Count) { $非法字 | ForEach-Object { 错 ("中文名含非法字符（只允许汉字与数字）：{0}（{1}）" -f $_.中, $_.英) } } else { 过 '全部中文名只由汉字与数字组成（无全角标点/拉丁字母/空格）' }
    $数字头 = @($kw | Where-Object { $_.中 -match '^[0-9]' })
    if ($数字头.Count) { $数字头 | ForEach-Object { 错 ("中文名以数字开头（铁律④）：{0}（{1}）" -f $_.中, $_.英) } } else { 过 '没有中文名以数字开头（铁律④）' }
    $短 = @($kw | Where-Object { (& $取汉字 $_.中) -lt 2 }); if ($短.Count) { $短 | ForEach-Object { 错 ("中文名不足两个汉字：{0}（{1}）" -f $_.中, $_.英) } } else { 过 '全部中文名都 ≥2 个汉字（铁律④伴随项）' }
    $长 = @($kw | Where-Object { (& $取汉字 $_.中) -gt 6 }); if ($长.Count) { $长 | ForEach-Object { 错 ("中文名超过 6 个汉字：{0}（{1}）" -f $_.中, $_.英) } } else { 过 '全部中文名都 ≤6 个汉字（定则 2–6）' }
    #    唯一性：同一个中文名只能指**同一个英文名**（`模块`/`导入` 在 ZH_KEYWORD 与
    #    ZH_CONTEXTUAL_KEYWORD 里各出现一次是**设计如此**：同一个关键字的第二扇门）。
    $重中 = @($kw | Group-Object 中 | Where-Object { @($_.Group | Select-Object -ExpandProperty 英 -Unique).Count -gt 1 })
    if ($重中.Count) { $重中 | ForEach-Object { 错 ("中文名重复且指向不同英文名：{0} —— {1}" -f $_.Name, (($_.Group | ForEach-Object { $_.类 + ':' + $_.英 }) -join ' , ')) } } else { 过 ("中文名两两不同（{0} 条按中文名去重后 {1} 个；同一英文名的两扇门（模块/导入）算一个）" -f $kw.Count, @($kw | Group-Object 中).Count) }

    # A2 英文名必须真的存在于 clang 的关键字来源里（4 种宏族都查 —— py 校验器漏了 CONTEXTUAL 那族）
    #    来源有三处，缺一处就会误报：
    #      ① TokenKinds.def 的 KEYWORD / PPKEYWORD / PUNCTUATOR 三类 + CXX_KEYWORD_OPERATOR 的别名
    #      ② Traits.td 的 `let Spelling = "xxx"`（alignof / sizeof / final / override / co_await 在这）
    $tkNames = @{}
    foreach ($pat in @(
        '(?m)^\s*(?:[A-Z0-9_]+_)?KEYWORD\s*\(\s*([A-Za-z_]\w*)',   # KEYWORD / CXX11_KEYWORD / C99_KEYWORD / MODULES_KEYWORD …
        '(?m)^\s*PPKEYWORD\s*\(\s*([A-Za-z_]\w*)',
        '(?m)^\s*PUNCTUATOR\s*\(\s*([A-Za-z_]\w*)',                # 运算符替代拼写的 tok 名（ampamp 等）就在这里
        '(?m)^\s*CXX_KEYWORD_OPERATOR\s*\(\s*[A-Za-z_]\w*\s*,\s*([A-Za-z_]\w*)'
    )) { foreach ($m in [regex]::Matches($tk, $pat)) { $tkNames[$m.Groups[1].Value] = 'TokenKinds.def' } }
    $traits = Join-Path $Root 'LLVM-main\clang\include\clang\Basic\Traits.td'
    if (Test-Path $traits) {
        foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($traits), 'let\s+Spelling\s*=\s*"([^"]+)"')) { $tkNames[$m.Groups[1].Value] = 'Traits.td' }
    }
    $缺英 = @($kw | Where-Object { $_.类 -ne 'ZH_VIRT_SPECIFIER' -and -not $tkNames.ContainsKey($_.英) })
    if ($缺英.Count) { $缺英 | ForEach-Object { 错 ("英文名不在 TokenKinds.def / Traits.td 里：{0}（{1} / {2}）" -f $_.英, $_.中, $_.类) } }
    else {
        $查英 = @($kw | Where-Object { $_.类 -ne 'ZH_VIRT_SPECIFIER' })
        $按源 = @($查英 | Group-Object { $tkNames[$_.英] } | ForEach-Object { "{0} {1} 条" -f $_.Name, $_.Count }) -join '，'
        过 ("全部 {0} 个英文名都能在 clang 的关键字来源里找到（{1}；两类来源合计 {2} 个名字）" -f $查英.Count, $按源, $tkNames.Count)
    }

    # A2b 虚说明符族（override/final）：它们**本来就不在 TokenKinds.def 里**（是"有特殊含义的标识符"），
    #     所以判据也不同：① 英文拼写必须仍由 Parser 处理（`Ident_<英文名>`）；
    #     ② 中文拼写必须经宏体**字符串化** `#ZH` 取出 —— 文档 §九 坑一 就是漏了这个 `#`，
    #        结果是"编译通过但中文静默失效"（只有真编译才炸，静态表检查看不出来）。
    $virt = @($kw | Where-Object { $_.类 -eq 'ZH_VIRT_SPECIFIER' })
    if ($virt.Count) {
        $pdcxx = Join-Path $Root 'LLVM-main\clang\lib\Parse\ParseDeclCXX.cpp'
        $src = if (Test-Path $pdcxx) { [System.IO.File]::ReadAllText($pdcxx) } else { '' }
        if (-not $src) { 错 '读不到 ParseDeclCXX.cpp，虚说明符无法核对' }
        else {
            $没有英 = @($virt | Where-Object { $src -notmatch ('\bIdent_' + [regex]::Escape($_.英) + '\b') })
            if ($没有英.Count) { $没有英 | ForEach-Object { 错 ("虚说明符的英文拼写没被 Parser 处理（找不到 Ident_{0}）：{1}" -f $_.英, $_.中) } }
            else { 过 ("{0} 个虚说明符的英文拼写仍由 Parser 处理（{1}）" -f $virt.Count, (($virt | ForEach-Object { 'Ident_' + $_.英 }) -join ' , ')) }
            if ($src -notmatch 'ZH_VIRT_SPECIFIER\(\s*NAME\s*,\s*ZH\s*\)[\s\S]{0,120}get\(#ZH\)') {
                错 '虚说明符宏体没有把中文名字符串化（缺 `#ZH`）—— 文档 §九 坑一：会编译失败或中文静默失效'
            } else { 过 '虚说明符宏体用 `#ZH` 把中文名字符串化（文档 §九 坑一的那个坑已堵）' }
            $没进表 = @($virt | Where-Object { $src -notmatch ('ChineseKeywords\.def') })
            if ($没进表.Count) { 提 'ParseDeclCXX.cpp 里没有出现 ChineseKeywords.def 的 #include —— 确认它经 Parser.h 间接包含' }
        }
    }

    # A3 上下文族的 SETTER 必须是 IdentifierInfo 的真方法
    $ii = [System.IO.File]::ReadAllText($idInfo)
    $ctx = @($kw | Where-Object { $_.类 -eq 'ZH_CONTEXTUAL_KEYWORD' })
    $坏Setter = @($ctx | Where-Object { $ii -notmatch ('\b' + [regex]::Escape($_.setter) + '\s*\(') })
    if ($ctx.Count -eq 0) { 提 '没有解析到上下文族条目' }
    elseif ($坏Setter.Count) { $坏Setter | ForEach-Object { 错 ("上下文族的 SETTER 不是 IdentifierInfo 的方法：{0}({1})" -f $_.setter, $_.英) } }
    else { 过 ("上下文族 {0} 条的 SETTER 都是 IdentifierInfo 的真方法：{1}" -f $ctx.Count, (($ctx | ForEach-Object { $_.setter }) -join ' , ')) }

    # A4 上下文族的中文名必须与同名 ZH_KEYWORD 行逐字一致（两处不一致 = 一半中文一半英文）
    foreach ($c in $ctx) {
        $same = @($kw | Where-Object { $_.类 -eq 'ZH_KEYWORD' -and $_.英 -eq $c.英 })
        if ($same.Count -eq 0) { 提 ("上下文族 {0} 在 ZH_KEYWORD 里没有同名行（那它就是只在特殊位置有含义）" -f $c.英) }
        elseif ($same[0].中 -ne $c.中) { 错 ("同一英文名两处中文不一致：{0} = {1}（ZH_KEYWORD） vs {2}（CONTEXTUAL）" -f $c.英, $same[0].中, $c.中) }
    }
    if ($ctx.Count) { 过 '上下文族的中文名与同名 ZH_KEYWORD 行逐字一致' }

    # A5 标志合法性（只做"非空且由大写字母/下划线/竖线组成"，深查交给 py 校验器）
    $坏标志 = @($kw | Where-Object { $_.类 -eq 'ZH_KEYWORD' -and $_.标志 -notmatch '^[A-Z0-9_| ]+$' })
    if ($坏标志.Count) { $坏标志 | ForEach-Object { 错 ("标志写法可疑：{0} -> '{1}'" -f $_.英, $_.标志) } } else { 过 'ZH_KEYWORD 的标志都是大写枚举写法' }
}

# ---------------------------------------------------------------------------
#  B 二进制检查：中文拼写必须真的在 chinese++.exe 里（抓"二进制是旧的/硬链接断了"）
# ---------------------------------------------------------------------------
if (@($Only) -contains 'B') {
    标题 'B 二进制检查（chinese++.exe 里必须真的含这些拼写）'
    $bytes = [System.IO.File]::ReadAllBytes($exe)
    $txt   = [System.Text.Encoding]::UTF8.GetString($bytes)
    $缺 = @()
    foreach ($k in $kw) { if (-not $txt.Contains($k.中)) { $缺 += $k } }
    if ($缺.Count) { $缺 | ForEach-Object { 错 ("二进制里搜不到中文拼写：{0}（{1}）—— 很可能 chinese++.exe 是旧的" -f $_.中, $_.英) } }
    else { 过 ("{0} 个中文拼写全部能在 {1}（{2:N1} MB）里搜到 ⇒ 二进制与表一致" -f $kw.Count, (Split-Path $exe -Leaf), ($bytes.Length / 1MB)) }
    # 旧译名必须已经不在二进制里（改名的负面对照）
    foreach ($旧 in @('动态绑定')) {
        if ($txt.Contains($旧)) { 错 ("旧译名 '{0}' 仍在二进制里 —— 改名没生效" -f $旧) } else { 过 ("旧译名 '{0}' 已不在二进制里（改名生效）" -f $旧) }
    }
}

# ---------------------------------------------------------------------------
#  C 负例：拿关键字当标识符用
#     · 真关键字 => 必须报错
#     · 上下文关键字（module/import、重写、最终）=> 必须编过（设计如此，见文档 §四.1）
# ---------------------------------------------------------------------------
#  上下文族集合（两类）：ZH_CONTEXTUAL_KEYWORD 的中文名 + ZH_VIRT_SPECIFIER 的中文名
$上下文 = @{}
foreach ($k in $kw) { if ($k.类 -eq 'ZH_CONTEXTUAL_KEYWORD' -or $k.类 -eq 'ZH_VIRT_SPECIFIER') { $上下文[$k.中] = $k } }
foreach ($k in $kw) { if ($k.类 -eq 'ZH_KEYWORD' -and $上下文.ContainsKey($k.中)) { $上下文[$k.中] = $k } }

if (@($Only) -contains 'C') {
    标题 'C 负例（真编）：真关键字当标识符必须报错；上下文关键字必须能当标识符'
    #  ⚠ 语言模式必须与 .def 里的 FLAGS 一致，否则会**误报**：
    #    `受限`(restrict) 是 KEYC99 —— 在 C++ 里它本来就只是普通标识符 ✓；
    #    `取类型`(typeof) / `取无修饰类型`(typeof_unqual) 是 KEYC23 —— 同理。
    #    实测（本脚本第一版）：这三条在 -std=c++20 下"能当标识符"，被判成失败 ✗ —— 是判据错，不是表错。
    function 取模式($标志) {
        if ($标志 -match 'KEYCXX|KEYALL|KEYMODULES|BOOLSUPPORT|CHAR8SUPPORT|WCHARSUPPORT|HALFSUPPORT') { return @('c++20', 'cpp') }
        if ($标志 -match 'KEYC99') { return @('c11', 'c') }
        if ($标志 -match 'KEYC23') { return @('c23', 'c') }
        return @('c++20', 'cpp')
    }
    $该错没错 = @(); $该过没过 = @(); $模式统计 = @{}
    #  ⚠ 编译开关必须**整串**传：`& $exe -std=$m ...` 在 PowerShell 里**不会**展开 `$m`
    #    （实测报 `（选项）'-std=$m' 中的值 '$m' 无效`）⇒ 每一次探针都"编译失败"⇒
    #    真关键字"全部被拒绝"会变成**假通过** ✗（本脚本第一版就栽在这，见下面的自测）。
    function 试编译($文件, $标准) {
        $flag = '-std=' + $标准
        $t = (& $exe $flag -ferror-limit=0 -fsyntax-only $文件 2>&1 | Out-String)
        return ($t -match '(?m)error')
    }
    # 自测（负面对照）：机制本身必须先被证明能分辨"关键字"与"普通标识符"
    $自测A = Join-Path $work 'selftest_keyword.cpp'
    $自测B = Join-Path $work 'selftest_notkeyword.cpp'
    [System.IO.File]::WriteAllText($自测A, '整数 如果 = 0;', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($自测B, '整数 这不是关键字 = 0;', (New-Object System.Text.UTF8Encoding($false)))
    $自测A错 = 试编译 $自测A 'c++20'
    $自测B错 = 试编译 $自测B 'c++20'
    Remove-Item $自测A, $自测B -Force
    if (-not $自测A错) { 错 '自测：已知关键字 如果 当标识符竟然没报错 ⇒ 判定机制坏了，后面的"通过"都不算数' }
    elseif ($自测B错) { 错 '自测：普通标识符 这不是关键字 竟然报错 ⇒ 判定机制坏了（会把一切判成关键字）' }
    else { 过 '自测：已知关键字 如果 被拒、普通标识符 这不是关键字 放行 ⇒ 判定机制有效（下面的结论才算数）' }
    foreach ($k in $kw) {
        $m = 取模式 $k.标志
        $模式统计[$m[0]] = 1 + [int]$模式统计[$m[0]]
        $p = Join-Path $work ('c_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.' + $m[1])
        [System.IO.File]::WriteAllText($p, ("整数 {0} = 0;`n" -f $k.中), (New-Object System.Text.UTF8Encoding($false)))
        $报错 = 试编译 $p $m[0]
        Remove-Item $p -Force
        if ($上下文.ContainsKey($k.中)) { if ($报错) { $该过没过 += $k } }
        else { if (-not $报错) { $该错没错 += $k } }
    }
    if ($该错没错.Count) { $该错没错 | ForEach-Object { 错 ("真关键字当标识符居然编过了（在它自己的语言模式 {0} 下）：{1}（{2} / {3}）" -f (取模式 $_.标志)[0], $_.中, $_.英, $_.类) } }
    else { 过 ("{0} 个真关键字在各自的语言模式（{1}）下当标识符全部被编译器拒绝" -f @($kw | Where-Object { -not $上下文.ContainsKey($_.中) }).Count, (($模式统计.Keys | Sort-Object | ForEach-Object { "$_ $($模式统计[$_]) 条" }) -join '，')) }
    if ($该过没过.Count) { $该过没过 | ForEach-Object { 错 ("上下文关键字当标识符应当合法，却报错了：{0}（{1} / {2}）" -f $_.中, $_.英, $_.类) } }
    else { 过 ("{0} 个上下文关键字（模块/导入/重写/最终）当标识符都合法（与文档 §四.1 一致）" -f $上下文.Count) }
    Get-ChildItem $work -Filter 'c_*' -ErrorAction SilentlyContinue | Remove-Item -Force
}

# ---------------------------------------------------------------------------
#  E 覆盖：每条关键字都必须在 tests\ / examples\ 里至少出现过一次
# ---------------------------------------------------------------------------
if (@($Only) -contains 'E') {
    标题 'E 覆盖检查：每条关键字都要在 tests\ / examples\ 的源码里真出现过'
    $src = @()
    $src += Get-ChildItem (Join-Path $Root 'tests')   -Recurse -Include *.cpp,*.txt -File -ErrorAction SilentlyContinue
    $src += Get-ChildItem (Join-Path $Root 'examples') -Recurse -Include *.cpp,*.h -File -ErrorAction SilentlyContinue
    $blob = ($src | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
    $没用 = @($kw | Where-Object { -not $blob.Contains($_.中) })
    if ($没用.Count) {
        提 ("有 {0} 条关键字在 tests/examples 的所有源码里一次都没出现过（不是错，但等于没人用过）：" -f $没用.Count)
        foreach ($k in $没用) { Write-Host ("         {0}（{1} / {2}）" -f $k.中, $k.英, $k.类) }
    } else { 过 ("{0} 条关键字在 tests/examples 里都出现过（扫了 {1} 个文件）" -f $kw.Count, $src.Count) }
}

# ---------------------------------------------------------------------------
#  D 正例 + 中英对照：每条关键字一个最小程序，中文版与英文版**只差那个关键字**，
#    两个都必须编过、跑出 0，并且**输出逐字节相同**（§K0-1 / K0-2 / K0-12）。
#    `%` 是占位符：中文版替换成中文名，英文版替换成英文名。
# ---------------------------------------------------------------------------
$探针 = @(
    # —— 基本类型 ——
    @('整数',        '整数 主函数(){ % 甲 = 3; 返回 甲 - 3; }'),
    @('字符',        '整数 主函数(){ % 甲 = 97; 返回 甲 - 97; }'),
    @('单精度',      '整数 主函数(){ % 甲 = 1.5f; 返回 (整数)甲 - 1; }'),
    @('双精度',      '整数 主函数(){ % 甲 = 1.5; 返回 (整数)甲 - 1; }'),
    @('长型',        '整数 主函数(){ % 甲 = 3; 返回 (整数)甲 - 3; }'),
    @('短型',        '整数 主函数(){ % 甲 = 3; 返回 (整数)甲 - 3; }'),
    @('宽字符',      '整数 主函数(){ % 甲 = 97; 返回 (整数)甲 - 97; }'),
    @('字符8位',     '整数 主函数(){ % 甲 = 97; 返回 (整数)甲 - 97; }'),
    @('字符16位',    '整数 主函数(){ % 甲 = 97; 返回 (整数)甲 - 97; }'),
    @('字符32位',    '整数 主函数(){ % 甲 = 97; 返回 (整数)甲 - 97; }'),
    @('布尔',        '整数 主函数(){ % 甲 = 真值; 返回 甲 ? 0 : 1; }'),
    @('空型',        '% 函数() {} 整数 主函数(){ 函数(); 返回 0; }'),
    @('有符号',      '整数 主函数(){ % 整数 甲 = -1; 返回 甲 < 0 ? 0 : 1; }'),
    @('无符号',      '整数 主函数(){ % 整数 甲 = 1; 返回 (整数)甲 - 1; }'),
    @('真值',        '整数 主函数(){ 返回 % ? 0 : 1; }'),
    @('假值',        '整数 主函数(){ 返回 % ? 1 : 0; }'),
    @('空指针',      '整数 主函数(){ 整数* 甲 = %; 返回 甲 == % ? 0 : 1; }'),
    @('汇编',        '整数 主函数(){ %("nop"); 返回 0; }'),
    # —— 声明与限定 ——
    @('常量',        '整数 主函数(){ % 整数 甲 = 3; 返回 甲 - 3; }'),
    @('常量表达式',  '% 整数 甲 = 3; 整数 主函数(){ 返回 甲 - 3; }'),
    @('立即求值',    '% 整数 甲() { 返回 3; } 整数 主函数(){ 返回 甲() - 3; }'),
    @('常量初始化',  '% 整数 甲 = 3; 整数 主函数(){ 返回 甲 - 3; }'),
    @('静态',        '% 整数 甲 = 3; 整数 主函数(){ 返回 甲 - 3; }'),
    @('外部',        '% 整数 甲 = 3; 整数 主函数(){ 返回 甲 - 3; }'),
    @('线程局部',    '% 整数 甲 = 3; 整数 主函数(){ 返回 甲 - 3; }'),
    # ⚠ `register` 在 C++17 起被移除 ⇒ 中文 `寄存器` 与英文 `register` 在 c++20 下**都**报错
    #   （同样的行为 ✓）⇒ 探针必须在 c++14 下跑，才能验证"能当存储类说明符用"。
    @('寄存器',      '整数 主函数(){ % 整数 甲 = 3; 返回 甲 - 3; }', 'c++14'),
    @('可变',        '类型 甲 { 公开: % 整数 乙; }; 整数 主函数(){ 甲 丙{}; 常量 甲& 丁 = 丙; 丁.乙 = 3; 返回 丙.乙 - 3; }'),
    @('易变',        '% 整数 甲 = 3; 整数 主函数(){ 返回 甲 - 3; }'),
    @('内联',        '% 整数 甲() { 返回 3; } 整数 主函数(){ 返回 甲() - 3; }'),
    @('自动',        '整数 主函数(){ 整数 甲 = 3; % 乙 = 甲; 返回 (整数)乙 - 3; }'),
    @('声明类型',    '整数 主函数(){ 整数 甲 = 3; %(甲) 乙 = 甲; 返回 (整数)乙 - 3; }'),
    @('对齐',        '整数 主函数(){ %(8) 整数 甲 = 3; 返回 甲 - 3; }'),
    @('对齐值',      '整数 主函数(){ 返回 (整数)%(整数) - 4; }'),
    @('大小',        '整数 主函数(){ 返回 (整数)%(整数) - 4; }'),
    @('类型别名',    '% 整数 甲; 整数 主函数(){ 甲 乙 = 3; 返回 乙 - 3; }'),
    @('使用',        '% 甲 = 整数; 整数 主函数(){ 甲 乙 = 3; 返回 乙 - 3; }'),
    @('静态断言',    '%(真值); 整数 主函数(){ 返回 0; }'),
    @('自身',        '类型 甲 { 公开: 整数 乙 = 3; 整数 取() { 返回 %->乙; } }; 整数 主函数(){ 甲 丙; 返回 丙.取() - 3; }'),
    @('类型标识',    '#include <typeinfo>\n整数 主函数(){ 返回 %(整数) == %(整数) ? 0 : 1; }'),
    @('不抛出',      '整数 甲() % { 返回 3; } 整数 主函数(){ 返回 甲() - 3; }'),
    # —— 面向对象 ——
    @('类型',        '% 甲 { 公开: 整数 乙 = 3; }; 整数 主函数(){ 甲 丙; 返回 丙.乙 - 3; }'),
    @('结构',        '% 甲 { 整数 乙 = 3; }; 整数 主函数(){ 甲 丙; 返回 丙.乙 - 3; }'),
    @('共用体',      '% 甲 { 整数 乙; 双精度 丙; }; 整数 主函数(){ 甲 丁{}; 丁.乙 = 3; 返回 丁.乙 - 3; }'),
    @('枚举',        '% 甲 { 一, 二 }; 整数 主函数(){ 返回 (整数)二 - 1; }'),
    @('公开',        '类型 甲 { %: 整数 乙 = 3; }; 整数 主函数(){ 甲 丙; 返回 丙.乙 - 3; }'),
    @('私有',        '类型 甲 { %: 整数 乙 = 3; 公开: 整数 取() { 返回 乙; } }; 整数 主函数(){ 甲 丙; 返回 丙.取() - 3; }'),
    @('受保护',      '类型 甲 { %: 整数 乙 = 3; }; 类型 派 : 公开 甲 { 公开: 整数 取() { 返回 乙; } }; 整数 主函数(){ 派 丙; 返回 丙.取() - 3; }'),
    @('虚拟',        '类型 甲 { 公开: % 整数 取() { 返回 3; } }; 整数 主函数(){ 甲 丙; 返回 丙.取() - 3; }'),
    @('重写',        '类型 基 { 公开: 虚拟 整数 取() { 返回 1; } }; 类型 派 : 公开 基 { 公开: 整数 取() % { 返回 3; } }; 整数 主函数(){ 派 丙; 返回 丙.取() - 3; }'),
    @('最终',        '类型 甲 % { 公开: 整数 乙 = 3; }; 整数 主函数(){ 甲 丙; 返回 丙.乙 - 3; }'),
    @('友元',        '类型 甲 { 公开: 整数 乙 = 3; % 整数 取(常量 甲&); }; 整数 取(常量 甲& 丙) { 返回 丙.乙; } 整数 主函数(){ 甲 丁; 返回 取(丁) - 3; }'),
    @('显式',        '类型 甲 { 公开: 整数 乙 = 3; % 甲(整数 值) : 乙(值) {} 甲() = 默认; }; 整数 主函数(){ 甲 丙(3); 返回 丙.乙 - 3; }'),
    @('运算符',      '类型 甲 { 公开: 整数 乙 = 3; % 整数() 常量 { 返回 乙; } }; 整数 主函数(){ 甲 丙; 返回 (整数)丙 - 3; }'),
    @('新建',        '整数 主函数(){ 整数* 甲 = % 整数(3); 整数 乙 = *甲; 删除 甲; 返回 乙 - 3; }'),
    @('删除',        '整数 主函数(){ 整数* 甲 = 新建 整数(3); 整数 乙 = *甲; % 甲; 返回 乙 - 3; }'),
    # —— 模板与概念 ——
    @('模板',        '% <类型名 元> 元 取(元 值) { 返回 值; } 整数 主函数(){ 返回 取(3) - 3; }'),
    @('类型名',      '模板 <% 元> 元 取(元 值) { 返回 值; } 整数 主函数(){ 返回 取(3) - 3; }'),
    @('概念',        '模板 <类型名 元> % 恒真 = 真值; 整数 主函数(){ 返回 0; }'),
    @('约束',        '模板 <类型名 元> 元 取(元 值) % (大小(元) > 0) { 返回 值; } 整数 主函数(){ 返回 取(3) - 3; }'),
    @('名域',        '% 甲 { 整数 乙 = 3; } 整数 主函数(){ 返回 甲::乙 - 3; }'),
    # —— 转换 ——
    @('静态转换',    '整数 主函数(){ 双精度 甲 = 3.0; 返回 (整数)%<整数>(甲) - 3; }'),
    @('常量转换',    '整数 主函数(){ 整数 甲 = 3; 常量 整数& 乙 = 甲; %<整数&>(乙) = 4; 返回 甲 - 4; }'),
    @('重释转换',    '整数 主函数(){ 整数 甲 = 3; 返回 *(整数*)%<整数*>(&甲) - 3; }'),
    @('动态转换',    '类型 基 { 公开: 虚拟 ~基() {} }; 类型 派 : 公开 基 { 公开: 整数 乙 = 3; }; 整数 主函数(){ 派 丙; 基* 丁 = &丙; 返回 %<派*>(丁)->乙 - 3; }'),
    # —— 控制流 ——
    @('如果',        '整数 主函数(){ 整数 甲 = 3; % (甲 > 2) { 返回 0; } 返回 1; }'),
    @('否则',        '整数 主函数(){ 整数 甲 = 1; 如果 (甲 > 2) { 返回 1; } % { 返回 0; } }'),
    @('对于',        '整数 主函数(){ 整数 和 = 0; % (整数 甲 = 0; 甲 < 3; ++甲) { 和 += 甲; } 返回 和 - 3; }'),
    @('每当',        '整数 主函数(){ 整数 甲 = 0; % (甲 < 3) { ++甲; } 返回 甲 - 3; }'),
    @('执行',        '整数 主函数(){ 整数 甲 = 0; % { ++甲; } 每当 (甲 < 3); 返回 甲 - 3; }'),
    @('选择',        '整数 主函数(){ 整数 甲 = 2; % (甲) { 情形 2: 返回 0; 默认: 返回 1; } }'),
    @('情形',        '整数 主函数(){ 整数 甲 = 2; 选择 (甲) { % 2: 返回 0; 默认: 返回 1; } }'),
    @('默认',        '整数 主函数(){ 整数 甲 = 2; 选择 (甲) { 情形 2: 返回 0; %: 返回 1; } }'),
    @('跳出',        '整数 主函数(){ 整数 和 = 0; 对于 (整数 甲 = 0; 甲 < 9; ++甲) { 如果 (甲 == 3) { %; } 和++; } 返回 和 - 3; }'),
    @('跳过',        '整数 主函数(){ 整数 和 = 0; 对于 (整数 甲 = 0; 甲 < 5; ++甲) { 如果 (甲 == 2) { %; } 和++; } 返回 和 - 4; }'),
    @('跳转',        '整数 主函数(){ 整数 甲 = 0; 如果 (真值) { % 标号; } 甲 = 3; 标号: 返回 甲; }'),
    @('返回',        '整数 取() { % 3; } 整数 主函数(){ 返回 取() - 3; }'),
    # —— 异常 ——
    @('尝试',        '整数 主函数(){ % { 抛出 3; } 捕获 (整数) { 返回 0; } 返回 1; }'),
    @('捕获',        '整数 主函数(){ 尝试 { 抛出 3; } % (整数) { 返回 0; } 返回 1; }'),
    @('抛出',        '整数 主函数(){ 尝试 { % 3; } 捕获 (整数) { 返回 0; } 返回 1; }'),
    # —— 运算符替代拼写 11 条（真关键字；⚠ 中文关键字之间/与标识符之间**必须留空格**：
    #    `并非假值` 会被 maximal-munch 切成**一个标识符** ✗ —— 英文同理（`nottrue` 也不是两个词））——
    @('并且',        '整数 主函数(){ 返回 (真值 % 真值) ? 0 : 1; }'),
    @('或者',        '整数 主函数(){ 返回 (假值 % 真值) ? 0 : 1; }'),
    @('并非',        '整数 主函数(){ 返回 (% 假值) ? 0 : 1; }'),
    @('异或',        '整数 主函数(){ 返回 (1 % 2) - 3; }'),
    @('位与',        '整数 主函数(){ 返回 (3 % 1) - 1; }'),
    @('位或',        '整数 主函数(){ 返回 (2 % 1) - 3; }'),
    @('取反',        '整数 主函数(){ 返回 (% 0) + 1; }'),
    @('与赋值',      '整数 主函数(){ 整数 甲 = 1; 甲 % 2; 返回 甲 - 0; }'),
    @('或赋值',      '整数 主函数(){ 整数 甲 = 0; 甲 % 2; 返回 甲 - 2; }'),
    @('异或赋值',    '整数 主函数(){ 整数 甲 = 1; 甲 % 1; 返回 甲 - 0; }'),
    @('不等于',      '整数 主函数(){ 返回 (1 % 2) ? 0 : 1; }'),
    # —— 只在 C 方言里才是关键字的三条（与英文 restrict/typeof 的适用范围一致）——
    @('受限',        'int main(){ int* % 甲 = 0; return 甲 == 0 ? 0 : 1; }', 'c11'),
    @('取类型',      'int main(){ int 甲 = 3; %(甲) 乙 = 甲; return (int)乙 - 3; }', 'c23'),
    @('取无修饰类型','int main(){ int 甲 = 3; %(甲) 乙 = 甲; return (int)乙 - 3; }', 'c23')
)
# 需要单独构造的（模块/协程）：见下面的专门分支
$特殊 = @('模块','导入','导出','协程等待','协程返回','协程产出')

if (@($Only) -contains 'D') {
    标题 'D 正例 + 中英对照（每条关键字：中文版编过并跑 0，英文版编过并跑 0，输出逐字节相同）'
    $表 = @{}
    foreach ($e in $探针) { $表[$e[0]] = $e[1] }
    $漏 = @($kw | Where-Object { $_.类 -ne 'ZH_VIRT_SPECIFIER' -and -not $表.ContainsKey($_.中) -and $特殊 -notcontains $_.中 } | Sort-Object 中 -Unique)
    if ($漏.Count) { $漏 | ForEach-Object { 错 ("探针表缺条目：{0}（{1}）—— 未覆盖就必须报出来，不许静默少查" -f $_.中, $_.英) } }
    else { 过 ("探针表覆盖把 {0} 条关键字全部列出（另有 {1} 条走专门分支：{2}）" -f $表.Count, $特殊.Count, ($特殊 -join ' ')) }
    #  英文拼写：ZH_OPERATOR_KEYWORD 的第二个字段是**token 名**（ampamp），不是源码拼写
    #  —— 源码拼写是 `CXX_KEYWORD_OPERATOR(and, ampamp)` 的**第一个**字段（`and`）。
    #  第一版直接拿 ampamp 去替英文版 ⇒ `甲 ampamp= 2;` 当然编不过 ✗（判据错，不是表错）。
    $过数 = 0; $坏 = @()
    foreach ($e in ($探针 | Sort-Object { $_[0] })) {
        $中名 = $e[0]; $片段 = $e[1] -replace '\\n', "`n"; $标准 = if ($e.Count -gt 2) { $e[2] } else { 'c++20' }
        $行 = @($kw | Where-Object { $_.中 -eq $中名 })[0]
        $英名 = if ($行.类 -eq 'ZH_OPERATOR_KEYWORD' -and $操作符拼写.ContainsKey($行.英)) { $操作符拼写[$行.英] } else { $行.英 }
        # C 方言要 `-x c`，否则驱动按扩展名把 .cpp 当 C++ ⇒ `-std=c11` 直接报
        # "不能与（选项）'C++' 一起使用" ✗（第一版就栽在这）。文件后缀也换成 .c。
        $是C = $C标准 -contains $标准
        $后 = if ($是C) { '.c' } else { '.cpp' }
        $p中 = Join-Path $work ('d_' + $中名 + '_' + $后)
        $p英 = Join-Path $work ('d_' + $中名 + '_en' + $后)
        [System.IO.File]::WriteAllText($p中, ($片段 -replace '%', $中名), (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($p英, ($片段 -replace '%', $英名), (New-Object System.Text.UTF8Encoding($false)))
        $exe中 = Join-Path $work ('d_' + $中名 + '_.exe')
        $exe英 = Join-Path $work ('d_' + $中名 + '_en.exe')
        $额外 = if ($是C) { @('-x', 'c') } else { @() }
        $编中 = (& $exe @额外 ('-std=' + $标准) -ferror-limit=0 -o $exe中 $p中 2>&1 | Out-String)
        $编英 = (& $exe @额外 ('-std=' + $标准) -ferror-limit=0 -o $exe英 $p英 2>&1 | Out-String)
        if ($编中 -match '(?m)error') { $坏 += ("{0}（中文版编不过 / {1}）：{2}" -f $中名, $标准, (($编中 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1))); continue }
        if ($编英 -match '(?m)error') { $坏 += ("{0}（英文版 {1} 编不过 / {2}）：{3}" -f $中名, $英名, $标准, (($编英 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1))); continue }
        $出中 = (& $exe中 2>&1 | Out-String); $码中 = $LASTEXITCODE
        $出英 = (& $exe英 2>&1 | Out-String); $码英 = $LASTEXITCODE
        if ($码中 -ne 0) { $坏 += ("{0}：中文版运行返回 {1}" -f $中名, $码中); continue }
        if ($码英 -ne 0) { $坏 += ("{0}：英文版运行返回 {1}" -f $中名, $码英); continue }
        if ($出中 -ne $出英) { $坏 += ("{0}：中英两版输出不同（'{1}' vs '{2}'）" -f $中名, $出中.Trim(), $出英.Trim()); continue }
        $过数++
    }
    if ($坏.Count) { $坏 | ForEach-Object { 错 $_ } } else { 过 ("{0} 条关键字：中文版与英文版都编过、都跑出 0、输出逐字节相同" -f $过数) }
    Get-ChildItem $work -Filter 'd_*' -ErrorAction SilentlyContinue | Remove-Item -Force

    # ---- 专门分支 1：模块 / 导入 / 导出（真做一个模块：界面 + 消费者，真编真跑）----
    function 试模块($模块名, $界面, $消费, $标签) {
        $ixx = Join-Path $work ($标签 + '.cppm'); $cpp = Join-Path $work ($标签 + '.cpp')
        [System.IO.File]::WriteAllText($ixx, $界面, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($cpp, $消费, (New-Object System.Text.UTF8Encoding($false)))
        $pcm = Join-Path $work ($标签 + '.pcm'); $obj = Join-Path $work ($标签 + '.obj'); $exe2 = Join-Path $work ($标签 + '.exe')
        foreach ($f in @($pcm, $obj, $exe2)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        $o1 = (& $exe '-std=c++20' '-x' 'c++-module' '--precompile' $ixx '-o' $pcm 2>&1 | Out-String)
        if ($o1 -match '(?m)error') { return @{ 好 = $false; 因 = "预编译失败：" + (($o1 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1)) } }
        $o2 = (& $exe '-std=c++20' '-x' 'c++-module' '-c' $ixx '-o' $obj 2>&1 | Out-String)
        if ($o2 -match '(?m)error') { return @{ 好 = $false; 因 = "界面 codegen 失败：" + (($o2 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1)) } }
        $o3 = (& $exe '-std=c++20' ("-fmodule-file=$模块名=$pcm") $cpp $obj '-o' $exe2 2>&1 | Out-String)
        if ($o3 -match '(?m)error') { return @{ 好 = $false; 因 = "消费者编译/链接失败：" + (($o3 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1)) } }
        $出 = (& $exe2 2>&1 | Out-String); $码 = $LASTEXITCODE
        return @{ 好 = ($码 -eq 0); 因 = "运行返回 $码"; 出 = $出 }
    }
    $界中 = "导出 模块 甲;`n导出 整数 取() { 返回 3; }`n"
    $用中 = "导入 甲;`n整数 主函数(){ 返回 取() - 3; }`n"
    $界英 = "export module 甲;`nexport int 取() { return 3; }`n"
    $用英 = "import 甲;`nint main(){ return 取() - 3; }`n"
    $中 = 试模块 '甲' $界中 $用中 'mod_zh'
    $英 = 试模块 '甲' $界英 $用英 'mod_en'
    if (-not $中.好) { 错 ("模块/导出/导入（中文版）失败：{0}" -f $中.因) }
    elseif (-not $英.好) { 错 ("模块/导出/导入（英文版 export/import）失败：{0}" -f $英.因) }
    elseif ($中.出 -ne $英.出) { 错 ("模块：中英两版输出不同（'{0}' vs '{1}'）" -f $中.出.Trim(), $英.出.Trim()) }
    else { 过 '模块 / 导出 / 导入：中文版与英文版各建一个真模块（预编译 → 出对象 → 消费者链接 → 运行）都跑出 0、输出相同' }
    Get-ChildItem $work -Filter 'mod_*' -ErrorAction SilentlyContinue | Remove-Item -Force

    # ---- 专门分支 2：协程三条（协程等待 / 协程返回 / 协程产出）----
    $协程前 = @'
#包含 <协程>
结构 任务 {
    结构 承诺类型 {
        任务 get_return_object() { 返回 {}; }
        标准::始终挂起 initial_suspend() noexcept { 返回 {}; }
        标准::始终挂起 final_suspend() noexcept { 返回 {}; }
        空型 return_void() noexcept {}
        空型 unhandled_exception() noexcept {}
        标准::始终挂起 yield_value(整数) noexcept { 返回 {}; }
    };
    使用 promise_type = 承诺类型;
};
'@
    foreach ($c in @(@('协程返回', '协程返回;', 'co_return;'),
                     @('协程产出', '协程产出 1;', 'co_yield 1;'),
                     @('协程等待', '协程等待 标准::始终挂起{};', 'co_await 标准::始终挂起{};'))) {
        $p中 = Join-Path $work ('co_' + $c[0] + '_.cpp'); $p英 = Join-Path $work ('co_' + $c[0] + '_en.cpp')
        $尾 = "`n整数 主函数(){ 自动 句 = 甲(); (空型)句; 返回 0; }`n"
        [System.IO.File]::WriteAllText($p中, ($协程前 + "任务 甲() { " + $c[1] + " }" + $尾), (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($p英, ($协程前 + "任务 甲() { " + $c[2] + " }" + $尾), (New-Object System.Text.UTF8Encoding($false)))
        $e中 = Join-Path $work ('co_' + $c[0] + '_.exe'); $e英 = Join-Path $work ('co_' + $c[0] + '_en.exe')
        $o中 = (& $exe '-std=c++20' '-isystem' (Join-Path $Root 'zhstdlib') -ferror-limit=0 -o $e中 $p中 2>&1 | Out-String)
        $o英 = (& $exe '-std=c++20' '-isystem' (Join-Path $Root 'zhstdlib') -ferror-limit=0 -o $e英 $p英 2>&1 | Out-String)
        if ($o中 -match '(?m)error') { 错 ("{0}（中文版编不过）：{1}" -f $c[0], (($o中 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1))) ; continue }
        if ($o英 -match '(?m)error') { 错 ("{0}（英文版 {1} 编不过）：{2}" -f $c[0], $c[2], (($o英 -split "`n" | Where-Object { $_ -match 'error' } | Select-Object -First 1))); continue }
        $null = & $e中; $k中 = $LASTEXITCODE; $null = & $e英; $k英 = $LASTEXITCODE
        if ($k中 -ne 0 -or $k英 -ne 0) { 错 ("{0}：中文版 {1} / 英文版 {2}" -f $c[0], $k中, $k英) }
        else { 过 ("{0}：中文版（{1}）与英文版（{2}）都编过并跑出 0" -f $c[0], $c[1], $c[2]) }
    }
    Get-ChildItem $work -Filter 'co_*' -ErrorAction SilentlyContinue | Remove-Item -Force
}

标题 '结论'
Write-Host ("  关键字：{0} 条（ZH_KEYWORD {1} / 操作符 {2} / 虚说明符 {3} / 上下文 {4}）；失败 {5} 项" -f $kw.Count, $nK, $nO, $nV, $nC, $fail)
if ($fail -eq 0) { Write-Host '  ✅ 全部通过' -ForegroundColor Green; exit 0 } else { Write-Host '  ❌ 有失败项（见上）' -ForegroundColor Red; exit 1 }
