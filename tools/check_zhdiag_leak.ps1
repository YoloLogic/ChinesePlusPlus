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
    'identifier',
    # §18.8 P-09 收尾时加的：**表达式**里的运算符也是同一类残留
    # （实测 `（表达式）'sizeof(整数) > 99'` —— 类型已经中文、运算符还是英文）。
    'sizeof', 'alignof'
)

# ⚠ 还没进黑名单、但**同类**的（登记为 P-13，见台账）：表达式打印里其余英文关键字 ——
#   转换（`static_cast<…>`）、`new`/`delete`、`true`/`false`、`this`、`typeid`…
#   它们走 StmtPrinter 的另一些分支，本次只修了测试撞到的 `sizeof`/`alignof`。
#   加进黑名单之前先确认那些分支也改了，否则守卫会红得没有意义。

# 有意【不】列入黑名单的（写明理由，免得后来者以为是漏了）：
#   template        —— `'template<>'` 是用户要【照写】的语法，中文消息里保留英文有据
#                      （`模板` 也可以写，但两种拼写在源码里并存，回显哪个都不算错）
#   and/or/not/…    —— 运算符替代拼写，`运算符&&` 与 `运算符 并且` 并存
#   __int128 / _BitInt / _Accum / _Fract / __vector / __interface / half
#                   —— 实现拼写，中文关键字表里【本来就没有】对应译名
#   ISO / C++ / C2y / OpenACC / HLSL / GCC / MSVC —— 专名与标准名

#                                                                  （§18.8 P-09 / D-04）
#   内建类型名**不再**是残留了：只要中文诊断开着，TypePrinter 就打中文（`整数`/`双精度`/
#   `整数 *`/`标准::向量<整数>`），关掉（-fno-chinese-diagnostics）打回英文。
#   所以这里现在**空着** —— 留这张表是为了下一个同类欠账有地方登记。
$已知未修 = @()

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
    # §18.8 P-09：类型名汉化之后，指针类型也必须跟着（`整数 *` 而不是 `int *`）
    @('L12-指针类型不匹配',   '整数* 甲 = 1; 整数 主函数(){ 返回 0; }'),
    # §18.8 P-09：**模板实参**走的是另一条打印路（%diff / TemplateDiff，
    # 它过去用 LangOptions 建策略 ⇒ 只有这条路漏英文：`盒<int>`）。
    @('L13-模板类型不匹配',   '模板 <类型名 甲> 结构 盒 { 甲 内容; }; 整数 主函数(){ 盒<整数> 甲{}; 盒<双精度> 乙 = 甲; 返回 0; }'),
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

