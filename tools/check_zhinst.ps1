# ============================================================================
#  check_zhinst.ps1 —— §17.20 「每个中文名都要能被真正用起来」实例化守卫
#
#  为什么要有它（2026-09-30 实测的事故）：
#    别名轨道的测试台从不把条目里的反引号-n 转成真换行 -> 整段用例写成一行 ->
#    `#包含` 之后的记号全被当"多余记号"（只警告）-> **43 个别名产物的"用法用例"
#    从没真正用过任何名字**，只证明"产品能解析"。修好测试台后立刻暴露 18/43 有真 bug
#    （endl/ends/flush/ws 一实例化就编不过、正则查找特征形参推导冲突…）。
#    结论：**"头能 include" != "名能用"**，而这正是用户验收判据最容易被绕过的地方。
#
#  判据（三条互不替代，一起记账）：
#    ① 自动探针：类型 -> 声明该类型的对象指针；**模板 -> 从表的 tparam/模板头合成实参**
#       （`向量<整数>`、`位集<1>`）；常量 -> 读一次；非模板函数 -> 取一次地址。
#       每个产物一个 TU，**编成 exe 并真跑**（不只 -fsyntax-only）。
#    ② 条目用例覆盖：名字出现在该条目自带用例里（那里的用例现在是真编译 + 真运行的）。
#    ③ 未覆盖：模板函数 / 概念 / 命名空间 / 预处理行等"无法自动生成实参"的名字，
#       必须写明**原因分类** —— 账要诚实显示"还缺"，不许把做不到的混进"已覆盖"。
#    ④ §17.21 模板函数「合成实参真调用」探针：**表里有名字 != 名字能被调用**。
#       别名层的手写签名（`生成` = std::generate 却写成返回 `输出迭代`）以前藏在
#       ③里没人看得见；现在模板函数也按形参合成见证**真调一次**，
#       见下面 §17.21 一节（A 级调用 / B 级显式模板实参）。
#
#  名字来源：三张生成器表（不是手写清单）。新增名字自动进账。
#    · 深度轨道 make_zhstdlib2.ps1 -ExportJson（产品公开名 + tparam + types/手写层）
#    · 别名轨道 make_zhalias.ps1   -ExportJson（常量/类型/函数/原样 四型）
#    · C  轨道 make_zhc.ps1 的 $T 表（类型/函数）
#
#  用法：
#    pwsh -File tools\check_zhinst.ps1              # 跑全量 + 重写台账
#    pwsh -NoProfile -File tools\check_zhinst.ps1 -Check        # 只校验台账（闸门用）
#    pwsh -NoProfile -File tools\check_zhinst.ps1 -Only 向量,时间   # 只跑某几个产物（调试）
# ============================================================================
param([switch] $Check, [switch] $Quiet, [string[]] $Only = @())

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx = Join-Path $root 'build\Release\bin\chinese++.exe'
$out = Join-Path $root 'zhstdlib'
$work = Join-Path $root 'build\_zhinst'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ledger = Join-Path $root 'docs\标准库汉化\实例化台账.md'
$zhName = '[\u4e00-\u9fff][\w\u4e00-\u9fff]*'

function Test-ZhName([string] $s) { return ($s -match ('^' + $zhName + '$')) }

# ---------------------------------------------------------------------------
#  模板实参合成：把 `模板 <类型名 元素, 类型名 分配器 = ...>` 变成 `整数`
#    · 有默认值的形参不传；类型形参（含包）传 `整数`；非类型形参传 `1`
#    · 全默认 -> 返回 $null（调用方用裸名字）
# ---------------------------------------------------------------------------
function Get-TemplateArgs([string] $decl) {
    if (-not $decl) { return $null }
    $m = [regex]::Match($decl, '模板\s*<(?<body>.*)>\s*$')
    if (-not $m.Success) { return $null }
    $body = $m.Groups['body'].Value
    $parts = @(); $depth = 0; $cur = ''
    foreach ($ch in $body.ToCharArray()) {
        if ($ch -eq '<' -or $ch -eq '(') { $depth++ }
        elseif ($ch -eq '>' -or $ch -eq ')') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $parts += $cur; $cur = '' } else { $cur += $ch }
    }
    if ($cur.Trim()) { $parts += $cur }
    $args = @()
    foreach ($p in $parts) {
        $pp = $p.Trim()
        if ($pp -match '=') { continue }
        if ($pp -match '^类型名') { $args += '整数' }
        else { $args += '1' }
    }
    if ($args.Count -eq 0) { return $null }
    return ($args -join ', ')
}

