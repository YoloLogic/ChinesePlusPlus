# ============================================================================
#  check_zhhijack.ps1 —— §18.61「重载劫持」守卫（第 30 道）
#
#  为什么加它（§18.60 实测出来的既有缺陷）：
#    C 轨的名字是**无约束变参转发模板**：`模板 <类型名... 参数> 声明类型(自动) 名(参数&&... 值)`。
#    它对**任何**实参都是"精确匹配"。而复制层 <复数> 对同名函数有**带类型的重载**
#    （`名(const 细节::复数实现<元素>&)`），传派生类实参时那条需要"派生→基类"转换
#    ⇒ 转换序列上变参更优 ⇒ 变参被选中 ⇒ 转发到 `std::sqrt(复数)` 无匹配 ⇒ **编不过**。
#    实测（§18.60）：`标准::平方根(复数)` 等 12 对今天就坏；`标准::双曲正弦(复数)` 也一样。
#
#  为什么不是 check_zhforward 的活：那条守卫查的是**同名同签名 = 重定义**；
#    这里是**同名不同签名之间的优劣关系**，两者判据不同、互不替代。
#
#  判据：凡【同名】既有 C 轨无约束变参（形参含 `参数&&... 值`），又有别的产物的带类型重载
#        ⇒ C 轨那一行**必须**带 `约束 (`（§18.60 给 17 条加了 `约束 (std::is_arithmetic_v<...> && ...)`）。
#
#  用法：pwsh -NoProfile -File tools\check_zhhijack.ps1 [-Quiet] [-SelfTest] [-Dir <产物目录>]
#  退出码：0 = 通过；1 = 有"会被劫持却没加约束"的转发
# ============================================================================
param([switch] $Quiet, [switch] $SelfTest, [string] $Dir)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')

# 扫出【命名空间作用域】的转发声明：名 + 形参形态 + 有没有 约束(...)
# 只认行首的 `模板 <...>`（与 check_zhforward 同一口径：类内成员模板不算）
function Get-ForwardDecls($files) {
    $out = @()
    foreach ($f in $files) {
        $txt = [System.IO.File]::ReadAllText($f)
        $txt = [regex]::Replace($txt, '/\*[\s\S]*?\*/', ' ')
        $lines = $txt -split "`n"
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $code = ($lines[$i] -replace '//.*$', '')
            $m = [regex]::Match($code, '^\s*模板\s*<[^>]*>\s*(?<req>约束\s*\([^)]*\)\s*)?声明类型\(自动\)\s*(?<n>[\u4e00-\u9fff][\w\u4e00-\u9fff]*)\s*\((?<p>[^)]*)\)')
            if ($m.Success) {
                $out += [pscustomobject]@{ 产物 = (Split-Path -Leaf $f); 文件 = $f; 行 = $i + 1
                                           名 = $m.Groups['n'].Value; 形态 = $m.Groups['p'].Value.Trim()
                                           有约束 = [bool]$m.Groups['req'].Success }
            }
        }
    }
    return $out
}

function Test-Hijack($decls) {
    $bad = @(); $okPairs = 0
    foreach ($g in ($decls | Group-Object 名)) {
        $变参 = @($g.Group | Where-Object { $_.形态 -match '参数\s*&&\s*\.\.\.' })
        $带类型 = @($g.Group | Where-Object { $_.形态 -notmatch '参数\s*&&\s*\.\.\.' })
        if ($变参.Count -ge 1 -and $带类型.Count -ge 1) {
            foreach ($v in $变参) {
                if ($v.有约束) { $okPairs++ }
                else { $bad += [pscustomobject]@{ 名 = $g.Name; 产物 = $v.产物; 行 = $v.行
                                                  对家 = (($带类型 | ForEach-Object { $_.产物 } | Sort-Object -Unique) -join ',')
                                                  对家形态 = ($带类型 | Select-Object -First 1).形态 } }
            }
        }
    }
    return [pscustomobject]@{ Bad = @($bad); OkPairs = $okPairs }
}

