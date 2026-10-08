# ============================================================================
#  check_zhforward.ps1 -- §17.19.16.2 公开层转发守卫
#
#  为什么必须有（第 82 轮）：<复数> 的单头测试 5/5 全绿，门禁却在「全量验证」报红 ——
#  根因是 <C数学> 与 <复数> 都写了【逐字相同的可变参模板】：
#      模板 <类型名... 参数> 声明类型(自动) 平方根(参数&&... 值) { 返回 std::sqrt(...); }
#  参数表一样、**又同处 `标准` 这个名字空间**，于是编译器判【重定义】，不是重载。
#
#  组合探针（tools\verify_zhstdlib.ps1）能抓到它，但那是**编译时**的：要在整个库里
#  真的撞上才报、而且只报第一条。本守卫把 §17.19.16.1 的配方变成**静态可见**的检查。
#
#  ⚠ 这个守卫是"校两次才对"的（全过程留在方案 §17.19.16.2，因为它本身就是判据的一部分）：
#    第一版 把 `字符串:28`/`向量:4016`/`互斥量:832` 这些【类内成员模板】当成重定义
#           —— **作用域**是判据的一部分，不同类里的同名同签名成员互不相干；
#           它还把 `size(...)` 与 `size(...) 常量` 当同一个签名 —— **限定符**也是签名的一部分。
#    第二版 又留下 5 对：`绝对值`（§3.14 的 `#ifndef _ZH_ABS` 一主一从，文本上重、编译时不重）
#           与 `变体` 的 `取`/`条件取`/`get`/`get_if` —— **模板形参表**也是签名的一部分
#           （`模板 <类型名 元素>` 与 `模板 <尺寸型 索引>` 是两个不同的函数模板，可以共存）。
#    第三版（本文件）四件都进判据：作用域、限定符、模板形参表、预处理条件。
#    => 判据：**静态守卫的假报和漏报一样坏**；每一条豁免都必须说得出"编译为什么不管它"。
#
#  判定（键 = 命名空间路径 + 名字 + 模板形参表形状）：
#    · 同键 + 都是可变参        = 重定义（硬失败，第 82 轮实测的机制）；
#    · 同键 + 归一化签名相同    = 重定义（硬失败）；
#    · 同键 + 签名不同          = 合法重载（打印供人工确认，不失败）；
#    · 落在 `#if*` 里的冲突     = 条件编译（打印，不失败 —— §3.14 的一主一从就靠它）。
#
#  配方（§17.19.16.1）：**默认不要用 `模板 <类型名... 参数>` 做公开转发**，
#  只有当那个名字在整个标准库里全局唯一时才安全；语义不同就该写【受限重载】。
#
#  用法：pwsh -NoProfile -File tools\check_zhforward.ps1 [-Quiet] [-SelfTest]
# ============================================================================
param([switch] $Quiet, [switch] $SelfTest)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')

# ---------------------------------------------------------------------------
#  扫描：只收【命名空间作用域】的 `模板 <...> 声明类型(自动) 名(参数表) [限定符] {`
#
#  种类栈（花括号）：开括号那一行（`{` 之前）
#    含 `名域`                            -> ns，记下名字
#    含 `类`/`结构`/`枚举`/`共用体`        -> type（成员声明一律不参与判定）
#    其余（函数体、初始化列表…）           -> other
# ---------------------------------------------------------------------------
function Get-Forwarders([string] $dir) {
    $out = @()
    # §18.61 修正一处"橡皮图章自测"（与 check_zhname 同一个形状）：
    #   原先写死 `Get-ZhIncludeDirs $root`、**无声忽略传入的 $dir** ⇒ 自测里传进来的临时目录
    #   根本没被扫，6 条 fixture 一个都没进判据（实测原版 -SelfTest = 「4/6、退出码 1」）。
    #   闸门跑的是**不带** -SelfTest 的那条 ⇒ 长期没人发现。认 $dir：给了就扫它，没给才走产品目录表。
    $zhProducts = if ($dir) { @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue) }
                  else { @(Get-ChildItem (Get-ZhIncludeDirs $root) -File -ErrorAction SilentlyContinue) }
