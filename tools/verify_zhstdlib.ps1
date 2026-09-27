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

Write-Host ""
Write-Host ("=== zhstdlib 全量验证: 通过 {0} / {1} ===" -f $ok, $files.Count) -ForegroundColor Cyan
if ($bad.Count) {
    $bad | ForEach-Object { Write-Host ("  [FAIL] {0,-16} {1}" -f $_.H, $_.E) -ForegroundColor Yellow }
    exit 1
}
Write-Host "  全部通过" -ForegroundColor Green
exit 0
