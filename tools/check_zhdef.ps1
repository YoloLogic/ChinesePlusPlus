# ============================================================================
#  check_zhdef.ps1 -- §17.19.17.1 中文类型名定义守卫
#
#  为什么必须有（第 83 轮的欠账，第 84 轮补上）：
#  `<变体>` 里的 `monostate` 曾经是【半成品改名】—— 活代码用 `monostate`，`#else` 死分支里
#  留着 `单态`，而 `单态` **全库没有任何定义**。它照样编过，因为那条分支在 C++20 下永不编译；
#  同时 `<变体>` 的中文 API（`标准::单态`）其实是缺的。发现它靠的是"grep 出两种写法一半一半"，
#  那是人肉判据 —— 本守卫把它变成机器判据。
#
#  判据（不需要编译器）：**产物里凡是【类型位置】用到的 `细节::<中文名>`，
#  都必须在某个产物里有定义**（`struct/class/结构/类型/枚举/共用体/类 <名字>`，
#  或 `使用 <名字> = <别的东西>`）。
#
#  为什么只查【类型位置】：`细节::访问(甲)` 这种是**调用**，它的定义在同一批产物的函数体里，
#  静态看不出"定义方是谁"；而类型位置能机器判定，也正好是出过事的那一类。
#  类型位置的四条形态（本轮实测覆盖到的全部形态）：
#    · 前面是 `<`            -> 模板实参：`hash<细节::单态>`、`变体<标准::单态>`
#    · 后面是 `<`/`&`/`*`/`,` -> 类型用法：`const 细节::复数实现<元素>&`
#    · 后面是 ` 名字;`/`=`    -> 变量声明
#    · 前面是 `使用 X =`      -> 别名右端：`使用 单态 = 细节::单态;`
#
#  ⚠ 自别名不算定义：`使用 X = 细节::X;` 的右端本身就是"用 X"，不能拿它证明 X 有定义
#    （否则 `标准::单态` 那个别名会自己把自己证明成"已定义"，守卫就成了摆设）。
#
#  用法：pwsh -NoProfile -File tools\check_zhdef.ps1 [-Quiet] [-SelfTest] [-Dir <产物目录>]
#        -Dir 是给"历史回放"用的：拿旧提交里的产物再跑一遍，验证守卫真的抓得住（见 §17.19.17.1）。
# ============================================================================
param([switch] $Quiet, [switch] $SelfTest, [string] $Dir)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
# ⚠ 名字里至少要有一个汉字；变量名取 $ZhRx 而不是 $Nm —— PowerShell 的变量名**大小写不敏感**，
#   函数里用 `$nm` 装"匹配到的名字"会把脚本级的模式变量 `$Nm` 覆盖掉（实测：定义表只剩 1 个、
#   使用 0 处，因为模式从第二个名字起就变成了固定字符串）。这个坑写在这里，别再踩。
$ZhRx = '[_A-Za-z\u4e00-\u9fff]*[\u4e00-\u9fff][_A-Za-z0-9\u4e00-\u9fff]*'

function Get-ZhDefs([string] $dir) {
    $uses = @()
    $defReal = @{}     # struct/class/类型/枚举/共用体/类 <名字>
    $defAlias = @{}    # 使用 <名字> = <不是它自己>
    foreach ($f in (Get-ChildItem $dir -File | Sort-Object Name)) {
        $lines = [System.IO.File]::ReadAllText($f.FullName) -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $code = ($lines[$i] -replace '//.*$', '')
            if ($code.Trim().Length -eq 0) { continue }
            # 定义形态（实测补齐的三类，第 84 轮）：
            #   · `class _NODISCARD_LOCK 锁守卫实现 {`  -> 关键字与名字之间夹着宏/属性
            #   · `enum 浮点舍入方式 {`                 -> 抄来层保留英文 enum/struct/union
            #   · `inline constexpr ptrdiff_t _信号量最大值 = PTRDIFF_MAX;` -> 变量定义也算
            foreach ($m in [regex]::Matches($code, "(?:结构|struct|类型|class|枚举|共用体|类|enum|union)\s+(?:[A-Z_][A-Za-z0-9_]*\s+)*($ZhRx)")) {
                $defReal[$m.Groups[1].Value] = $true
            }
            foreach ($m in [regex]::Matches($code, "($ZhRx)\s*=")) {
                # 但 `使用 X = ...` 的左端不算（否则自别名 `使用 X = 细节::X;` 会自己证明自己，见 §17.19.17.1）
                $b2 = $code.Substring(0, $m.Index)
                if ($b2 -notmatch '使用\s+$') { $defReal[$m.Groups[1].Value] = $true }
            }
            foreach ($m in [regex]::Matches($code, "使用\s+($ZhRx)\s*=\s*(.+?);")) {
                $nm = $m.Groups[1].Value
                if ($m.Groups[2].Value.Trim() -ne "细节::$nm") { $defAlias[$nm] = $true }
            }
            foreach ($m in [regex]::Matches($code, "(?:标准::)?细节::($ZhRx)")) {
                $nm    = $m.Groups[1].Value
                $before = $code.Substring(0, $m.Index)
                $after  = $code.Substring($m.Index + $m.Length)
                # 带【显式模板实参】的函数调用（细节::取<0>(甲)）不是类型用法 —— 实测漏判过 10 处。
                $isCall = $after -match '^\s*<[^()]*>\s*\('
                $isType = $false
                if ($before -match '<[^<>]*$')                            { $isType = $true }   # 模板实参
                if (-not $isCall -and $after -match '^\s*[<>&*,]')                          { $isType = $true }   # 类型用法
                if ($after  -match '^\s+[\w\u4e00-\u9fff]+\s*[;=,)（]')    { $isType = $true }   # 变量声明
                if ($before -match "使用\s+$ZhRx\s*=\s*$")                   { $isType = $true }   # 别名右端
                if ($isType) {
                    $uses += [pscustomobject]@{ Product = $f.Name; Line = $i + 1; Name = $nm; Raw = $lines[$i].Trim() }
                }
            }
        }
    }
    return [pscustomobject]@{ Uses = @($uses); DefReal = $defReal; DefAlias = $defAlias }
}

