# ============================================================================
#  copy_zhstdlib.ps1 -- 阶段 1：把微软 STL 的公开头【全部复制一份】
#
#  只做结构改造，名字一个都不改：
#    1. 换 include 守卫（_VECTOR_ -> _ZH_VECTOR_，不抢微软的）
#    2. _STD_BEGIN -> 名域 标准 { 名域 细节 { + 使用 名域 std;
#       _STD_END   -> } }
#    3. 文件名先沿用英文（中文文件名在阶段 3 用译名表统一改）
#
#  为什么必须先全部复制、再统一改（见 docs\标准库汉化\标准库汉化方案.md 第三节）：
#    译名表必须【全局建好再套用】。一个文件端到端地改，会出现
#    "vector 里 size 叫尺寸、map 里 size 叫个数"这种跨文件漂移。
#
#  用法：
#      powershell -File tools\copy_zhstdlib.ps1              # 复制 + 逐个验证
#      powershell -File tools\copy_zhstdlib.ps1 -NoVerify    # 只复制
#
#  ⚠ VS 版本号在下面写死；换 VS 版本要改 $vsInc。
# ============================================================================
param(
    [switch] $NoVerify
)

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx   = Join-Path $root 'build\Release\bin\chinese++.exe'
$vsInc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$out   = Join-Path $root 'zhstdlib'
if (-not (Test-Path $vsInc)) { throw "MSVC STL 不在 $vsInc —— 换 VS 版本请改脚本顶部路径" }
if (-not (Test-Path $cxx))   { throw "找不到编译器 $cxx" }
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 要复制的 112 个公开标准头 = 无扩展名 且 不以 x 开头（x 是微软内部件）
$headers = Get-ChildItem $vsInc -File |
           Where-Object { $_.Extension -eq '' -and $_.Name -notmatch '^x' } |
           Select-Object -ExpandProperty Name | Sort-Object

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null

Write-Host "=== 阶段 1：复制 $($headers.Count) 个公开头 ===" -ForegroundColor Cyan

$srcTotal = 0; $dstTotal = 0; $guardFails = @(); $done = 0

foreach ($h in $headers) {
    $srcPath = Join-Path $vsInc $h
    $text = [System.IO.File]::ReadAllText($srcPath)
    $srcTotal += ([System.IO.File]::ReadAllLines($srcPath)).Count

    # 步 1：换守卫。取最前面的 #ifndef X / #define X 一对。
    $gm = [regex]::Match($text, '(?m)^#ifndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\r?\n#define\s+\1\b')
    if ($gm.Success) {
        $g = $gm.Groups[1].Value
        $ng = '_ZH_' + ($h.ToUpper() -replace '[^A-Z0-9]', '_') + '_'
        $text = $text.Replace("#ifndef $g", "#ifndef $ng").Replace("#define $g", "#define $ng")
    } else {
        # 有些头（如 <cassert>）没有守卫，用 #pragma once
        $guardFails += $h
        $text = "#pragma once`n" + $text
    }

    # 步 2：搬进 标准::细节 + 兜底
    $nb = ([regex]::Matches($text, '_STD_BEGIN')).Count
    $text = $text.Replace('_STD_BEGIN', "名域 标准 { 名域 细节 {`n使用 名域 std;")
    $text = $text.Replace('_STD_END', '} }')

    [System.IO.File]::WriteAllText((Join-Path $out $h), $text, $utf8)
    $dstTotal += ([System.IO.File]::ReadAllLines((Join-Path $out $h))).Count
    $done++
}
Write-Host ("  复制完成: {0} 个文件   源 {1:N0} 行 -> 目标 {2:N0} 行（+{3:N0}）" -f `
    $done, $srcTotal, $dstTotal, ($dstTotal - $srcTotal))
if ($guardFails.Count) {
    Write-Host ("  没找到 include 守卫、改用 #pragma once 的: {0} 个" -f $guardFails.Count) -ForegroundColor Yellow
    Write-Host ("    " + ($guardFails -join ' '))
}
Write-Host ("  一个字都没改（阶段 3 才改名）。输出目录: {0}" -f $out) -ForegroundColor Green

if ($NoVerify) { return }

# ---------------------------------------------------------------------------
#  验证：112 个逐个 -fsyntax-only。这一步证明"结构改造"对【每一个】都成立，
#  而不是只对 vector 成立 —— 这正是先全部复制、再统一改的价值所在。
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 验证：逐个编译 112 个 ===" -ForegroundColor Cyan
$tmp = Join-Path $root 'build\_zcopy'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force $tmp | Out-Null

$okList = @(); $badList = @()
foreach ($h in $headers) {
    $src = Join-Path $tmp 't.cpp'
    [System.IO.File]::WriteAllText($src, "#包含 <$h>`n整数 主函数(){ 返回 0; }`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -fsyntax-only `"$src`" > `"$tmp\out.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { $okList += $h }
    else {
        $first = (Get-Content "$tmp\out.txt" -ErrorAction SilentlyContinue |
                  Where-Object { $_ -match 'error:' } | Select-Object -First 1)
        $badList += [pscustomobject]@{ Header = $h; Err = ([string]$first).Trim() }
    }
}
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

Write-Host ("  通过 {0} / {1}" -f $okList.Count, $headers.Count) -ForegroundColor Green
if ($badList.Count) {
    Write-Host ("  失败 {0} 个：" -f $badList.Count) -ForegroundColor Yellow
    $badList | ForEach-Object { Write-Host ("    {0,-24} {1}" -f $_.Header, $_.Err) }
}