# ---------------------------------------------------------------------------
#  §17.21 模板函数「合成实参真调用」探针
#
#  事故（实测）：别名层 `生成` 的签名写成
#    `模板 <类型名 迭代, 类型名 输出迭代, 类型名 生成器> 输出迭代 生成(迭代 首, 迭代 尾, 生成器 丙)`
#  而 std::generate 返回 void —— `输出迭代` 只出现在返回类型里，永远推导不出来，
#  用户一写 `标准::生成(首, 尾, 丙)` 就是「没有匹配的函数」。旧守卫对模板函数
#  **一律不做探针**（记「模板函数-无探针」），于是"根本调不通"能长期藏在"未覆盖"里。
#  护栏口径：**表里有名字 != 名字能被调用**；模板函数也要真的调一次。
#
#  两级（都真编译；调用写在**永不被调用的 lambda 里** —— 证明的是"能实例化调用"，
#  不是运行时行为，于是不会把算法的 UB 引到探针进程里）：
#    A 调用探针    `标准::名(见证…)`            普通推导调用
#    B 显式实参探针 `标准::名<见证类型…>(见证…)`  A 失败才跑：把"只在返回类型里出现的
#      形参"当显式模板实参传进去。**合法**的（`时长转换<目标时长>`）在 B 下通过；
#      **签名有病**的（`生成`）在 B 下实例化函数体，报错**正落在这个名字自己的定义行**
#      —— 只有这一种判真失败。B 的报错落在别处 = 见证表达不出，记「未覆盖」，
#      不冤判库。
# ---------------------------------------------------------------------------
function Split-TopLevel([string] $s) {
    $o = @(); $depth = 0; $cur = ''
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '<' -or $ch -eq '(' -or $ch -eq '[') { $depth++ }
        elseif ($ch -eq '>' -or $ch -eq ')' -or $ch -eq ']') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $o += $cur; $cur = '' } else { $cur += $ch }
    }
    if ($cur.Trim()) { $o += $cur }
    return $o
}
function Get-TemplateBody([string] $line) {
    $i = $line.IndexOf('模板'); if ($i -lt 0) { return '' }
    $j = $line.IndexOf('<', $i); if ($j -lt 0) { return '' }
    $depth = 0
    for ($k = $j; $k -lt $line.Length; $k++) {
        $ch = $line[$k]
        if ($ch -eq '<') { $depth++ }
        elseif ($ch -eq '>') { $depth--; if ($depth -eq 0) { return $line.Substring($j + 1, $k - $j - 1) } }
    }
    return ''
}
function Get-FuncParams([string] $line) {
    $m = [regex]::Match($line, '([\u4e00-\u9fff][\u4e00-\u9fff_0-9]*)\s*\(([^()]*)\)\s*(?:不抛出|noexcept)?\s*\{')
    if (-not $m.Success) { return $null }
    return @{ Name = $m.Groups[1].Value; Params = (Split-TopLevel $m.Groups[2].Value) }
}
#  见证种类：组=整数数组（迭代器）、出=输出缓冲、壹=左值、丙=变参 lambda、引=随机引擎、范=向量
function New-WitnessDecl([string[]] $kinds, [int] $id) {
    $d = @()
    if ($kinds -contains '组') { $d += "        整数 组$id[8]{0,1,2,3,4,5,6,7};" }
    if ($kinds -contains '出') { $d += "        整数 出$id[32]{};" }
    if ($kinds -contains '壹') { $d += "        整数 壹$id = 1;" }
    if ($kinds -contains '丙') { $d += "        自动 丙$id = [](自动&&... 参){ 返回 1; };" }
    if ($kinds -contains '引') { $d += "        标准::默认随机引擎 引$id{};" }
    if ($kinds -contains '范') { $d += "        标准::向量<整数> 范$id{1,2,3,4};" }
    return ($d -join "`n")
}
function Get-Witness([string] $type, [string] $pname, [int] $id) {
    #  返回 @{ Expr; Kind } ；$null = 这个形参见证不出来（整个名字不做探针）
    $t = ($type.Trim() -replace '^const\s+', '') -replace '\s*[&*]+\s*$', ''
    $k = ''
    if ($t -match '^输出迭代|^输出迭代器|^插入迭代') { $k = '出' }
    elseif ($t -match '迭代') { $k = '组' }
    elseif ($t -match '^(谓词|比较|一元操作|二元操作|生成器|函数|成员函数|操作|条件|判据)$') { $k = '丙' }
    elseif ($t -match '^(值类型|大小类型|距离类型|类型1|类型2|某类型|元素|别的|替换类型|整数类型|实数类型)$') { $k = '壹' }
    elseif ($t -match '^(std::size_t|std::ptrdiff_t|size_t|整数|长整型|无符号整数)$') { $k = '壹' }
    elseif ($t -match '^范围类型$') { $k = '范' }
    elseif ($pname -match '^引擎$' -and $t -match '^引擎$') { $k = '引' }
    else { return $null }
    $expr = switch ($k) {
        '组' { if ($pname -match '尾') { "组$id + 8" } elseif ($pname -match '中') { "组$id + 2" } else { "组$id" } }
        '出' { if ($pname -match '尾') { "出$id + 32" } else { "出$id" } }
        '壹' { "壹$id" }
        '丙' { "丙$id" }
        '引' { "引$id" }
        '范' { "范$id" }
        default { return $null }
    }
    return @{ Expr = $expr; Kind = $k }
}
# ---------------------------------------------------------------------------
#  §17.22 未覆盖的"账目质量"：判据②要求**剩余项都带理由登记为边界且有消除路径**。
#  只有"未覆盖"四个字不算登记 —— 每个名字都要能看出①为什么没覆盖②下一步怎么销。
# ---------------------------------------------------------------------------
function Get-ReasonClass([string] $r) {
    if ($r -match '^手写层') { return '手写层·嵌套成员（需宿主类型）' }
    if ($r -match '^概念') { return '概念（模板实参合成不出）' }
    if ($r -match '^调用探针编不过') { return '模板函数（调用探针编不过）' }
    if ($r -match '^调用探针表达不出') { return '模板函数（显式实参也编不过）' }
    if ($r -match '^变参转发器') { return '变参转发器（一元/二元都编不过）' }
    if ($r -match '重载') { return '重载函数（需具体实参）' }
    if ($r -match '模板合成实参不适用') { return '模板类型/别名（合成实参不适用）' }
    if ($r -match '-无探针') { return '无探针（见证表表达不出）' }
    return '其它'
}
#  ⚠ 台账必须**可复算**（同一次生成跑两遍要一字不差，否则闸门的 -Check 永远报"已过期"）。
#  探针文件名里带 `[Math]::Abs($n.Name.GetHashCode())`，而 .NET 的字符串 hash **每个进程随机化** ——
#  报错文本一旦原样进账，两遍就是两份不同的账。所以进账前只留**编译器的话**，去掉
#  `盘符:\…\build\_zhinst\p_xxx_n123.cpp:12:9:` 这段"我们自己的路径 + 随机 hash"。
function Get-ErrBrief([string] $e) {
    if (-not $e) { return '' }
    $m = [regex]::Match($e, 'error:\s*(.*)$')
    $t = $(if ($m.Success) { $m.Groups[1].Value } else { $e })
    $t = $t -replace '[A-Za-z]:\\[^:]*\\build\\_zhinst\\[^:]*', '<探针>'
    return $t.Trim()
}
function Get-FixPath([string] $reason, [string] $kind) {
    if ($reason -match '^手写层') { return '按它的宿主类型写嵌套探针（`标准::宿主<实参>::名`），或给条目补一条真用它的用例' }
    if ($reason -match '^概念') { return '给它的模板形参加见证（`Get-TypeArgWitness`），或补一条真用一次概念的用例' }
    if ($reason -match '^调用探针|^模板函数') { return '把该形参的见证加进 `Get-Witness`，或给条目补一条真调用用例' }
    if ($reason -match '^变参转发器') { return '补一条带**真实参类型**的调用用例（打印/格式化类要格式串，整数哑实参天然不匹配）' }
    if ($reason -match '重载') { return '补一条带具体实参的调用用例（取地址有歧义 -> 直接调用）' }
    if ($reason -match '模板合成实参不适用') { return '给条目补一条真用一次的用例；这正是"条目用例"该干的事（见台账"用例覆盖"列）' }
    if ($reason -match '-无探针') { return '扩见证表（`Get-Witness` / `Get-TemplateArgs`），或补一条真用例' }
    return '补一条真用例，或扩见证表（判责规则见 tools\check_zhinst.ps1 顶部）'
}
function Get-WitnessIncludes([string[]] $kinds) {
    $inc = @()
    if ($kinds -contains '引') { $inc += '随机' }
    if ($kinds -contains '范') { $inc += '向量' }
    return $inc
}
function Get-TypeArgWitness([string] $body, [int] $id) {
    #  模板形参 -> 显式模板实参；有一个见证不出来就返回 $null（B 级探针不做）
    if (-not $body) { return $null }
    $args = @()
    foreach ($p in (Split-TopLevel $body)) {
        $t = $p.Trim(); if (-not $t) { continue }
        if ($t -match '=') { $t = ($t -split '=')[0].Trim() }
        $nm = ($t -split '\s+')[-1].TrimEnd('.')
        if ($t -match '^类型名') {
            if ($nm -match '^(迭代|迭代1|迭代2|输出迭代|输出迭代器|随机迭代)$') { $args += '整数*' }
            elseif ($nm -match '^(谓词|比较|一元操作|二元操作|生成器|函数|成员函数|操作|条件|判据)$') { $args += "decltype(丙$id)" }
            elseif ($nm -match '^(值类型|大小类型|距离类型|类型1|类型2|元素|别的|替换类型|整数类型|实数类型)$') { $args += '整数' }
            else { return $null }
        } else { $args += '1' }
    }
    if (-not $args.Count) { return $null }
    return ($args -join ', ')
}
function New-TplProbe($n, [int] $id, [string] $prodPath) {
    #  返回 @{ Name; Kind; Line(A); LineB; DefLine } ；$null = 见证表达不出，不做探针
    if (-not $n.Raw) { return $null }
    $fp = Get-FuncParams $n.Raw
    if (-not $fp) { return $null }
    $wits = @(); $kinds = @()
    foreach ($pd in $fp.Params) {
        $t = $pd.Trim(); if (-not $t) { continue }
        $pm = [regex]::Match($t, '^(.*?)[\s&*]+([\u4e00-\u9fff][\u4e00-\u9fff_0-9]*)$')
        if (-not $pm.Success) { return $null }
        $w = Get-Witness $pm.Groups[1].Value $pm.Groups[2].Value $id
        if (-not $w) { return $null }
        $wits += $w.Expr
        if ($kinds -notcontains $w.Kind) { $kinds += $w.Kind }
    }
    if (-not $wits.Count) { return $null }
    $decl = New-WitnessDecl $kinds $id
    $lineA = "    自动 探$id = [](){`n$decl`n        标准::$($n.Name)($($wits -join ', '));`n    };`n    (空型)探$id;"
    $lineB = $null
    $ta = Get-TypeArgWitness (Get-TemplateBody $n.Raw) $id
    if ($ta) { $lineB = "    自动 探B$id = [](){`n$decl`n        标准::$($n.Name)<$ta>($($wits -join ', '));`n    };`n    (空型)探B$id;" }
    #  这个名字在产物里的定义行号：判真失败要求报错**正落在这行**
    $defLine = 0
    if (Test-Path $prodPath) {
        $txt = [System.IO.File]::ReadAllText($prodPath)
        $dl = [regex]::Match($txt, '(?m)^.*[\s(]' + [regex]::Escape($n.Name) + '\s*\(')
        if ($dl.Success) { $defLine = @($txt.Substring(0, $dl.Index) -split "`n").Count }
    }
    return [pscustomobject]@{ Name = $n.Name; Kind = '模板函数探针'; Line = $lineA; LineB = $lineB; DefLine = $defLine; ExtraInc = (Get-WitnessIncludes $kinds) }
}

