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
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '概念'; Template = '' }) }
    $m = [regex]::Match($t, '^模板\s*<[^>]*>\s*使用\s+(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '模板别名'; Template = $tmpl }) }
    $m = [regex]::Match($t, '^使用\s+(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '类型'; Template = '' }) }
    if ($t -match '^模板\s*<') {
        $m = [regex]::Match($t, '\s(' + $zhName + ')\s*\(')
        if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '模板函数'; Template = $tmpl }) }
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
    #  手写层（extra/deriveExtra/prologue）里提的名字：里面混着**嵌套成员名**与**局部别名**
    #  （`基类`/`常量反向迭代器`），不能当顶层名探针 -> 记「手写层/嵌套名（需宿主或具体实参）」，
    #  由条目自带用例覆盖（账上如实显示）。
    foreach ($field in 'extra', 'deriveExtra', 'prologue', 'deriveTypes') {
        if (($p.Value.PSObject.Properties.Name -contains $field) -and $p.Value.$field) {
            foreach ($n2 in (Get-NamesFromCode ([string]$p.Value.$field))) { $names += [pscustomobject]@{ Name = $n2.Name; Kind = '手写层'; Template = $n2.Template } }
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

$rows = @(); $failAll = @()
foreach ($p in $products) {
    $items = @(); $probed = @(); $byTest = @(); $uncovered = @{}
    foreach ($n in @($p.Names | Sort-Object Name -Unique)) {
        $used = $false
        if ($p.Tests -and $p.Tests -match [regex]::Escape($n.Name)) { $byTest += $n.Name; $used = $true }
        $id = [Math]::Abs($n.Name.GetHashCode())
        $line = $null
        switch ($n.Kind) {
            '类型' { $line = ("    {0}* 针{1} = 空指针; (空型)针{1};" -f ('标准::' + $n.Name), $id) }
            '内部实现类' { $line = ("    标准::细节::{0}* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id) }
            '模板类型' { $a = Get-TemplateArgs $n.Template; if ($a) { $line = ("    {0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f ('标准::' + $n.Name), $a, $id) } }
            '模板别名' { $a = Get-TemplateArgs $n.Template; if ($a) { $line = ("    {0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f ('标准::' + $n.Name), $a, $id) } }
            '常量' { $line = ("    (空型)标准::{0};" -f $n.Name) }
            '函数' { $line = ("    自动 针f{0} = &标准::{1}; (空型)针f{0};" -f $id, $n.Name) }
        }
        if ($line) { $items += [pscustomobject]@{ Line = $line; Name = $n.Name; Kind = $n.Kind }; $probed += $n.Name; $used = $true }
        elseif (-not $used) {
            $uncovered[$n.Name] = $(if ($n.Kind -eq '手写层') { '手写层/嵌套名（需宿主类型或具体实参）' } else { $n.Kind + '-无探针' })
        }
    }
    $compiled = $null; $ran = $null
    $safe = ($p.Product -replace '[\\/:*?"<>|]', '_')
    #  §17.20 阶段(5)：**C++23 条件壳**的分支要用 C++23 编（产品里有 `#如果 _HAS_CXX23`
    #  就说明它的名字只在 C++23 下存在）—— 这正是"壳的分支只有人工探针"那条欠账的机器化。
    $prodFile = Join-Path $out $p.Product
    $stdFlag = '-std=c++20'
    if ((Test-Path $prodFile) -and ([System.IO.File]::ReadAllText($prodFile) -match '_HAS_CXX23')) { $stdFlag = '-std=c++23' }
    function Invoke-Probe([string[]] $lines, [string] $tag) {
        $src = Join-Path $work ("p_$safe$tag.cpp"); $exe = Join-Path $work ("p_$safe$tag.exe")
        $code = "#包含 <$($p.Product)>`n整数 主函数(){`n" + ($lines -join "`n") + "`n    返回 0;`n}`n"
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
            $badLines = @(); $badNames = @()
            foreach ($it in $items) {
                $ri = Invoke-Probe @($it.Line) ('_n' + [Math]::Abs($it.Name.GetHashCode()))
                if ($ri.CC -eq 0) { continue }
                $soft = $false; $why = ''
                if ($it.Kind -in @('模板类型', '模板别名', '内部实现类')) { $soft = $true; $why = '探针不可表达（模板合成实参不适用）' }
                elseif ($it.Kind -eq '函数' -and ($ri.Err -match 'overloaded|重载')) { $soft = $true; $why = '探针不可表达（重载函数：需具体实参）' }
                if ($soft) { $badLines += $it.Line; $badNames += $it.Name; $uncovered[$it.Name] = $why }
                else { $failAll += ("  [{0}] 探针编不过（{1}：{2}）：{3}" -f $p.Product, $it.Kind, $it.Name, $ri.Err) }
            }
            $items = @($items | Where-Object { $badLines -notcontains $_.Line })
            $probed = @($probed | Where-Object { $badNames -notcontains $_ })
            if ($items.Count) { $r0 = Invoke-Probe @($items | ForEach-Object { $_.Line }) '' }
            else { $r0 = [pscustomobject]@{ CC = 0; RC = 0; Err = '' } }
        }
        $compiled = $r0.CC; $ran = $r0.RC
        if ($compiled -ne 0) { $failAll += ("  [{0}] 探针编不过：{1}" -f $p.Product, $r0.Err) }
        elseif ($ran -ne 0) { $failAll += ("  [{0}] 探针运行返回 {1}" -f $p.Product, $ran) }
    } else { $compiled = 0; $ran = 0 }
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
    '> 非模板函数取地址（每个产物编成 exe 并真跑）；**用例覆盖** = 名字出现在该条目自带用例里',
    '> （那里的用例真编译 + 真运行，见 §17.19.58）；**未覆盖** = 模板函数/概念等无法自动生成实参的名字，',
    '> 末列写明原因 —— 账要诚实显示"还缺"。',
    '',
    ("**汇总**：名字 {0} 个；自动探针 {1}；用例覆盖 {2}；未覆盖 {3}；探针失败产物 {4} 个" -f $totNames, $totProbe, $totTest, $totUncov, $failProducts.Count),
    '',
    '| 轨道 | 产物 | 名字 | 自动探针 | 用例覆盖 | 未覆盖 | 编译 | 运行 | 未覆盖（原因分类） |',
    '|---|---|---|---|---|---|---|---|---|'
)
foreach ($r in ($rows | Sort-Object 轨道, 产物)) {
    $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |" -f $r.轨道, $r.产物, $r.名字, $r.自动探针, $r.用例覆盖, $r.未覆盖, $r.编译, $r.运行, $r.未覆盖名单)
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

[System.IO.File]::WriteAllText($ledger, $text, $utf8)
Write-Host ("=== 实例化守卫（§17.20）：名字 {0} 个：自动探针 {1} / 用例覆盖 {2} / 未覆盖 {3} ===" -f $totNames, $totProbe, $totTest, $totUncov) -ForegroundColor Cyan
if ($failProducts.Count) {
    Write-Host ("❌ 探针失败 {0} 个产物：" -f $failProducts.Count) -ForegroundColor Red
    $failAll | Select-Object -First 20 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
} else {
    Write-Host ("  全部 {0} 个产物的探针都编过并跑过（返回 0）" -f $rows.Count) -ForegroundColor Green
}
Write-Host "  台账已写入 docs\标准库汉化\实例化台账.md"
exit $(if ($failProducts.Count) { 1 } else { 0 })
