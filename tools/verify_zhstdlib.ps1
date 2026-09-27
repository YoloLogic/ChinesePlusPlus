# ============================================================================
#  verify_zhstdlib.ps1 -- 全量验证 zhstdlib 里【每一个】中文头
#
#  为什么必须单独有一个：单个头"能编过"不等于整批没问题 ——
#  实测踩过两次"英文名副本 shadow 微软真头"（zhstdlib\type_traits 把真
#  <type_traits> 挤掉，连累 cmath/ccomplex/ctgmath）。那种问题只有全量跑才看得见。
#
#  做法：把 zhstdlib 的每个头单独 #包含 一遍，逐个 -fsyntax-only。
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
    $src = Join-Path $d 't.cpp'
    [System.IO.File]::WriteAllText($src, "#包含 <$($f.Name)>`n整数 主函数(){ 返回 0; }`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$inc`" -fsyntax-only `"$src`" > `"$d\o.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { $ok++ }
    else {
        $first = Get-Content "$d\o.txt" -ErrorAction SilentlyContinue |
                 Where-Object { $_ -match 'error:' } | Select-Object -First 1
        $bad += [pscustomobject]@{ H = $f.Name; E = ([string]$first).Trim() }
    }
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