# ---------------------------------------------------------------------------
#  从「原样」/手写层的 C++ 行里提名字、类别与模板头
# ---------------------------------------------------------------------------
function Get-NamesFromLine([string] $line) {
    $out = @()
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('//') -or $t.StartsWith('#')) { return $out }
    if ($t -match '^\s*名域\s+[\w\u4e00-\u9fff]+\s*\{' -or $t -eq '}') { return $out }
    $tmpl = ''
    $mt = [regex]::Match($t, '^(模板\s*<.*?>)\s')
    if ($mt.Success) { $tmpl = $mt.Groups[1].Value }
    $m = [regex]::Match($t, '^模板\s*<[^>]*>\s*概念\s+(' + $zhName + ')')
    #  §17.22 概念也能机器探针：`(空型)标准::概念名<整数…>;` —— 概念求值对任何实参都良构
    #  （不满足只是求值为 false，不是编译错误），所以"合成实参"这条路对概念是通的。
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '概念'; Template = $tmpl }) }
    $m = [regex]::Match($t, '^模板\s*<[^>]*>\s*使用\s+(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '模板别名'; Template = $tmpl }) }
    $m = [regex]::Match($t, '^使用\s+(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '类型'; Template = '' }) }
    if ($t -match '^模板\s*<') {
        #  ⚠ 名字必须是「参数表后紧跟函数体 `{`」的那个 —— 不能取行里第一个 `名(`：
        #    `声明类型(自动) 变换(...) { ... }`（decltype(auto) 返回类型，§16.52）里第一个
        #    `名(` 是关键字 `声明类型`，取它会**用假名顶掉真名** —— 真名就此不在账上。
        #    实测（2026-09-30）：`时长转换`/`时间点转换`/`时钟转换`/`时长上取整`/`时长四舍五入`/
        #    `生成规范数`/`变换`… 一整批真名被一个 `声明类型` 顶掉。**账上少一个名字，
        #    比多一个假名更坏**：少的那几个永远没人去覆盖。
        $m = [regex]::Match($t, '(' + $zhName + ')\s*\(([^()]*)\)\s*(?:不抛出|noexcept)?\s*\{')
        if (-not $m.Success) {
            $m2 = [regex]::Match($t, '\s(' + $zhName + ')\s*\(')   # 体在下一行：退回第一个，但关键字不算名字
            if ($m2.Success -and $m2.Groups[1].Value -ne '声明类型') { $m = $m2 }
        }
        #  Raw = 原始签名行：§17.21 要从行里抠出「模板形参」和「函数形参」做调用探针
        if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '模板函数'; Template = $tmpl; Raw = $t }) }
        return $out
    }
    $m = [regex]::Match($t, '^内联\s+常量\s+[^=]+?\s(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '常量'; Template = '' }) }
    $m = [regex]::Match($t, '^(?:内联\s+|常量表达式\s+|静态\s+)*[\w:<>,\s&*]+\s(' + $zhName + ')\s*\(')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '函数'; Template = '' }) }
    return $out
}

