# ============================================================================
#  check_zhname.ps1 -- §17.19.27 中文名占用守卫（变量 / 别名 / 常量）
#
#  为什么必须有（第 103 轮的两个真撞名，公开层转发守卫都没抓到）：
#    · `标准输入`：C标准输入输出 里是 `内联 文件* 常量& 标准输入 = stdin;`，
#      我在 <输入输出流> 里写 `内联 自动& 标准输入 = std::cin;` -> 同名不同型 = 重定义。
#    · `冲刷`：C标准输入输出 里已占（fflush）-> 我又拿它当 flush 的中文名。
#  两者都不是"函数转发"（§17.19.16.2 只扫 `模板 <...> 声明类型(自动) 名(`），
#  而是【变量/别名】声明 —— 于是它们一路走到组合探针才炸。
#
#  判据：**命名空间作用域的中文名字（变量、别名、常量）在全库必须唯一。**
#  与 §17.19.16.2 的区别：那里管"函数转发能不能靠签名区分"，这里管"名字本身能不能共存" ——
#  变量和别名**没有重载**，同名就是重定义（`using X = …;` 两次也是重定义）。
#
#  ⚠ 家族头用 `#ifndef` 一主一从（§17.19.25）共享同一批类型名 -> 那些属于"条件编译"，
#    不计为冲突（与 §17.19.16.2 的同名分桶一致）。
#
#  用法：pwsh -NoProfile -File tools\check_zhname.ps1 [-Quiet] [-SelfTest] [-Dir <产物目录>]
# ============================================================================
param([switch] $Quiet, [switch] $SelfTest, [string] $Dir)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')
$Name = '[\u4e00-\u9fff][\w\u4e00-\u9fff]*'   # 名字里至少要有一个汉字（且以汉字开头）

# §17.19.37 圆括号内不算命名空间作用域：算某一位次处的圆括号深度（base 为行首之前的累计深度）。
function Get-ParenDepthAt([string] $s, [int] $idx, [int] $base) {
    $d = $base
    for ($j = 0; $j -lt $idx -and $j -lt $s.Length; $j++) {
        if ($s[$j] -eq '(') { $d++ } elseif ($s[$j] -eq ')') { $d-- }
    }
    return $d
}
function Get-ZhNames([string] $dir) {
    $out = @()
    # §18.59 **修正一处"橡皮图章"**（实测发现的既有缺陷）：原先这一行写死 `Get-ZhIncludeDirs $root`，
    #   把传进来的 `$dir` **无声忽略** ⇒ 自测里 `Get-ZhNames $d` 报的临时目录根本没被扫，
    #   5 个 fixture 一个都没进判据。实测后果：原版 `-SelfTest` 报「4/5、退出码 1」
    #   （自检1 永远失败，2–5 因为"真产物本来就没冲突"而白过）。
    #   闸门跑的是**不带** -SelfTest 的那条（所以长期没人发现）。
    #   ⇒ 认 $dir：给了就扫它（自测/历史回放用），没给才走产品目录表。
    $zhProducts = if ($dir) { @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue) }
                  else { @(Get-ChildItem (Get-ZhIncludeDirs $root) -File -ErrorAction SilentlyContinue) }