# ---------------------------------------------------------------------------
#  附加（§18.8 P-08）：中文表**自己的** `%select{...}` 备选串不许留英文
#
#  为什么要单列一条：上面那条判据看的是**渲染出来的正文**（实参黑名单），
#  而中文表里还有一类英文藏在 `%select{a|b}` 的**备选串**里 —— 它同样是用户
#  看到的正文，却不在上面那条路径上。P-08 就是"只扫表"扫出来的。
#
#  第一版判据（10 个**写死的英文形态**出现 0 次）是个**假守卫**：
#  它钉的是字符串字面量 —— 同一个词换个写法（`%select{NULL|nullptr}1` 而不是
#  `'%select{NULL|nullptr}0'`）就从缝里漏过去了（实测真漏了一条）。
#  现在换成**与关键字表同源**的判据：
#
#  判据①（覆盖面最大）：备选串只要等于**中文关键字表已经译过的英文拼写**
#    （if/switch/void/nullptr/final/… 共 88 个，直接从 ChineseKeywords.def 读），
#    就必须是中文；只有在 `$备选豁免` 里**逐条写明理由**的才允许留英文
#    （代码里要照写的名字：doxygen 命令名 `\class`、ObjC 属性特性名、ObjC 方法族名、
#     GNU 属性名）。豁免表还**必须条条命中**（登记虚着就红）。
#  判据②（处数登记）：某些"术语刚定/待定"的备选串按**处数**登记 ——
#    登记处数必须**正好等于**实测处数（英文往回长就红；翻干净了就把登记钉成 0）。
#    现在：`lambda` 已按 D-07 = **匿名函数** 全部翻掉 ⇒ 钉 0 处。
#  判据③（防新增）：纯英文备选串**总出现次数**不得超过登记上限 ——
#    新增英文一律要显式改这个数（第一版判据完全没有这层）。
# ---------------------------------------------------------------------------
$tbl = Join-Path $Root 'llvm-main\clang\include\clang\Basic\ChineseDiagnostics.def'
$kwFile = Join-Path $Root 'llvm-main\clang\include\clang\Basic\ChineseKeywords.def'
if ((Test-Path $tbl) -and (Test-Path $kwFile)) {
    # 已译英文关键字拼写（判据①的"源" —— 与关键字表同源，不另外维护词表）
    $已译英文 = @()
    foreach ($l in [System.IO.File]::ReadAllLines($kwFile)) {
        $km = [regex]::Match($l, '^\s*ZH_(?:KEYWORD|OPERATOR_KEYWORD|VIRT_SPECIFIER|CONTEXTUAL_KEYWORD)\(\s*([A-Za-z_][A-Za-z0-9_]*)')
        if ($km.Success) { $已译英文 += $km.Groups[1].Value }
    }
    $已译英文 = @($已译英文 | Sort-Object -Unique)

    # 备选串 == 已译关键字、但仍然必须留英文的**逐条**理由（键 '<诊断名>|<备选串>'）
    $备选豁免 = @{
        'warn_doc_api_container_decl_mismatch|class'    = 'doxygen 命令名（\class / @class），用户要照写'
        'warn_doc_api_container_decl_mismatch|struct'   = 'doxygen 命令名（\struct / @struct）'
        'warn_doc_api_container_decl_mismatch|union'    = 'doxygen 命令名（\union / @union）'
        'err_module_odr_violation_objc_property|class'  = 'Objective-C 属性特性名（@property(class)）'
        'note_module_odr_violation_objc_property|class' = '同上，note 一侧'
        'note_related_result_type_family|new'           = 'Objective-C 方法族名 new'
        'warn_pure_function_returns_void|const'         = 'GNU 属性名 const（代码里照写），与关键字 常量 无关'
    }
    # 备选串处数登记：'<备选串>' = @(登记处数, 理由)
    $备选钉数 = @{ 'lambda' = @(0, '已按 D-07 = 匿名函数 翻完（2026-10-04）；钉 0，退回英文就红') }
    $英文上限 = 760   # 纯英文备选串总出现次数（§18.8 实测；判据③）

    # 扫描器写成函数：真表跑一次，自测（合成行）再跑一次 —— 判据必须**能失败**
    function 扫备选([string[]]$行) {
        $r = @{ 英文数 = 0; 钉数命中 = @{}; 漏 = @(); 豁免命中 = @{} }
        foreach ($row in $行) {
            $dm = [regex]::Match($row, '^\s*ZH_DIAG\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,')
            if (-not $dm.Success) { continue }
            $dn = $dm.Groups[1].Value
            foreach ($m in [regex]::Matches($row, '%select\{([^}]*)\}')) {
                foreach ($a in ($m.Groups[1].Value -split '\|')) {
                    $t = $a.Trim()
                    if ($t -eq '') { continue }
                    # 含汉字/全角标点的备选串 = 已翻，跳过
                    if ($t -match '[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]') { continue }
                    $r.英文数++
                    $u = $t.Trim("'")
                    if ($备选钉数.ContainsKey($u)) {
                        if (-not $r.钉数命中.ContainsKey($u)) { $r.钉数命中[$u] = 0 }
                        $r.钉数命中[$u]++
                    }
                    if ($已译英文 -contains $u) {
                        $key = $dn + '|' + $u
                        if ($备选豁免.ContainsKey($key)) { $r.豁免命中[$key] = $true }
                        else { $r.漏 += $key }
                    }
                }
            }
        }
        return $r
    }

    $rows = @([System.IO.File]::ReadAllLines($tbl) | Where-Object { $_ -match '^\s*ZH_DIAG\(' })
    $扫 = 扫备选 $rows
    $英文数 = $扫.英文数
    $钉数命中 = $扫.钉数命中
    $漏 = $扫.漏
    $豁免命中 = $扫.豁免命中

    # 自测：合成的英文备选串必须被抓到；豁免的要放行；已翻的不许误报
    $自测行 = @(
        'ZH_DIAG(testsyn_a, "前 %select{if|switch}0 后")',
        'ZH_DIAG(warn_doc_api_container_decl_mismatch, "命令 ''%select{\\|@}0%select{class|interface}1'' 不对")',
        'ZH_DIAG(testsyn_b, "前 %select{如果|选择}0 后")'
    )
    $自测 = 扫备选 $自测行
    $自测过 = ($自测.漏.Count -eq 2) -and (($自测.漏 | Sort-Object) -join ',') -eq 'testsyn_a|if,testsyn_a|switch'
    if ($自测过) {
        过 'P-08 自测：合成的英文备选串被抓到、豁免与已翻的不误报'
    } else {
        错 ('P-08 自测失败：合成行应恰好命中「testsyn_a|if」「testsyn_a|switch」两条，实际 ' + $自测.漏.Count + ' 条 —— ' + ($自测.漏 -join '、'))
    }
    if ($漏.Count -eq 0) {
        过 ("P-08①：备选串里没有'已译关键字的英文拼写'残留（对照 {0} 个关键字拼写 · 扫了 {1} 条表项）" -f $已译英文.Count, $rows.Count)
    } else {
        错 ("P-08①：备选串里还有'已译关键字的英文拼写' —— " + (($漏 | Sort-Object -Unique) -join '、'))
    }
    # 判据②：登记处数必须**正好**等于实测（多了=登记虚着，少了=英文在往回长）
    $钉数错 = @()
    foreach ($k in $备选钉数.Keys) {
        $want = $备选钉数[$k][0]
        $got = 0
        if ($钉数命中.ContainsKey($k)) { $got = $钉数命中[$k] }
        if ($got -ne $want) { $钉数错 += ("{0}：登记 {1} 处、实测 {2} 处" -f $k, $want, $got) }
    }
    if ($钉数错.Count -eq 0) {
        过 ("P-08②：备选串处数登记与实测一致（" + (($备选钉数.Keys | Sort-Object | ForEach-Object { '{0} {1} 处' -f $_, $备选钉数[$_][0] }) -join '、') + "）")
    } else {
        错 ("P-08②：备选串处数登记和实测对不上（翻干净了就把登记改成 0）—— " + ($钉数错 -join '；'))
    }
    # 判据③：纯英文备选串总数不得超过登记上限
    if ($英文数 -le $英文上限) {
        过 ("P-08③：纯英文备选串 {0} 处 ≤ 登记上限 {1} 处" -f $英文数, $英文上限)
    } else {
        错 ("P-08③：纯英文备选串 {0} 处 > 登记上限 {1} 处（新增的英文备选串要么翻掉，要么显式改上限）" -f $英文数, $英文上限)
    }
    # 豁免表不许虚着：每条都要在表里真的命中
    $虚 = @($备选豁免.Keys | Where-Object { -not $豁免命中.ContainsKey($_) })
    if ($虚.Count -gt 0) {
        提 ("`$备选豁免 里有条目已经查不到了（表改了就把豁免删掉）：{0}" -f ($虚 -join '、'))
    }
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
