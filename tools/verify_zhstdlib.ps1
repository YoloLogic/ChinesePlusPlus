# ============================================================================
#  verify_zhstdlib.ps1 -- 全量验证 zhstdlib 里【每一个】中文头
#
#  为什么必须单独有一个：单个头"能编过"不等于整批没问题 ——
#  实测踩过两次"英文名副本 shadow 微软真头"（zhstdlib\type_traits 把真
#  <type_traits> 挤掉，连累 cmath/ccomplex/ctgmath）。那种问题只有全量跑才看得见。
#
#  做法：把 zhstdlib 的每个头单独 #包含 一遍，逐个 -fsyntax-only。
#
#  ⚠ 每个头要检【两次】，第二次是【同一个头连包含两遍】。
#  为什么（2026-09-27 实测，潜伏很久的 bug）：我们在原头末尾追加了派生层，
#  而 MSVC 公开头的最末一行正是包含守卫的 `#endif` —— 于是派生层落在守卫【外面】，
#  同一个头被包含两次时正文被跳过、派生层却被编译第二遍：
#      error: 重定义（名字） '互斥量' / '独占锁' / '锁守卫'
#  单头探针永远照不出来；只有 <共享互斥量>（它经 <条件变量> 又回到 <互斥量>）
#  这种"同一个头进两次"的场景才炸得出来。修好之后把探针留在这里，
#  让这条规矩以后由机器来守，而不是靠我记得。
#
#  用法：powershell -File tools\verify_zhstdlib.ps1
# ============================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$inc  = Join-Path $root 'zhstdlib'
$d    = Join-Path $root 'build\_zfull'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $inc)) { throw "zhstdlib 不存在" }
if (Test-Path $d) { Remove-Item -Recurse -Force $d }
New-Item -ItemType Directory -Force $d | Out-Null