function Test-ZhDefs($info) {
    $bad = @()
    foreach ($u in $info.Uses) {
        if ($info.DefReal.ContainsKey($u.Name) -or $info.DefAlias.ContainsKey($u.Name)) { continue }
        $bad += $u
    }
    return @($bad)
}

function Show-Result($info, $bad, [switch] $Quiet) {
    $names = @($info.Uses | Select-Object -ExpandProperty Name -Unique)
    if (-not $Quiet) {
        $nUses  = @($info.Uses).Count
        $nNames = @($names).Count
        $nProds = @($info.Uses | Select-Object -ExpandProperty Product -Unique).Count
        $nDefs  = $info.DefReal.Count + $info.DefAlias.Count
        $nAlias = $info.DefAlias.Count
        Write-Host ("  类型位置的中文限定名 {0} 处 / {1} 个名字 / {2} 个产品；定义表 {3} 个（含别名 {4} 个）" -f $nUses, $nNames, $nProds, $nDefs, $nAlias)
    }
    if ($bad.Count) {
        Write-Host ("  ❌ 没有定义的 {0} 处（半成品改名的信号：用了，但全库没定义）：" -f $bad.Count) -ForegroundColor Red
        @($bad) | Select-Object -First 12 | ForEach-Object { Write-Host ("      {0}:{1}  细节::{2}" -f $_.Product, $_.Line, $_.Name) -ForegroundColor Red }
        if ($bad.Count -gt 12) { Write-Host ("      …另有 {0} 处" -f ($bad.Count - 12)) -ForegroundColor Red }
        Write-Host '  修法（§17.19.17）：改名要在【定义侧】落地；调用侧的登记会被编译校对撤回，撤回后就是欠账。' -ForegroundColor Yellow
    } else {
        Write-Host ("  中文类型名定义守卫：通过（{0} 处限定使用，全部有定义）" -f $info.Uses.Count) -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
#  自检：守卫必须能红，也必须能绿
# ---------------------------------------------------------------------------
if ($SelfTest) {
    $d = Join-Path $env:TEMP ('zhdef_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $d | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $w = { param($n, $t) [System.IO.File]::WriteAllText("$d\$n", $t, $utf8) }
    $pass = 0; $total = 4
    # 1 用了 细节::幽灵（模板实参），全库没定义 -> 必须报
    & $w '甲' "名域 标准 { 模板 <> 结构 hash<细节::幽灵> {}; }`n"
    if ((Test-ZhDefs (Get-ZhDefs $d)).Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检1 未抓住"用了但没定义"' -ForegroundColor Red }
    # 2 另一个产物定义了它 -> 必须不报（跨产物定义也算数）
    & $w '乙' "名域 标准 { 名域 细节 { struct 幽灵 {}; } }`n"
    if ((Test-ZhDefs (Get-ZhDefs $d)).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检2 误报"跨产物已定义"' -ForegroundColor Red }
    # 3 只是【调用】（后接括号）-> 不是类型位置，必须不报
    Remove-Item "$d\乙" -Force
    & $w '甲' "名域 标准 { 名域 细节 { 声明类型(自动) 访问(整数); } }`n整数 主函数(){ 返回 细节::访问(1); }`n"
    if ((Test-ZhDefs (Get-ZhDefs $d)).Count -eq 0) { $pass++ } else { Write-Host '  ❌ 自检3 误报"函数调用"' -ForegroundColor Red }
    # 4 自别名不算定义：`使用 幽灵 = 细节::幽灵;` 不能自己证明自己
    & $w '甲' "名域 标准 { 使用 幽灵 = 细节::幽灵; }`n"
    if ((Test-ZhDefs (Get-ZhDefs $d)).Count -gt 0) { $pass++ } else { Write-Host '  ❌ 自检4 未抓住"自别名循环证明"' -ForegroundColor Red }
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

# ---------------------------------------------------------------------------
#  正式运行
# ---------------------------------------------------------------------------
$scan = if ($Dir) { $Dir } else { Join-Path $root 'zhstdlib' }
$info = Get-ZhDefs $scan
$bad  = Test-ZhDefs $info
Show-Result $info $bad -Quiet:$Quiet
exit $(if ($bad.Count -eq 0) { 0 } else { 1 })