function Get-NamesFromCode([string] $code) {
    $r = @()
    foreach ($ln in ($code -split "`r?`n")) { $r += Get-NamesFromLine $ln }
    return $r
}

# ---------------------------------------------------------------------------
#  三张表 -> (产品, tparam, 名字, 用例文本)
# ---------------------------------------------------------------------------
$products = @()

# ① 别名轨道
$ajson = & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhalias.ps1') -ExportJson 2>$null | Out-String
$atab = $ajson | ConvertFrom-Json
foreach ($p in $atab.PSObject.Properties) {
    $names = @()
    foreach ($e in $p.Value.a) {
        switch ($e[0]) {
            '常量' { if (Test-ZhName $e[1]) { $names += [pscustomobject]@{ Name = $e[1]; Kind = '常量'; Template = '' } } }
            '类型' { if (Test-ZhName $e[1]) { $names += [pscustomobject]@{ Name = $e[1]; Kind = '类型'; Template = '' } } }
            '函数' { if (Test-ZhName $e[1]) { $names += [pscustomobject]@{ Name = $e[1]; Kind = '模板函数'; Template = '' } } }
            '原样' { $names += Get-NamesFromLine ([string]$e[1]) }
        }
    }
    $tests = ''
    if ($p.Value.PSObject.Properties.Name -contains 'tests') { foreach ($tc in $p.Value.tests) { $tests += ([string]$tc[1]) + "`n" } }
    $products += [pscustomobject]@{ Track = '别名'; Product = $p.Value.zh; TParam = ''; Names = @($names | Sort-Object Name -Unique); Tests = $tests }
}

# ② 深度轨道
$djson = & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhstdlib2.ps1') -ExportJson 2>$null | Out-String
$dtab = $djson | ConvertFrom-Json
foreach ($p in $dtab.PSObject.Properties) {
    $zh = $p.Value.zh
    $tp = ''
    if (($p.Value.PSObject.Properties.Name -contains 'tparam') -and $p.Value.tparam) { $tp = [string]$p.Value.tparam.decl }
    $names = @()
    #  产品名只有当它在产品正文里**确实被声明为类型**时才当类型探针 —— 否则会误报
    #  （`数值算法`/`版本`/`字符转换` 这类头是"只有函数/只有宏"的，`标准::数值算法` 不是类型）。
    if (Test-ZhName $zh) {
        $pubName = $zh
        if (($p.Value.PSObject.Properties.Name -contains 'pub') -and $p.Value.pub) { $pubName = [string]$p.Value.pub }
        $prodFile = Join-Path $out $zh
        $declaresType = $false
        if (Test-Path $prodFile) {
            $ptxt = [System.IO.File]::ReadAllText($prodFile)
            $declaresType = ($ptxt -match ('(?m)^\s*(?:类型|使用)\s+' + [regex]::Escape($pubName) + '\b'))
        }
        if ($declaresType) { $names += [pscustomobject]@{ Name = $pubName; Kind = $(if ($tp) { '模板类型' } else { '类型' }); Template = $tp } }
    }
    if (($p.Value.PSObject.Properties.Name -contains 'types') -and $p.Value.types) {
        foreach ($k in $p.Value.types.PSObject.Properties) {
            $v = [string]$k.Value
            if ((Test-ZhName $v) -and -not $v.StartsWith('_')) { $names += [pscustomobject]@{ Name = $v; Kind = '内部实现类'; Template = '' } }
        }
    }
    #  手写层（extra/deriveExtra/prologue）里提的名字：既有**顶层自由函数**（复数/C数学 的
    #  `常用对数`/`反余弦`），也有**嵌套成员名**（`基类`/`常量反向迭代器`）。
    #  §17.22 起不再**一律**记成"手写层"黑洞（那样这些名字连一次编译都没过）：
    #  保留它**自己是什么**（Inner），顶层先按那个探针真试一次，试不过才软记账为
    #  「手写层·X：顶层试不过（嵌套成员/需宿主实参）」—— 账要能看出"差在哪一步"。
    foreach ($field in 'extra', 'deriveExtra', 'prologue', 'deriveTypes') {
        if (($p.Value.PSObject.Properties.Name -contains $field) -and $p.Value.$field) {
            foreach ($n2 in (Get-NamesFromCode ([string]$p.Value.$field))) {
                $names += [pscustomobject]@{ Name = $n2.Name; Kind = '手写层探针'; Inner = $n2.Kind; Template = $n2.Template; Raw = $n2.Raw }
            }
        }
    }
    $tests = ''
    if (($p.Value.PSObject.Properties.Name -contains 'tests') -and $p.Value.tests) { foreach ($tc in $p.Value.tests) { $tests += ([string]$tc[1]) + "`n" } }
    $products += [pscustomobject]@{ Track = '深度'; Product = $zh; TParam = $tp; Names = @($names | Sort-Object Name -Unique); Tests = $tests }
}

