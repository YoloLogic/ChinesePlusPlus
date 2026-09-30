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
$Name = '[\u4e00-\u9fff][\w\u4e00-\u9fff]*'   # 名字里至少要有一个汉字（且以汉字开头）

function Get-ZhNames([string] $dir) {
    $out = @()
    foreach ($f in (Get-ChildItem $dir -File | Sort-Object Name)) {
        $stack = New-Object System.Collections.ArrayList   # 花括号种类栈
        $cond  = 0
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
            if (-not $inType) {
                $hit = $null; $kind = ''
                # 别名：使用 X = … / 模板 <…> 使用 X = …
                $m = [regex]::Match($code, "^\s*(?:模板\s*<[^>]*>\s*)?使用\s+($Name)\s*=(?!=)")
                if ($m.Success) { $hit = $m.Groups[1].Value; $kind = '别名' }
                # 变量/常量：内联 … X = … / 常量表达式 … X = …
                if (-not $hit -and $code -notmatch '^\s*#') {
                    $m2 = [regex]::Match($code, "(?<![\w:])($Name)\s*=(?!=)")
                    if ($m2.Success) { $hit = $m2.Groups[1].Value; $kind = '变量' }
                }
                if ($hit) {
                    $out += [pscustomobject]@{ Product = $f.Name; Line = $i + 1; Path = $path; Name = $hit; Kind = $kind; Guarded = ($cond -gt 0) }
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
    $conflicts = @(); $cond = @()
    foreach ($g in ($names | Group-Object { "$($_.Path)::$($_.Name)" })) {
        $items = @($g.Group)
        if ($items.Count -lt 2) { continue }
        $prods = @($items | ForEach-Object { $_.Product } | Sort-Object -Unique)
        if ($prods.Count -lt 2) { continue }                    # 同一产物里同名：交给编译器
        if (@($items | Where-Object { $_.Guarded }).Count -gt 0) { $cond += $g.Name; continue }
        $conflicts += [pscustomobject]@{
            Name = $g.Name
            Where = (($items | ForEach-Object { "$($_.Product):$($_.Line)($($_.Kind))" }) -join ' ')
        }
    }
    return [pscustomobject]@{ Conflicts = @($conflicts); Conditional = @($cond) }
}

if ($SelfTest) {
    $d = Join-Path $env:TEMP ('zhname_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $d | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $w = { param($n, $t) [System.IO.File]::WriteAllText("$d\$n", $t, $utf8) }
    $pass = 0; $total = 3
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
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
    Write-Host ("自检：{0}/{1}" -f $pass, $total) -ForegroundColor $(if ($pass -eq $total) { 'Green' } else { 'Red' })
    exit $(if ($pass -eq $total) { 0 } else { 1 })
}

$scan = if ($Dir) { $Dir } else { Join-Path $root 'zhstdlib' }
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
if ($r.Conflicts.Count) {
    Write-Host ("  ❌ 跨产物同名 {0} 个（变量/别名没有重载 —— 同名就是重定义）：" -f $r.Conflicts.Count) -ForegroundColor Red
    @($r.Conflicts) | Select-Object -First 12 | ForEach-Object { Write-Host ("      {0}  {1}" -f $_.Name, $_.Where) -ForegroundColor Red }
    Write-Host '  修法：改掉其中一个中文名（先 grep 全库占用再定名），或按 §17.19.25 用 #ifndef 一主一从。' -ForegroundColor Yellow
} else {
    Write-Host ("  中文名占用守卫：通过（{0} 处声明，跨产物同名 0 个）" -f $all.Count) -ForegroundColor Green
}
exit $(if ($r.Conflicts.Count -eq 0) { 0 } else { 1 })