$files = Get-ChildItem $inc -File | Sort-Object Name
$ok = 0; $bad = @()
foreach ($f in $files) {
    $fail = $null
    # 探针 1：引一次  探针 2：同一个头连引两次（查包含守卫，见文件头注释）
    $probes = @(
        @{ tag = '';     body = "#包含 <$($f.Name)>`n" },
        @{ tag = '二次:'; body = "#包含 <$($f.Name)>`n#包含 <$($f.Name)>`n" }
    )
    foreach ($p in $probes) {
        $src = Join-Path $d 't.cpp'
        [System.IO.File]::WriteAllText($src, $p.body + "整数 主函数(){ 返回 0; }`n", $utf8)
        & cmd /c "`"$cxx`" -std=c++20 -isystem`"$inc`" -fsyntax-only `"$src`" > `"$d\o.txt`" 2>&1"
        if ($LASTEXITCODE -ne 0) {
            $first = Get-Content "$d\o.txt" -ErrorAction SilentlyContinue |
                     Where-Object { $_ -match 'error:' } | Select-Object -First 1
            $fail = $p.tag + ([string]$first).Trim()
            break
        }
    }
    if ($fail) { $bad += [pscustomobject]@{ H = $f.Name; E = $fail } } else { $ok++ }
}
Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
#  组合探针：把【全部】汉语头放进同一个 TU 一起引。
#
#  为什么必须有（实测抓到的第一个真问题，见方案 §3.14）：
#  汉语别名全都落在同一个 `标准` 里 —— 两个头声明同一个中文名就是【重定义】。
#  而 C 库在标准里是故意重叠的：std::abs 既属于 <cstdlib> 也属于 <cmath>，
#  于是 <C标准库> 与 <C数学> 都想声明 标准::绝对值：
#      error: 重定义（名字）'绝对值'
#  单头探针永远照不出来（每个头自己都好好的）。
#  同理它也能照出抄+派生轨道里"两个头都定义了 标准::细节::X"这类跨头撞名。
# ---------------------------------------------------------------------------
$all = Join-Path $d 'all.cpp'
New-Item -ItemType Directory -Force $d | Out-Null   # 上面刚把 $d 删了，这里要重建
$lines = (Get-ChildItem $inc -File | Sort-Object Name | ForEach-Object { "#包含 <$($_.Name)>" }) -join "`n"
[System.IO.File]::WriteAllText($all, $lines + "`n整数 主函数(){ 返回 0; }`n", $utf8)
$allOk = $true; $allErr = ''
& cmd /c "`"$cxx`" -std=c++20 -isystem`"$inc`" -fsyntax-only `"$all`" > `"$d\all_o.txt`" 2>&1"
if ($LASTEXITCODE -ne 0) {
    $allOk = $false
    $allErr = ([string]((Get-Content "$d\all_o.txt" -ErrorAction SilentlyContinue |
                Where-Object { $_ -match 'error:' } | Select-Object -First 1))).Trim()
}
Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
#  §16.63 调试/硬化配置探针：同一个组合 TU，换 `_ITERATOR_DEBUG_LEVEL` 再编两遍。
#
#  为什么必须有：我们所有产品【一直只在默认配置下被编译过】，而
#  `_ITERATOR_DEBUG_LEVEL` 在 std 里切换的是**结构不同的分支**：
#      `_Container_base12` / `_Iterator_base12`（带代理与迭代器链）
#   与 `_Container_base0` / `_Iterator_base0`（空基类、无链）。
#  这些名字在 `内存内部件` 里都被翻成汉语了，而 `#if _ITERATOR_DEBUG_LEVEL == 0`
#  那一支【从来没被编译过】—— 典型的"隐形规矩"（§16.42 的老教训）。
#  另外开源项目常带 `/D_ITERATOR_DEBUG_LEVEL=0`（Release 配置）编译，
#  铁律②要求"随便拿一个开源项目也必须照样编得过"，这一条正是它的机器保证。
#
#  ⚠ 用 `-fsyntax-only` 且**只换这一个宏**：改动面越小，报出来的就越是真问题。
#  ⚠ 只测 0 与 1：`_ITERATOR_DEBUG_LEVEL=2` 在 release 模式下是 `yvals.h:66`
#    自己拒的（"not supported in release mode"），那要连 `-D_DEBUG` 一起给，
#    会把别的开关也带进来 —— 而 **0 与 1 已经覆盖了我们真正关心的两条分支**
#    （`_Container_base0`/`_Iterator_base0` 与 `_Container_base12`/`_Iterator_base12`，
#     见 xmemory 里那句 `#if _ITERATOR_DEBUG_LEVEL == 0`）。
#  ⚠ 先做【报告】而不是直接判失败：配置相关的失败往往要单独修一轮，
#    把它显式打出来（按 §16.42：守卫必须可见），有失败就计入退出码。
# ---------------------------------------------------------------------------
$d2 = Join-Path $root 'build\_zhverify_cfg'
New-Item -ItemType Directory -Force $d2 | Out-Null
$cfg = @()
foreach ($lvl in @('0', '1')) {
    $src = Join-Path $d2 "all_idl$lvl.cpp"
    [System.IO.File]::WriteAllText($src, $lines + "`n整数 主函数(){ 返回 0; }`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$inc`" -D_ITERATOR_DEBUG_LEVEL=$lvl -fsyntax-only `"$src`" > `"$d2\o$lvl.txt`" 2>&1"
    $e = ''
    if ($LASTEXITCODE -ne 0) {
        $e = ([string]((Get-Content "$d2\o$lvl.txt" -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match 'error:' } | Select-Object -First 1))).Trim()
    }
    $cfg += [pscustomobject]@{ Lvl = $lvl; Ok = ($LASTEXITCODE -eq 0); Err = $e }
}
Remove-Item -Recurse -Force $d2 -ErrorAction SilentlyContinue
$cfgOk = @($cfg | Where-Object { -not $_.Ok }).Count -eq 0
Write-Host ""
if ($cfgOk) {
    Write-Host ("  调试配置探针（_ITERATOR_DEBUG_LEVEL = 0 / 1，全部 {0} 个头一起引）: 通过" -f $files.Count) -ForegroundColor Green
} else {
    Write-Host "  调试配置探针: FAIL（我们的产品只在默认配置下被编译过）" -ForegroundColor Yellow
    $cfg | Where-Object { -not $_.Ok } | ForEach-Object {
        Write-Host ("    _ITERATOR_DEBUG_LEVEL={0}: {1}" -f $_.Lvl, $_.Err) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ("=== zhstdlib 全量验证: 通过 {0} / {1} ===" -f $ok, $files.Count) -ForegroundColor Cyan
if ($allOk) {
    Write-Host ("  组合探针（全部 {0} 个头一起引）: 通过" -f $files.Count) -ForegroundColor Green
} else {
    Write-Host "  组合探针（全部头一起引）: FAIL" -ForegroundColor Yellow
    Write-Host ("    {0}" -f $allErr) -ForegroundColor Yellow
}
if ($bad.Count) {
    $bad | ForEach-Object { Write-Host ("  [FAIL] {0,-16} {1}" -f $_.H, $_.E) -ForegroundColor Yellow }
    exit 1
}
if (-not $allOk) { exit 1 }
if (-not $cfgOk) { exit 1 }
Write-Host "  全部通过" -ForegroundColor Green
exit 0
