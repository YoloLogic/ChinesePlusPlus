# ============================================================================
#  补丁与源码树一致性守卫（第 23 道）—— §18.11
#  （大检查台账里"待定：这次顺带发现的一条'没有护栏'的事"）
#
#  背景（台账原话）：
#    改了**编译器源码**却忘记重跑 `tools\make_patch.ps1` ⇒ 补丁与源码树不一致，
#    而**没有任何守卫会发现**（`regen_zhstdlib.ps1` 里 `patch` / `补丁` /
#    `make_patch` 三个词一次都不出现）。P-01 那次靠"人记得"跑了。
#    ⇒ 建议把"补丁必须能重放成当前源码树"做成闸门项。
#
#  判据（两条）：
#    ① **不落后**：重新生成一遍补丁（`make_patch.ps1 -Check`：生成到 scratch，
#       **不动** `patches\`），再与仓库里那份**逐字节**比 —— 不一致就红。
#       不一致的含义只有一个：**改了编译器源码而 patches\ 里那份是旧的**。
#    ② **自测**：逐字节比较这个判据必须**能失败** —— 改坏一个字节必须报不同，
#       自己和自己比必须报相同。
#
#  为什么这么便宜：`make_patch.ps1` 末尾那段"把补丁打回干净树、必须等于我们的树"
#  本来就是现成的判据（台账原话），只差接进闸门。
#
#  跑法：pwsh -NoProfile -File tools\check_zhpatch.ps1
#  退出码：0 = 补丁与源码树一致；1 = 有失败
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$真 = Join-Path $Root 'patches'
$新 = Join-Path $Root 'build\_zhpatch'
New-Item -ItemType Directory -Force $新 | Out-Null

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }

function 文件相同([string]$x, [string]$y) {
    if (-not (Test-Path $x) -or -not (Test-Path $y)) { return $false }
    return ((Get-FileHash $x -Algorithm SHA256).Hash -eq (Get-FileHash $y -Algorithm SHA256).Hash)
}

# ---------------------------------------------------------------------------
#  ① 重新生成（到 scratch）+ 重放校验，再逐字节比
# ---------------------------------------------------------------------------
$log = Join-Path $新 'make_patch_check.log'
& pwsh -NoProfile -File (Join-Path $Root 'tools\make_patch.ps1') -Check *> $log
$rc = $LASTEXITCODE
if ($rc -ne 0) {
    错 ("重新生成补丁失败（make_patch.ps1 -Check 退出码 {0}）—— 要么源码树本身有问题，要么'补丁打回干净树 != 我们的树'；日志尾：" -f $rc)
    Get-Content $log -Tail 12 | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor DarkRed }
}

foreach ($n in @('zh-keywords.patch', 'zh-diagnostics.patch')) {
    $老 = Join-Path $真 $n
    $生成 = Join-Path $新 $n
    if (-not (Test-Path $老)) { 错 ("patches\{0} 不存在（补丁没生成过？）" -f $n); continue }
    if (-not (Test-Path $生成)) { 错 ("{0}：-Check 没生成出这一份（上一条应该已经报错）" -f $n); continue }
    $尺寸 = (Get-Item $生成).Length
    if (文件相同 $老 $生成) {
        过 ("{0}：与重新生成的**逐字节一致**（{1:N0} 字节 —— 补丁没有落后于源码树）" -f $n, $尺寸)
    } else {
        错 ("{0}：与重新生成的不一致 —— **改了编译器源码之后忘了重跑 tools\make_patch.ps1**（或 patches\ 里那份是旧的，会误导打补丁的人）" -f $n)
    }
}

# ---------------------------------------------------------------------------
#  ② 自测：这个判据必须能失败
# ---------------------------------------------------------------------------
$样 = Join-Path $真 'zh-keywords.patch'
if (Test-Path $样) {
    $坏 = Join-Path $新 'selftest_mutated.patch'
    $b = [System.IO.File]::ReadAllBytes($样)
    $b[[int]($b.Length / 2)] = $b[[int]($b.Length / 2)] -bxor 0xFF
    [System.IO.File]::WriteAllBytes($坏, $b)
    if (文件相同 $样 $坏) {
        错 "自测失败：改坏一个字节竟然还算'一致' —— 这个判据是橡皮图章"
    } elseif (-not (文件相同 $样 $样)) {
        错 "自测失败：文件与它自己比竟然不算'一致'"
    } else {
        过 "自测：逐字节比较能区分（改坏一个字节 → 不同；自己和自己比 → 相同）"
    }
    Remove-Item $坏 -Force -ErrorAction SilentlyContinue
} else {
    错 "自测没法跑：patches\zh-keywords.patch 不存在"
}

Write-Host ''
if ($script:fail -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host ("  => FAIL（{0} 条）" -f $script:fail) -ForegroundColor Red
exit 1