# ③ C 轨道（表在源码里）
$ctext = [System.IO.File]::ReadAllText((Join-Path $root 'tools\make_zhc.ps1'))
foreach ($em in [regex]::Matches($ctext, "(?ms)^\s*'([a-z_][a-z0-9_.]*)'\s*=\s*@\{\s*zh\s*=\s*'([^']+)'\s*;?\s*a\s*=\s*@\((.*?)\)\s*\}")) {
    $names = @()
    foreach ($nm in [regex]::Matches($em.Groups[3].Value, "@\('(\S+?)','([^']+)','([^']*)'\)")) {
        $kind = $nm.Groups[1].Value; $nm2 = $nm.Groups[2].Value
        if (-not (Test-ZhName $nm2)) { continue }
        if ($kind -eq '类型') { $names += [pscustomobject]@{ Name = $nm2; Kind = '类型'; Template = '' } }
        elseif ($kind -eq '常量') { $names += [pscustomobject]@{ Name = $nm2; Kind = '常量'; Template = '' } }
        else { $names += [pscustomobject]@{ Name = $nm2; Kind = '模板函数'; Template = '' } }
    }
    $products += [pscustomobject]@{ Track = 'C'; Product = $em.Groups[2].Value; TParam = ''; Names = @($names | Sort-Object Name -Unique); Tests = '' }
}

# ⚠ pwsh -File 把逗号列表当【一个字符串】传（老坑）—— 自己拆。
if ($Only.Count) {
    $Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $products = @($products | Where-Object { $Only -contains $_.Product })
}
if ($products.Count -eq 0) { throw "实例化守卫：选中的产物数为 0（-Only 写法不对？§15.3：跑 0 条的通过不是通过）" }

# ---------------------------------------------------------------------------
#  生成探针并编译运行
# ---------------------------------------------------------------------------
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $work | Out-Null

