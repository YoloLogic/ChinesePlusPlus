# ============================================================================
#  verify_originals.ps1 -- 铁律① 的机器守卫：**微软原库一个字节都没动**
#
#  为什么需要它（用户 2026-09-28 问："原本的英语库都没动吧"）：
#    铁律① 一直是靠"我们只读它"这个约定维持的 —— 而**约定不是守卫**。
#    本项目已经反复吃过"靠我记得"的亏（§15.1 空测、§16.30 守卫被吞、
#    §16.31 表项漏扫），所以这条最要紧的铁律也必须由机器来守。
#
#  做法：把微软 STL 头目录里每个文件的 SHA256 记进 tools\msvc_originals.sha256，
#  之后每次核对：增/删/改任何一项都报出来并退出码 1。
#  为什么用内容哈希而不是修改时间：**时间戳可以被复制/恢复，内容不会**。
#
#  用法：
#      pwsh -File tools\verify_originals.ps1            # 核对（默认）
#      pwsh -File tools\verify_originals.ps1 -Init      # 首次建立基线清单
# ============================================================================
param([switch] $Init)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$inc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$manifest = Join-Path $root 'tools\msvc_originals.sha256'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $inc)) { throw "微软 STL 头目录不在 $inc（换了 VS 版本要改本脚本顶部的路径）" }

$files = Get-ChildItem $inc -File -Recurse | Sort-Object FullName
$now = @{}
foreach ($f in $files) {
    $rel = $f.FullName.Substring($inc.Length).TrimStart('\')
    $now[$rel] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
}

if ($Init) {
    $lines = @('# 微软 STL 原文件内容哈希（铁律① 的基线）—— 由 tools\verify_originals.ps1 -Init 生成',
               "# 目录: $inc", "# 文件数: $($now.Count)")
    foreach ($k in ($now.Keys | Sort-Object)) { $lines += ("{0}  {1}" -f $now[$k], $k) }
    [System.IO.File]::WriteAllLines($manifest, $lines, $utf8)
    Write-Host ("已建立基线：{0}（{1} 个文件）" -f $manifest, $now.Count) -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $manifest)) {
    Write-Host "❌ 基线清单不存在：$manifest —— 先跑 tools\verify_originals.ps1 -Init" -ForegroundColor Red
    exit 1
}

$old = @{}
foreach ($line in [System.IO.File]::ReadAllLines($manifest)) {
    if ($line -match '^([0-9A-Fa-f]{64})\s\s(.+)$') { $old[$Matches[2]] = $Matches[1].ToUpper() }
}

$changed = @(); $missing = @(); $added = @()
foreach ($k in $old.Keys) {
    if (-not $now.ContainsKey($k)) { $missing += $k; continue }
    if ($now[$k] -ne $old[$k]) { $changed += $k }
}
foreach ($k in $now.Keys) { if (-not $old.ContainsKey($k)) { $added += $k } }

if ($changed.Count -or $missing.Count -or $added.Count) {
    Write-Host "❌ 【铁律① 被破坏】微软 STL 原文件发生了变化：" -ForegroundColor Red
    foreach ($k in $changed) { Write-Host ("   改过: {0}" -f $k) -ForegroundColor Red }
    foreach ($k in $missing) { Write-Host ("   删掉: {0}" -f $k) -ForegroundColor Red }
    foreach ($k in $added)   { Write-Host ("   新增: {0}" -f $k) -ForegroundColor Red }
    Write-Host "   —— 本项目【绝不修改微软原库】。请查清是谁写的，改回去再提交。" -ForegroundColor Yellow
    exit 1
}

Write-Host ("铁律①：微软 STL 原文件未变（{0} 个文件逐个比对 SHA256）" -f $now.Count) -ForegroundColor Green
exit 0