if ($SelfTest) {
    $d = Join-Path $env:TEMP ('zhhijack_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $d | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $pass = 0; $total = 4
    # 1 无约束变参 + 带类型重载 ⇒ 必须报
    [System.IO.File]::WriteAllText("$d\甲", "名域 标准 {`n  模板 <类型名... 参数> 声明类型(自动) 平方根(参数&&... 值) { 返回 1; }`n}`n", $utf8)
    [System.IO.File]::WriteAllText("$d\乙", "名域 标准 {`n  模板 <类型名 元素> 声明类型(自动) 平方根(常量 细节::复数实现<元素>& 值) { 返回 2; }`n}`n", $utf8)
    $r = Test-Hijack (Get-ForwardDecls @("$d\甲", "$d\乙"))
    if ($r.Bad.Count -eq 1) { $pass++ } else { Write-Host "  ❌ 自检1 未抓住无约束变参劫持（Bad=$($r.Bad.Count)）" -ForegroundColor Red }
    # 2 加了 约束(...) ⇒ 不报，且记一对
    [System.IO.File]::WriteAllText("$d\甲", "名域 标准 {`n  模板 <类型名... 参数> 约束 (std::is_arithmetic_v<std::remove_cvref_t<参数>> && ...) 声明类型(自动) 平方根(参数&&... 值) { 返回 1; }`n}`n", $utf8)
    $r2 = Test-Hijack (Get-ForwardDecls @("$d\甲", "$d\乙"))
    if ($r2.Bad.Count -eq 0 -and $r2.OkPairs -eq 1) { $pass++ } else { Write-Host "  ❌ 自检2 加了约束仍报（Bad=$($r2.Bad.Count) Ok=$($r2.OkPairs)）" -ForegroundColor Red }
    # 3 只有变参、没有 typed ⇒ 不算（不能误报）
    Remove-Item "$d\*" -Force
    [System.IO.File]::WriteAllText("$d\甲", "名域 标准 {`n  模板 <类型名... 参数> 声明类型(自动) 平方根(参数&&... 值) { 返回 1; }`n}`n", $utf8)
    $r3 = Test-Hijack (Get-ForwardDecls @("$d\甲"))
    if ($r3.Bad.Count -eq 0) { $pass++ } else { Write-Host "  ❌ 自检3 误报（只有变参也报了）" -ForegroundColor Red }
    # 4 两个都是变参（如 C标准库/C数学 的 绝对值）⇒ 不算劫持
    Remove-Item "$d\*" -Force
    [System.IO.File]::WriteAllText("$d\甲", "名域 标准 {`n  模板 <类型名... 参数> 声明类型(自动) 绝对值(参数&&... 值) { 返回 1; }`n}`n", $utf8)
    [System.IO.File]::WriteAllText("$d\乙", "名域 标准 {`n  模板 <类型名... 参数> 声明类型(自动) 绝对值(参数&&... 值) { 返回 2; }`n}`n", $utf8)
    $r4 = Test-Hijack (Get-ForwardDecls @("$d\甲", "$d\乙"))
    if ($r4.Bad.Count -eq 0) { $pass++ } else { Write-Host "  ❌ 自检4 误报（两条都是变参）" -ForegroundColor Red }
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

$scan = if ($Dir) { $Dir } else { $null }
$files = if ($scan) { @(Get-ChildItem $scan -File | ForEach-Object { $_.FullName }) }
         else { @(Get-ChildItem (Get-ZhIncludeDirs $root) -File | ForEach-Object { $_.FullName }) }
$decls = Get-ForwardDecls $files
$r = Test-Hijack $decls
if (-not $Quiet) {
    Write-Host ("  命名空间作用域转发 {0} 条 / {1} 个名字；其中【同名既有变参又有带类型重载】且**已加约束** {2} 对" -f `
        $decls.Count, (@($decls | Select-Object -ExpandProperty 名 -Unique)).Count, $r.OkPairs)
}
if ($r.Bad.Count) {
    Write-Host ("  ❌ 会被「重载劫持」却**没加约束**的转发 {0} 条：" -f $r.Bad.Count) -ForegroundColor Red
    @($r.Bad) | Select-Object -First 12 | ForEach-Object { Write-Host ("      {0}  {1}:{2}   （带类型的是 {3}：{4}）" -f $_.名, $_.产物, $_.行, $_.对家, $_.对家形态) -ForegroundColor Red }
    Write-Host '  修法：给该条加第 4 个字段 ''算术约束''（生成器会发射 `约束 (std::is_arithmetic_v<std::remove_cvref_t<参数>> && ...)`）。' -ForegroundColor Yellow
    exit 1
}
if (-not $Quiet) { Write-Host '  重载劫持守卫：通过' -ForegroundColor Green }
exit 0