$rows = @(); $failAll = @(); $uncoveredAll = @()
foreach ($p in $products) {
    $items = @(); $probed = @(); $byTest = @(); $uncovered = @{}; $tplItems = @()
    foreach ($n in @($p.Names | Sort-Object Name -Unique)) {
        $used = $false
        if ($p.Tests -and $p.Tests -match [regex]::Escape($n.Name)) { $byTest += $n.Name; $used = $true }
        $id = [Math]::Abs($n.Name.GetHashCode())
        #  §17.21 模板函数走「合成实参真调用」探针（自成一批，见下面的 tpl 批）
        #  §17.22 手写层里的模板函数也走同一条路（它是"名字自己是什么"的一类）
        if ($n.Raw -and ($n.Kind -eq '模板函数' -or $n.Kind -eq '手写层探针')) {
            $tpn = New-TplProbe $n $id (Join-Path $out $p.Product)
            if ($tpn) {
                #  手写层名字**不判真失败**：它的调用上下文是我们合成的，错不一定在库（§17.22）
                if ($n.Kind -eq '手写层探针') { $tpn | Add-Member -NotePropertyName Soft -NotePropertyValue $true }
                $tplItems += $tpn; $probed += $n.Name; $used = $true; continue
            }
        }
        $line = $null
        switch ($n.Kind) {
            '类型' { $line = ("    {0}* 针{1} = 空指针; (空型)针{1};" -f ('标准::' + $n.Name), $id) }
            '内部实现类' { $line = ("    标准::细节::{0}* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id) }
            '模板类型' { $a = Get-TemplateArgs $n.Template; if ($a) { $line = ("    {0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f ('标准::' + $n.Name), $a, $id) } }
            '模板别名' { $a = Get-TemplateArgs $n.Template; if ($a) { $line = ("    {0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f ('标准::' + $n.Name), $a, $id) } }
            '常量' { $line = ("    (空型)标准::{0};" -f $n.Name) }
            '函数' { $line = ("    自动 针f{0} = &标准::{1}; (空型)针f{0};" -f $id, $n.Name) }
            #  §17.22 概念探针：概念求值对任何实参都良构（不满足只求值为 false），
            #  所以"合成实参 + 求值一次"就是真实的实例化检查。
            '概念' {
                $a = Get-TemplateArgs $n.Template
                $arg = if ($n.Template) { '<' + $(if ($a) { $a } else { '' }) + '>' } else { '' }
                $line = ("    (空型)标准::{0}{1};" -f $n.Name, $arg)
            }
            #  §17.22 手写层名：先按它**自己是什么**在顶层试一次；试不过再软记账（嵌套成员要宿主）
            '手写层探针' {
                switch ($n.Inner) {
                    '类型' { $line = ("    标准::{0}* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id) }
                    '模板别名' { $a = Get-TemplateArgs $n.Template; if ($a) { $line = ("    标准::{0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f $n.Name, $a, $id) } }
                    '常量' { $line = ("    (空型)标准::{0};" -f $n.Name) }
                    '函数' { $line = ("    自动 针f{0} = &标准::{1}; (空型)针f{0};" -f $id, $n.Name) }
                }
            }
            #  §17.22 别名 `函数` 形与 C 轨道的**变参转发器**：形状是固定的
            #  （`模板 <类型名... 参数> 声明类型(自动) 名(参数&&... 值) { 返回 std::英文(值...); }`），
            #  唯一未知的是**实参个数** -> 一元/二元各出一条候选，任意一条编过即算"能调用"。
            #  调用写在永不被调用的 lambda 里：C 轨道的包装器（`取字符串长度`(空指针) 之类）
            #  不能在探针进程里真跑，但"能实例化调用"正是要证的那件事。
            '模板函数' {
                foreach ($arity in 1, 2) {
                    $callArgs = $(if ($arity -eq 1) { "壹$id" } else { "壹$id, 壹$id" })
                    $ln = "    自动 探$arity$id = [](){ 整数 壹$id = 1; 标准::$($n.Name)($callArgs); };`n    (空型)探$arity$id;"
                    $items += [pscustomobject]@{ Line = $ln; Name = $n.Name; Kind = $n.Kind }
                }
                $probed += $n.Name; $used = $true
            }
        }
        if ($line) { $items += [pscustomobject]@{ Line = $line; Name = $n.Name; Kind = $n.Kind }; $probed += $n.Name; $used = $true }
        elseif (-not $used) {
            $uncovered[$n.Name] = $(if ($n.Kind -eq '手写层探针') { '手写层·' + $n.Inner + '：顶层试不过（嵌套成员/需宿主实参）' }
                elseif ($n.Kind -eq '概念') { '概念：模板实参合成不出来（形参有默认值依赖等）' }
                else { $n.Kind + '-无探针' })
        }
    }
    $compiled = $null; $ran = $null
    $safe = ($p.Product -replace '[\\/:*?"<>|]', '_')
    #  §17.20 阶段(5)：**C++23 条件壳**的分支要用 C++23 编（产品里有 `#如果 _HAS_CXX23`
    #  就说明它的名字只在 C++23 下存在）—— 这正是"壳的分支只有人工探针"那条欠账的机器化。
    $prodFile = Join-Path $out $p.Product
    $stdFlag = '-std=c++20'
    if ((Test-Path $prodFile) -and ([System.IO.File]::ReadAllText($prodFile) -match '_HAS_CXX23')) { $stdFlag = '-std=c++23' }
    $extraInc = @()   #  §17.21：模板函数探针需要额外中文头（见证用了随机引擎 -> <随机>、范围 -> <向量>）
    function Invoke-Probe([string[]] $lines, [string] $tag) {
        $src = Join-Path $work ("p_$safe$tag.cpp"); $exe = Join-Path $work ("p_$safe$tag.exe")
        $inc = "#包含 <$($p.Product)>`n"
        foreach ($e in @($extraInc)) { if ($e) { $inc += "#包含 <$e>`n" } }
        $code = $inc + "整数 主函数(){`n" + ($lines -join "`n") + "`n    返回 0;`n}`n"
        [System.IO.File]::WriteAllText($src, $code, $utf8)
        & cmd /c "`"$cxx`" $stdFlag -isystem`"$out`" `"$src`" -o `"$exe`" > `"$work\o_$safe$tag.txt`" 2>&1"
        $cc = $LASTEXITCODE
        $rc = -1
        if ($cc -eq 0) { & $exe; $rc = $LASTEXITCODE }
        $errLines = @(Get-Content "$work\o_$safe$tag.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' })
        $firstErr = ''
        if ($errLines.Count -gt 0) { $firstErr = ([string]$errLines[0]).Trim() }
        return [pscustomobject]@{ CC = $cc; RC = $rc; Err = $firstErr }
    }
    #  二分找出编不过的条目 —— 整批编不过时避免逐个编（条目多时省成倍时间）
    function Find-BadItems([object[]] $list, [string] $tag) {
        $bad = @(); $queue = New-Object System.Collections.ArrayList
        [void]$queue.Add(@($list))
        while ($queue.Count -gt 0) {
            $g = @($queue[0]); $queue.RemoveAt(0)
            if ($g.Count -eq 0) { continue }
            if ($g.Count -eq 1) {
                $r = Invoke-Probe @($g[0].Line) ('_' + $tag + [Math]::Abs($g[0].Name.GetHashCode()))
                if ($r.CC -ne 0) { $bad += $g[0] }
                continue
            }
            $r = Invoke-Probe @($g | ForEach-Object { $_.Line }) ('_' + $tag + 'G' + [Math]::Abs($g[0].Name.GetHashCode()))
            if ($r.CC -ne 0) {
                $h = [int][Math]::Floor($g.Count / 2)
                [void]$queue.Add(@($g[0..($h - 1)]))
                [void]$queue.Add(@($g[$h..($g.Count - 1)]))
            }
        }
        return $bad
    }
    if ($items.Count) {
        $r0 = Invoke-Probe @($items | ForEach-Object { $_.Line }) ''
        if ($r0.CC -ne 0) {
            #  §17.20 判责规则：**按名字类别 + 报错性质**，不按报错位置。
            #    · 模板类型 / 模板别名 / 内部实现类：实参是我们**合成**的（`整数`/`1`），
            #      对"默认形参依赖前一个形参"的模板（`时间点<时钟, 时长 = 时钟::duration>`）
            #      哑实参天然不适用 -> 记「未覆盖（探针不可表达）」并从批量里剔掉，**不判库失败**。
            #    · 函数：**重载**取地址有歧义（`存在`/`当前路径` 各有多个重载）-> 同样记
            #      「未覆盖（重载函数：需具体实参）」，不判库失败。
            #    · 类型 / 常量（不需要实参）：编不过就是**库/表自己的问题** -> 真失败。
            $badLines = @(); $softNames = @{}; $okNames = @{}
            foreach ($it in $items) {
                $ri = Invoke-Probe @($it.Line) ('_n' + [Math]::Abs($it.Name.GetHashCode()))
                if ($ri.CC -eq 0) { $okNames[$it.Name] = $true; continue }
                $soft = $false; $why = ''
                if ($it.Kind -in @('模板类型', '模板别名', '内部实现类')) { $soft = $true; $why = '探针不可表达（模板合成实参不适用）' }
                elseif ($it.Kind -eq '函数' -and ($ri.Err -match 'overloaded|重载')) { $soft = $true; $why = '探针不可表达（重载函数：需具体实参）' }
                #  §17.22：手写层名与概念都是"我们替它合成上下文"，编不过**不判库失败**
                elseif ($it.Kind -eq '手写层探针') { $soft = $true; $why = '手写层·' + $it.Inner + '：顶层试不过（嵌套成员/需宿主实参）' }
                elseif ($it.Kind -eq '概念') { $soft = $true; $why = '概念：模板实参合成不出来（形参默认值依赖等）' }
                elseif ($it.Kind -eq '模板函数') { $soft = $true; $why = '变参转发器：一元/二元实参都试过，都编不过' }
                if ($soft) { $badLines += $it.Line; $softNames[$it.Name] = $why }
                else { $failAll += ("  [{0}] 探针编不过（{1}：{2}）：{3}" -f $p.Product, $it.Kind, $it.Name, $ri.Err) }
            }
            $items = @($items | Where-Object { $badLines -notcontains $_.Line })
            #  §17.22 **任意一条候选编过就算这个名字能调用** —— 同一名字可能有多条候选
            #  （变参转发器的一元/二元形态），只有"条条都编不过"才记未覆盖。
            foreach ($nm in $softNames.Keys) {
                if (-not $okNames.ContainsKey($nm)) {
                    $uncovered[$nm] = $softNames[$nm]
                    $probed = @($probed | Where-Object { $_ -ne $nm })
                }
            }
            if ($items.Count) { $r0 = Invoke-Probe @($items | ForEach-Object { $_.Line }) '' }
            else { $r0 = [pscustomobject]@{ CC = 0; RC = 0; Err = '' } }
        }
        $compiled = $r0.CC; $ran = $r0.RC
        if ($compiled -ne 0) { $failAll += ("  [{0}] 探针编不过：{1}" -f $p.Product, $r0.Err) }
        elseif ($ran -ne 0) { $failAll += ("  [{0}] 探针运行返回 {1}" -f $p.Product, $ran) }
    } else { $compiled = 0; $ran = 0 }
    # -----------------------------------------------------------------------
    #  §17.21 模板函数批：合成实参真调用（A 级）+ 显式模板实参（B 级）
    #    · 调用写在**永不被调用的 lambda** 里 -> 证明的是"能实例化调用"，不把算法
    #      的 UB 引进探针进程（探针 exe 仍要真跑，跑的是主批）
    #    · 整批编过 = 这批名字都调用得通；整批编不过 -> 二分找出编不过的，逐个定性
    #    · 判真失败的唯一条件：B 级报错**正落在这个名字自己的定义行** = 签名有病
    # -----------------------------------------------------------------------
    if ($tplItems.Count) {
        $extraInc = @()
        foreach ($ti in $tplItems) { foreach ($e in $ti.ExtraInc) { if ($extraInc -notcontains $e) { $extraInc += $e } } }
        $rT = Invoke-Probe @($tplItems | ForEach-Object { $_.Line }) '_t'
        if ($rT.CC -ne 0) {
            foreach ($it in @(Find-BadItems $tplItems 't')) {
                $id = [Math]::Abs($it.Name.GetHashCode())
                $ri = Invoke-Probe @($it.Line) ('_t' + $id)
                if ($ri.CC -eq 0) { continue }   # 单独编过：整批失败是别的名字拖累的
                $why = "调用探针编不过：$(Get-ErrBrief $ri.Err)"
                if ($it.LineB) {
                    $bi = Invoke-Probe @($it.LineB) ('_b' + $id)
                    if ($bi.CC -eq 0) { continue }   # 显式模板实参能调 -> 仍算"能调用"
                    $em = [regex]::Match([string]$bi.Err, 'zhstdlib.*?:(\d+):')
                    #  §17.22：手写层名字（Soft）**不判真失败** —— 它的调用上下文是我们合成的，
                    #  错不一定在库；定义行命中也不足以定罪。
                    if (-not $it.Soft -and $it.DefLine -gt 0 -and $em.Success -and [int]$em.Groups[1].Value -eq $it.DefLine) {
                        $failAll += ("  [{0}] 模板函数签名病（显式模板实参下报错正落在定义行 {1}）：{2} -> {3}" -f $p.Product, $it.DefLine, $it.Name, $bi.Err)
                        continue
                    }
                    $why = $(if ($it.Soft) { '手写层·模板函数：调用探针编不过（' } else { '调用探针表达不出（显式实参也编不过）：' }) + "$(Get-ErrBrief $bi.Err)"
                }
                $uncovered[$it.Name] = $why
                $probed = @($probed | Where-Object { $_ -ne $it.Name })
            }
        }
        $extraInc = @()
    }
    #  §17.22 逐名登记未覆盖：名字 + 类别 + 原因 + 消除路径（判据②：剩余项也是"有账的边界"）
    foreach ($k in $uncovered.Keys) {
        $kn = @($p.Names | Where-Object { $_.Name -eq $k } | Select-Object -First 1)
        $kKind = $(if ($kn.Count) { [string]$kn[0].Kind } else { '?' })
        $reason = [string]$uncovered[$k]
        $uncoveredAll += [pscustomobject]@{
            轨道 = $p.Track; 产物 = $p.Product; 名字 = $k; 类别 = $kKind
            原因 = $reason; 分类 = (Get-ReasonClass $reason); 消除路径 = (Get-FixPath $reason $kKind)
        }
    }
    $rows += [pscustomobject]@{
        轨道 = $p.Track; 产物 = $p.Product; 名字 = @($p.Names | Sort-Object Name -Unique).Count
        自动探针 = @($probed | Sort-Object -Unique).Count; 用例覆盖 = @($byTest | Sort-Object -Unique).Count
        未覆盖 = $uncovered.Count; 编译 = $compiled; 运行 = $ran
        未覆盖名单 = (($uncovered.Keys | Sort-Object) -join ' ')
    }
}

$totNames = ($rows | Measure-Object -Property 名字 -Sum).Sum
if (-not $totNames) { throw "实例化守卫：一个名字都没提出来（表解析坏了，§15.3）" }
$totProbe = ($rows | Measure-Object -Property 自动探针 -Sum).Sum
$totTest = ($rows | Measure-Object -Property 用例覆盖 -Sum).Sum
$totUncov = ($rows | Measure-Object -Property 未覆盖 -Sum).Sum
$failProducts = @($rows | Where-Object { $_.编译 -ne 0 -or $_.运行 -ne 0 })

# ---------------------------------------------------------------------------
#  台账
# ---------------------------------------------------------------------------
$lines = @(
    '# 实例化台账（§17.20）——「每个中文名都要能被真正用起来」',
    '',
    '> 本文件由 `tools\check_zhinst.ps1` 生成，`tools\regen_zhstdlib.ps1` 用 `-Check` 守。',
    '> 名字来自**三张生成器表**（深度 / 别名 / C），不是手写清单；新增名字自动进账。',
    '> 三列口径：**自动探针** = 类型声明指针（模板按表里的 `tparam`/模板头合成实参）+ 常量读取 +',
    '> 非模板函数取地址 + §17.21 **模板函数按形参合成见证真调一次**（A 级推导调用，',
    '> A 编不过再试 B 级显式模板实参；调用写在永不被调用的 lambda 里，证明"能实例化调用"）',
    '> （每个产物编成 exe 并真跑）；**用例覆盖** = 名字出现在该条目自带用例里',
    '> （那里的用例真编译 + 真运行，见 §17.19.58）；**未覆盖** = 模板函数/概念等无法自动生成实参的名字，',
    '> 末列写明原因 —— 账要诚实显示"还缺"。**§17.22 起每个未覆盖名字都在文末逐名登记原因与消除路径**',
    '',
    ("**汇总**：名字 {0} 个；自动探针 {1}；用例覆盖 {2}；未覆盖 {3}；探针失败产物 {4} 个" -f $totNames, $totProbe, $totTest, $totUncov, $failProducts.Count),
    '',
    '| 轨道 | 产物 | 名字 | 自动探针 | 用例覆盖 | 未覆盖 | 编译 | 运行 | 未覆盖名单（原因与消除路径见下一节） |',
    '|---|---|---|---|---|---|---|---|---|'
)
foreach ($r in ($rows | Sort-Object 轨道, 产物)) {
    $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |" -f $r.轨道, $r.产物, $r.名字, $r.自动探针, $r.用例覆盖, $r.未覆盖, $r.编译, $r.运行, $r.未覆盖名单)
}

# ---------------------------------------------------------------------------
#  §17.22 未覆盖逐名台账（判据②：剩余项都带理由 + 消除路径）
# ---------------------------------------------------------------------------
$hist = @($uncoveredAll | Group-Object 分类 | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })   # 排序要全序，否则台账不可复算
$lines += ''
$lines += ('## 未覆盖逐名台账（{0} 个名字 —— 每个都有**原因**和**消除路径**）' -f $uncoveredAll.Count)
$lines += ''
$lines += '> 判据②（§17.22）：未覆盖**不是失败**，是还欠的账；但只写"未覆盖"三个字**不算登记** ——'
$lines += '> 每个名字都要写清**为什么没覆盖**与**下一步怎么销**。这一节就是下一批工作的清单。'
$lines += ''
$lines += ('**原因分布**：' + (($hist | ForEach-Object { '{0} × {1}' -f $_.Name, $_.Count }) -join '；'))
$lines += ''
$lines += '| 产物 | 名字 | 类别 | 原因 | 消除路径 |'
$lines += '|---|---|---|---|---|'
foreach ($u in ($uncoveredAll | Sort-Object 分类, 产物, 名字)) {
    $rn = ([string]$u.原因) -replace '\|', '\|' -replace "`r?`n", ' '
    $fx = ([string]$u.消除路径) -replace '\|', '\|'
    $lines += ('| {0} | {1} | {2} | {3} | {4} |' -f $u.产物, $u.名字, $u.类别, $rn, $fx)
}
$text = ($lines -join "`r`n") + "`r`n"

if ($Check) {
    if (-not (Test-Path $ledger)) { Write-Host '❌ 实例化台账不存在：先跑 tools\check_zhinst.ps1（不带 -Check）' -ForegroundColor Red; exit 1 }
    if ([System.IO.File]::ReadAllText($ledger) -ne $text) {
        Write-Host '❌ 实例化台账【已过期】（产物或名字变了，但台账没重生成）' -ForegroundColor Red
        Write-Host '   修法：pwsh -NoProfile -File tools\check_zhinst.ps1  然后一起提交。' -ForegroundColor Yellow
        exit 1
    }
    if ($failProducts.Count) {
        Write-Host ("❌ 实例化探针失败 {0} 个产物：" -f $failProducts.Count) -ForegroundColor Red
        $failAll | Select-Object -First 12 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
    Write-Host ("  实例化守卫：通过（名字 {0}：自动探针 {1} / 用例覆盖 {2} / 未覆盖 {3}；{4} 个产物全部编过并跑过）" -f $totNames, $totProbe, $totTest, $totUncov, $rows.Count) -ForegroundColor Green
    exit 0
}

if ($Only.Count -and -not $Check) {
    Write-Host '  （-Only 调试跑：不写台账，免得把全量台账覆盖成局部的）' -ForegroundColor Yellow
} else {
    [System.IO.File]::WriteAllText($ledger, $text, $utf8)
    Write-Host "  台账已写入 docs\标准库汉化\实例化台账.md"
}
Write-Host ("=== 实例化守卫（§17.20/§17.21/§17.22）：名字 {0} 个：自动探针 {1} / 用例覆盖 {2} / 未覆盖 {3} ===" -f $totNames, $totProbe, $totTest, $totUncov) -ForegroundColor Cyan
if ($hist.Count) {
    Write-Host '  未覆盖原因分布（下一批的清单；逐名原因 + 消除路径见台账 §未覆盖逐名台账）：'
    foreach ($h in $hist) { Write-Host ("    {0,-36} {1}" -f $h.Name, $h.Count) }
}
if ($failProducts.Count) {
    Write-Host ("❌ 探针失败 {0} 个产物：" -f $failProducts.Count) -ForegroundColor Red
    $failAll | Select-Object -First 20 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
} else {
    Write-Host ("  全部 {0} 个产物的探针都编过并跑过（返回 0）" -f $rows.Count) -ForegroundColor Green
}
exit $(if ($failProducts.Count) { 1 } else { 0 })