if ($zhProducts.Count -eq 0) { Write-Host "❌ 一个产物都没扫到 —— 跑 0 条的通过不是通过（§15.3）" -ForegroundColor Red; exit 1 }
foreach ($f in ($zhProducts | Sort-Object Name)) {
        $stack = New-Object System.Collections.ArrayList
        $cond  = 0                                          # 预处理条件深度
        $lines = [System.IO.File]::ReadAllText($f.FullName) -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $raw = $lines[$i]
            $tt  = $raw.Trim()
            if     ($tt -match '^#\s*(if|ifdef|ifndef)\b') { $cond++ }
            elseif ($tt -match '^#\s*endif\b')             { if ($cond -gt 0) { $cond-- } }
            $code = ($raw -replace '//.*$', '')
            if ($code.Trim().Length -eq 0) { continue }

            # §18.61：容忍 `约束 (...)`（§18.60 给 17 条数学转发加的 requires 子句）——
            #   否则那 17 条会被**静默漏扫**（本守卫只查"同名同签名=重定义"，漏扫就等于不查）。
            $m = [regex]::Match($code, '模板\s*<([^>]*)>\s*(?:约束\s*\([^)]*\)\s*)?声明类型\(自动\)\s*([^\s(]+)\s*\(([^)]*)\)\s*([^{]{0,60}?)\{')
            $inType = @($stack | Where-Object { $_.Kind -eq 'type' }).Count -gt 0
            $path   = (@($stack | Where-Object { $_.Kind -eq 'ns' } | ForEach-Object { $_.Name }) -join '::')
            if ($m.Success -and -not $inType) {
                $tps  = $m.Groups[1].Value
                $name = $m.Groups[2].Value
                $ps   = $m.Groups[3].Value.Trim()
                $qual = ($m.Groups[4].Value -replace '\s+', ' ').Trim()
                # 模板形参表形状：种类 + 是否参数包（形参名不参与签名）
                $tshape = (@($tps -split ',') | ForEach-Object {
                    $q = $_.Trim()
                    $k = if ($q -match '^(类型名|尺寸型|整型|布尔|字符|双精度|单精度|自动|类型名\.\.\.)') { $Matches[1] } else { ($q -replace '\s+.*$', '') }
                    if ($q -match '\.\.\.') { "$k..." } else { $k }
                }) -join ','
                $variadic = $ps.Contains('...')
                $shape = $ps
                foreach ($tm in [regex]::Matches($tps, '类型名\s*(?:\.\.\.\s*)?([^\s,>]+)')) {
                    $pn = $tm.Groups[1].Value
                    if ($pn) { $shape = [regex]::Replace($shape, "\b$([regex]::Escape($pn))\b", 'T') }
                }
                $shape = (($shape -replace '\s+', ' ') -replace '([&>])\s+[\p{L}\p{N}_]+$', '$1').Trim()
                if ($qual) { $shape = "$shape $qual" }
                $out += [pscustomobject]@{
                    Product = $f.Name; Line = $i + 1; Path = $path; Name = $name
                    TShape = $tshape; Variadic = $variadic; Shape = $shape; Guarded = ($cond -gt 0)
                    Key = "$path::$name::$tshape"
                }
            }

            while ($code.Contains('{') -or $code.Contains('}')) {
                $ib = $code.IndexOf('{'); $ic = $code.IndexOf('}')
                if ($ib -ge 0 -and ($ic -lt 0 -or $ib -lt $ic)) {
                    $head = $code.Substring(0, $ib)
                    $kind = 'other'; $nm = ''
                    if ($head -match '名域\s+([^\s{]+)') { $kind = 'ns'; $nm = $Matches[1] }
                    elseif ($head -match '(类|结构|枚举|共用体)') { $kind = 'type' }
                    [void]$stack.Add([pscustomobject]@{ Kind = $kind; Name = $nm })
                    $code = $code.Substring($ib + 1)
                } else {
                    if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }
                    $code = if ($ic + 1 -lt $code.Length) { $code.Substring($ic + 1) } else { '' }
                }
            }
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
#  判定
# ---------------------------------------------------------------------------
function Test-Forwarders($fw) {
    $conflicts = @(); $sameName = @(); $cond = @()
    foreach ($g in ($fw | Group-Object Key)) {
        $items = @($g.Group)
        if ($items.Count -lt 2) { continue }
        for ($a = 0; $a -lt $items.Count; $a++) {
            for ($b = $a + 1; $b -lt $items.Count; $b++) {
                $x = $items[$a]; $y = $items[$b]
                $hit = ($x.Variadic -and $y.Variadic) -or ($x.Shape -eq $y.Shape)
                if (-not $hit) {
                    $sameName += [pscustomobject]@{ Name = $x.Key; Where = "$($x.Product):$($x.Line) 与 $($y.Product):$($y.Line)"; Detail = "$($x.Shape)  /  $($y.Shape)" }
                } elseif ($x.Guarded -or $y.Guarded) {
                    $cond += [pscustomobject]@{ Name = $x.Key; Where = "$($x.Product):$($x.Line) 与 $($y.Product):$($y.Line)"; Detail = $x.Shape }
                } else {
                    $conflicts += [pscustomobject]@{ Name = $x.Key; Where = "$($x.Product):$($x.Line) 与 $($y.Product):$($y.Line)"; Detail = $x.Shape }
                }
            }
        }
    }
    return [pscustomobject]@{ Conflicts = @($conflicts); SameName = @($sameName); Conditional = @($cond) }
}