if ($zhProducts.Count -eq 0) { Write-Host "❌ 一个产物都没扫到 —— 跑 0 条的通过不是通过（§15.3）" -ForegroundColor Red; exit 1 }
foreach ($f in ($zhProducts | Sort-Object Name)) {
        $stack = New-Object System.Collections.ArrayList   # 花括号种类栈
        $cond  = 0
        $paren = 0                                          # 圆括号深度（跨行累计，§17.19.37）
        $lines = [System.IO.File]::ReadAllText($f.FullName) -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $raw = $lines[$i]
            $tt = $raw.Trim()
            if     ($tt -match '^#\s*(if|ifdef|ifndef)\b') { $cond++ }
            elseif ($tt -match '^#\s*endif\b')             { if ($cond -gt 0) { $cond-- } }
            $code = ($raw -replace '//.*$', '')
            if ($code.Trim().Length -eq 0) { continue }

            $inType = @($stack | Where-Object { $_.Kind -eq 'type' }).Count -gt 0
            $path   = (@($stack | Where-Object { $_.Kind -eq 'ns' } | ForEach-Object { $_.Name }) -join '::')
            # §17.19.37 假报修正：只有【命名空间作用域 + 圆括号外 + 本行第一个 { 之前】才算命名空间级声明。
            #   来由：`空型 复制(… copy_options 丙 = …::none) { … }` 里的默认实参 `丙 =` 被当成变量，
            #   于是两个产物的形参 `丙` 撞成"跨产物同名"（假报）。假报与漏报一样坏，故收紧判据。
            $parenBase = $paren
            $paren += ([regex]::Matches($code, '\(')).Count - ([regex]::Matches($code, '\)')).Count
            $atNs = ($stack.Count -eq 0 -or $stack[$stack.Count - 1].Kind -eq 'ns')
            $braceFirst = $code.IndexOf('{')
            if (-not $inType -and $atNs) {
                $hit = $null; $kind = ''
                # 别名：使用 X = … / 模板 <…> 使用 X = …
                $m = [regex]::Match($code, "^\s*(?:模板\s*<[^>]*>\s*)?使用\s+($Name)\s*=(?!=)")
                if ($m.Success -and $parenBase -eq 0 -and ($braceFirst -lt 0 -or $m.Index -lt $braceFirst)) {
                    $hit = $m.Groups[1].Value; $kind = '别名'
                    # §18.59：把别名【右端文本】也记下来。理由（编译器实测，不是猜）：
                    #   `using 大小类型 = std::size_t;` 在同一个名域里写两遍**合法**（同型重声明），
                    #   而 `std::size_t` 与 `unsigned int` 这种【不同型】才报
                    #   「别名声明 被重定义，类型不同」。这条守卫原先一律判红 ⇒ 会把
                    #   "多个 C 头各自声明同一个 size_t 别名"这种正常写法误报成冲突。
                    #   现在按右端文本是否逐字相同来区分（压掉空白；取到分号为止）。
                    $mt = [regex]::Match($code.Substring($m.Index), '^\s*(?:模板\s*<[^>]*>\s*)?使用\s+[^=]+=\s*(?<t>[^;]+);')
                    $target = if ($mt.Success) { ($mt.Groups['t'].Value -replace '\s+', ' ').Trim() } else { '' }
                }
                # 变量/常量：内联 … X = … / 常量表达式 … X = …
                if (-not $hit -and $code -notmatch '^\s*#') {
                    $m2 = [regex]::Match($code, "(?<![\w:])($Name)\s*=(?!=)")
                    if ($m2.Success -and (Get-ParenDepthAt $code $m2.Index $parenBase) -eq 0 -and ($braceFirst -lt 0 -or $m2.Index -lt $braceFirst)) {
                        $hit = $m2.Groups[1].Value; $kind = '变量'
                    }
                }
                if ($hit) {
                    $out += [pscustomobject]@{ Product = $f.Name; Line = $i + 1; Path = $path; Name = $hit; Kind = $kind; Guarded = ($cond -gt 0)
                                               Target = $(if ($kind -eq '别名') { $target } else { '' }) }
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

function Test-ZhNames($names) {
    $conflicts = @(); $cond = @(); $sameType = @()
    foreach ($g in ($names | Group-Object { "$($_.Path)::$($_.Name)" })) {
        $items = @($g.Group)
        if ($items.Count -lt 2) { continue }
        $prods = @($items | ForEach-Object { $_.Product } | Sort-Object -Unique)
        if ($prods.Count -lt 2) { continue }                    # 同一产物里同名：交给编译器
        if (@($items | Where-Object { $_.Guarded }).Count -gt 0) { $cond += $g.Name; continue }
        # §18.59：**全是别名、且右端逐字相同** ⇒ 这是合法的同型重声明，不算冲突
        #   （编译器实测：同名同型 `using` 写两遍编得过；同名不同型才报"类型不同"）。
        #   右端不同、或掺了变量/常量（变量没有重载，同名就是重定义）⇒ 照旧报。
        $allAlias = (@($items | Where-Object { $_.Kind -eq '别名' }).Count -eq $items.Count)
        if ($allAlias) {
            $tgts = @($items | ForEach-Object { $_.Target } | Sort-Object -Unique)
            if ($tgts.Count -eq 1 -and [string]$tgts[0] -ne '') { $sameType += $g.Name; continue }
        }
        $conflicts += [pscustomobject]@{
            Name = $g.Name
            Where = (($items | ForEach-Object { "$($_.Product):$($_.Line)($($_.Kind))" }) -join ' ')
        }
    }
    return [pscustomobject]@{ Conflicts = @($conflicts); Conditional = @($cond); SameType = @($sameType) }
}

if ($SelfTest) {
    $d = Join-Path $env:TEMP ('zhname_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $d | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $w = { param($n, $t) [System.IO.File]::WriteAllText("$d\$n", $t, $utf8) }
    $pass = 0; $total = 8
    # 1 两个产物各自声明同名变量 -> 必须报
    & $w '甲' "名域 标准 {`n  内联 自动& 标准输出 = std::cout;`n}`n"
    & $w '乙' "名域 标准 {`n  内联 文件* 常量& 标准输出 = stdin;`n}`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检1 未抓住同名变量' -ForegroundColor Red }
    # 2 同名别名但带 #ifndef 一主一从 -> 归"条件编译"，不报
    & $w '乙' "#ifndef _ZH_X`n#define _ZH_X`n名域 标准 {`n  使用 标准输出 = std::cout;`n}`n#endif`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检2 误报"一主一从"' -ForegroundColor Red }
    # 3 类内成员同名不算（类型作用域）
    Remove-Item "$d\*" -Force
    & $w '甲' "名域 标准 {`n  类 甲 { 公开:`n    内联 自动& 名字 = 甲;`n  };`n}`n"
    & $w '乙' "名域 标准 {`n  类 乙 { 公开:`n    内联 自动& 名字 = 乙;`n  };`n}`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检3 误报"类内成员"' -ForegroundColor Red }
    # 4 函数形参（含默认实参）同名不算 —— 圆括号内不是命名空间作用域（§17.19.37 假报修正的回归）
    Remove-Item "$d\*" -Force
    & $w '甲' "名域 标准 {`n  空型 甲一(整数 丙 = 1);`n}`n"
    & $w '乙' "名域 标准 {`n  空型 乙一(整数 丙 = 2);`n}`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检4 误报"函数形参"' -ForegroundColor Red }
    # 5 函数体内的局部变量同名不算（单行函数体也不行）
    Remove-Item "$d\*" -Force
    & $w '甲' "名域 标准 {`n  空型 甲一() { 整数 丙 = 1; }`n}`n"
    & $w '乙' "名域 标准 {`n  空型 乙一() { 整数 丙 = 2; }`n}`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检5 误报"函数体内局部变量"' -ForegroundColor Red }
    # ---- §18.59 别名同型重声明（编译器实测支撑的三条）----
    # 6 两个产物各自 `使用 X = 同一右端;` -> **不报**（同型重声明合法）
    Remove-Item "$d\*" -Force
    & $w '甲' "名域 标准 {`n  使用 大小类型 = std::size_t;`n}`n"
    & $w '乙' "名域 标准 {`n  使用 大小类型 = std::size_t;`n}`n"
    $r6 = Test-ZhNames (Get-ZhNames $d)
    if ($r6.Conflicts.Count -eq 0 -and $r6.SameType.Count -eq 1) { $pass++ } else { Write-Host ('  ❌ 自检6 误报"同名同型别名重声明"（冲突 {0} 个）' -f $r6.Conflicts.Count) -ForegroundColor Red }
    # 7 同名但右端不同 -> **必须报**（编译器实测：`size_t` vs `unsigned int` = 别名声明被重定义，类型不同）
    Remove-Item "$d\*" -Force
    & $w '甲' "名域 标准 {`n  使用 大小类型 = std::size_t;`n}`n"
    & $w '乙' "名域 标准 {`n  使用 大小类型 = unsigned int;`n}`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检7 漏报"同名不同型别名"' -ForegroundColor Red }
    # 8 一个是别名一个是变量 -> **必须报**（变量没有重载，同名就是重定义）
    Remove-Item "$d\*" -Force
    & $w '甲' "名域 标准 {`n  使用 大小类型 = std::size_t;`n}`n"
    & $w '乙' "名域 标准 {`n  内联 整数 常量& 大小类型 = 1;`n}`n"
    if ((Test-ZhNames (Get-ZhNames $d)).Conflicts.Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检8 漏报"别名与变量同名"' -ForegroundColor Red }
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

$scan = if ($Dir) { $Dir } else { $null }   # §18.59：$null ⇒ Get-ZhNames 走产品目录表（与原来一致）
$all = Get-ZhNames $scan
$r = Test-ZhNames $all
if (-not $Quiet) {
    Write-Host ("  命名空间作用域的中文名（变量/别名）{0} 处 / {1} 个名字 / {2} 个产品" -f `
        $all.Count, (@($all | ForEach-Object { "$($_.Path)::$($_.Name)" } | Sort-Object -Unique)).Count,
        (@($all | Select-Object -ExpandProperty Product -Unique)).Count)
}
if ($r.Conditional.Count) {
    Write-Host ("  ⚠ 条件编译内同名 {0} 个（家族头 #ifndef 一主一从，§17.19.25）：{1}" -f `
        $r.Conditional.Count, (($r.Conditional | Select-Object -First 6) -join ' ')) -ForegroundColor DarkYellow
}
if ($r.SameType.Count) {
    Write-Host ("  ℹ 同名同型别名重声明 {0} 个（合法，§18.59；不计冲突）：{1}" -f `
        $r.SameType.Count, (($r.SameType | Select-Object -First 8) -join ' ')) -ForegroundColor DarkGray
}
if ($r.Conflicts.Count) {
    Write-Host ("  ❌ 跨产物同名 {0} 个（变量/别名没有重载 —— 同名就是重定义）：" -f $r.Conflicts.Count) -ForegroundColor Red
    @($r.Conflicts) | Select-Object -First 12 | ForEach-Object { Write-Host ("      {0}  {1}" -f $_.Name, $_.Where) -ForegroundColor Red }
    Write-Host '  修法：改掉其中一个中文名（先 grep 全库占用再定名），或按 §17.19.25 用 #ifndef 一主一从。' -ForegroundColor Yellow
} else {
    Write-Host ("  中文名占用守卫：通过（{0} 处声明，跨产物同名 0 个）" -f $all.Count) -ForegroundColor Green
}
exit $(if ($r.Conflicts.Count -eq 0) { 0 } else { 1 })