function Show-Result($fw, $r, [switch] $Quiet) {
    $names = @($fw | Select-Object -ExpandProperty Key -Unique)
    $var   = @($fw | Where-Object { $_.Variadic })
    if (-not $Quiet) {
        Write-Host ("  命名空间作用域转发 {0} 条 / {1} 个名字 / {2} 个产品" -f $fw.Count, $names.Count,
                    (@($fw | Select-Object -ExpandProperty Product -Unique)).Count)
        Write-Host ("  其中可变参转发 {0} 条（§17.19.16.1：只有在全局唯一时才安全）" -f $var.Count) -ForegroundColor DarkGray
    }
    if ($r.SameName.Count) {
        Write-Host ("  ⚠ 同名但签名不同 {0} 对（= 合法重载，列出供人工确认）：" -f $r.SameName.Count) -ForegroundColor Yellow
        @($r.SameName) | Select-Object -First 8 | ForEach-Object { Write-Host ("      {0}  [{1}]" -f $_.Name, $_.Where) -ForegroundColor DarkYellow }
        if ($r.SameName.Count -gt 8) { Write-Host ("      …另有 {0} 对" -f ($r.SameName.Count - 8)) -ForegroundColor DarkYellow }
    }
    if ($r.Conditional.Count) {
        Write-Host ("  ⚠ 条件编译内同名同签名 {0} 对（§3.14 的一主一从靠它；组合探针为准）：" -f $r.Conditional.Count) -ForegroundColor Yellow
        @($r.Conditional) | Select-Object -First 5 | ForEach-Object { Write-Host ("      {0}  [{1}]" -f $_.Name, $_.Where) -ForegroundColor DarkYellow }
    }
    if ($r.Conflicts.Count) {
        Write-Host ("  ❌ 重定义风险 {0} 对（同签名 = 重定义，不是重载；组合探针必然报红）：" -f $r.Conflicts.Count) -ForegroundColor Red
        @($r.Conflicts) | Select-Object -First 15 | ForEach-Object { Write-Host ("      {0}  {1}   {2}" -f $_.Name, $_.Where, $_.Detail) -ForegroundColor Red }
        if ($r.Conflicts.Count -gt 15) { Write-Host ("      …另有 {0} 对" -f ($r.Conflicts.Count - 15)) -ForegroundColor Red }
        Write-Host '  修法（§17.19.16.1）：语义相同 -> 一名一主，另一头不声明；语义不同 -> 写成只吃自己那个类型的【受限重载】。' -ForegroundColor Yellow
    } else {
        Write-Host ("  公开层转发守卫：通过（{0} 条命名空间作用域声明，重定义风险 0 对）" -f $fw.Count) -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
#  自检：守卫必须能红，也必须能绿（第一版就是"能红"却"乱红"）
# ---------------------------------------------------------------------------
if ($SelfTest) {
    $d = Join-Path $env:TEMP ('zhfw_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $d | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $varNs = "名域 标准 {`n  模板 <类型名... 参数> 声明类型(自动) 平方根(参数&&... 值) { 返回 1; }`n}`n"
    $resNs = "名域 标准 {`n  模板 <类型名 元素> 声明类型(自动) 平方根(const 甲<元素>& 值) { 返回 1; }`n}`n"
    $clsA  = "名域 标准 {`n 类 甲 {`n 公开:`n  模板 <类型名... 参数> 声明类型(自动) size(参数&&... 值) { 返回 1; }`n  模板 <类型名... 参数> 声明类型(自动) size(参数&&... 值) 常量 { 返回 1; }`n }`n}`n"
    $clsB  = "名域 标准 {`n 类 乙 {`n 公开:`n  模板 <类型名... 参数> 声明类型(自动) size(参数&&... 值) { 返回 1; }`n }`n}`n"
    $pass = 0; $total = 6
    $write = { param($n, $t) [System.IO.File]::WriteAllText("$d\$n", $t, $utf8) }
    # 1 两产品都是命名空间作用域的可变参同名 -> 必须报
    & $write '甲' $varNs; & $write '乙' $varNs
    if ((Test-Forwarders (Get-Forwarders $d)).Conflicts.Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检1 未抓住"跨产品同可变参"' -ForegroundColor Red }
    # 2 可变参 + 受限重载 -> §17.19.16.1 的正解，必须不报
    & $write '乙' $resNs
    if ((Test-Forwarders (Get-Forwarders $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检2 误报"可变参 + 受限重载"' -ForegroundColor Red }
    # 3 两个不同类的同名同签名成员 -> 不算重定义（第一版就是这里乱红）
    & $write '甲' $clsA; & $write '乙' $clsB
    if ((Test-Forwarders (Get-Forwarders $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检3 误报"不同类的同名成员"' -ForegroundColor Red }
    # 4 同一个名字空间里同名同签名 -> 必须报
    & $write '甲' "名域 标准 {`n  模板 <类型名 元素> 声明类型(自动) 实部(const 甲<元素>& 值) { 返回 1; }`n  模板 <类型名 元素> 声明类型(自动) 实部(const 甲<元素>& 值) { 返回 2; }`n}`n"
    Remove-Item "$d\乙" -Force
    if ((Test-Forwarders (Get-Forwarders $d)).Conflicts.Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检4 未抓住"同名字空间同签名"' -ForegroundColor Red }
    # 5 模板形参表不同（类型名 vs 尺寸型）-> 是两个不同的函数模板，必须不报
    & $write '甲' "名域 标准 {`n  模板 <类型名 元素> 声明类型(自动) 取(元素&& 值) { 返回 1; }`n}`n"
    & $write '乙' "名域 标准 {`n  模板 <尺寸型 索引> 声明类型(自动) 取(索引&& 值) { 返回 1; }`n}`n"
    if ((Test-Forwarders (Get-Forwarders $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检5 误报"模板形参表不同"' -ForegroundColor Red }
    # 6 条件编译内同名同签名 -> 归"条件编译"，不进硬失败（§3.14 的一主一从）
    $gd = "#ifndef _ZH_甲`n名域 标准 {`n  模板 <类型名... 参数> 声明类型(自动) 绝对值(参数&&... 值) { 返回 1; }`n}`n#endif`n"
    & $write '甲' $gd; & $write '乙' $gd
    if ((Test-Forwarders (Get-Forwarders $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检6 误报"条件编译内的一主一从"' -ForegroundColor Red }
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

# ---------------------------------------------------------------------------
#  正式运行
# ---------------------------------------------------------------------------
$fw = Get-Forwarders $null   # §18.61：$null ⇒ 走产品目录表（与原来等效）；给了目录就只扫那个目录
$r  = Test-Forwarders $fw
Show-Result $fw $r -Quiet:$Quiet
exit $(if ($r.Conflicts.Count -eq 0) { 0 } else { 1 })
