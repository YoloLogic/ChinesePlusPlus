# ============================================================================
#  check_stuck.ps1 —— 长任务「是不是卡住了」的证据式检测器（§17.34）
#
#  为什么要它（2026-10-01 实测误判）：
#    闸门跑到第 30 分钟时我只看了一个目录（`third_party\`）就说"卡了"——
#    其实第三方两批早在 09:53 跑完，闸门正在**实例化守卫**里编探针（写的是 `build\_zhinst`）。
#    教训：**"某处没动静"不等于"卡住"**；判定必须看**多个活动源** + **进程树**，
#    而且要**采样**（看 delta），不能只看一眼快照。
#
#  判定（全部都要满足才算"疑似卡住"）：
#    ① 根任务已运行 ≥ -StuckAfterMinutes（默认 25 分钟）
#    ② 采样窗口内：看护目录的**文件数不增、最新写入时间不动**
#    ③ 采样窗口内：进程树里**没有编译器类子进程**（chinese++/clang/ninja/cmake/lld/link）
#    ④ 日志文件在采样窗口内没有增长
#  只要有一条不成立，就是**活跃**（并打印是哪条证据救的它）。
#
#  用法：
#    pwsh -NoProfile -File tools\check_stuck.ps1                       # 自动找最长的长任务
#    pwsh -NoProfile -File tools\check_stuck.ps1 -RootPattern regen    # 指定命令行关键字
#    pwsh -NoProfile -File tools\check_stuck.ps1 -SampleSeconds 30 -StuckAfterMinutes 25
#  退出码：0 = 活跃；1 = 疑似卡住；2 = 没找到目标任务（不算卡住，但**必须查**）
# ============================================================================
param(
    [string] $RootPattern = '',
    [string[]] $Watch = @('build\_zhinst', 'third_party\build', 'third_party\logs', 'build\_zha', 'build\_zhc_case', 'build\Release'),
    [int] $SampleSeconds = 20,
    [int] $StuckAfterMinutes = 25,
    [string] $LogFile = '',
    [switch] $Loop,
    [int] $IntervalSeconds = 300,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
#  §17.34 `-Loop`：作为**监测器**跟着长任务跑 —— 每 `-IntervalSeconds` 秒判一次，
#  一旦"疑似卡住"就大声打一行（落进任务输出/日志，人立刻看得见）。
if ($Loop) {
    while ($true) {
        Start-Sleep -Seconds $IntervalSeconds
        & pwsh -NoProfile -File $PSCommandPath -RootPattern $RootPattern -SampleSeconds $SampleSeconds -StuckAfterMinutes $StuckAfterMinutes -LogFile $LogFile -Quiet
        if ($LASTEXITCODE -eq 1) {
            Write-Host ("!! 看门狗（§17.34）：目标任务 [{0}] 疑似卡住，{1} —— 按输出里的『下一步』查，别只说卡了" -f $RootPattern, (Get-Date).ToString('HH:mm:ss')) -ForegroundColor Red
        } elseif ($LASTEXITCODE -eq 2) {
            Write-Host ("看门狗：{0} 没找到目标任务（已结束？）—— 监测退出" -f (Get-Date).ToString('HH:mm:ss')) -ForegroundColor DarkGray
            exit 0
        }
    }
}
#  根探测：不能假设"脚本就在 tools\ 下" —— 第一版按 `..\..` 推，放在 build\_review_own\ 里试跑时
#  推成了 `build\`，于是看护目录全不存在 -> 空证据也判"卡住"（正是"没证据就下结论"的翻版）。
#  改成**认标记**：往上找，直到看见 `tools\regen_zhstdlib.ps1`。
$root = $PSScriptRoot
for ($i = 0; $i -lt 6; $i++) {
    if (Test-Path (Join-Path $root 'tools\regen_zhstdlib.ps1')) { break }
    $up = Split-Path -Parent $root
    if (-not $up -or $up -eq $root) { break }
    $root = $up
}
if (-not (Test-Path (Join-Path $root 'tools\regen_zhstdlib.ps1'))) { Write-Host '看门狗：找不到仓库根（认 tools\regen_zhstdlib.ps1 这个标记）' -ForegroundColor Red; exit 2 }
function Say([string] $s, [string] $color = 'Gray') { if (-not $Quiet) { Write-Host $s -ForegroundColor $color } }

$procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
function Get-Tree([int] $rootPid) {
    $all = @($rootPid); $cur = @($rootPid)
    for ($d = 0; $d -lt 8; $d++) {
        $next = @($procs | Where-Object { $cur -contains $_.ParentProcessId } | ForEach-Object { [int]$_.ProcessId })
        $next = @($next | Where-Object { $all -notcontains $_ })
        if (-not $next.Count) { break }
        $all += $next; $cur = $next
    }
    return $all
}
function Get-Activity {
    $n = 0; $newest = [datetime]::MinValue; $newestName = ''
    foreach ($d in $Watch) {
        $p = Join-Path $root $d
        if (-not (Test-Path $p)) { continue }
        foreach ($f in (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue)) {
            $n++
            if ($f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime; $newestName = $f.Name }
        }
    }
    return @{ Count = $n; Newest = $newest; NewestName = $newestName }
}

# 找目标长任务：优先 -RootPattern，否则取"跑得最久的、命令行像闸门/守卫"的 pwsh
$cand = @($procs | Where-Object { $_.Name -eq 'pwsh.exe' -and $_.CommandLine -and $_.CommandLine -match '\.ps1' })
if ($RootPattern) { $cand = @($cand | Where-Object { $_.CommandLine -match $RootPattern }) }
if (-not $cand.Count) {
    Say '看门狗：没找到目标任务（-RootPattern 写错？或任务已结束）' 'Yellow'
    exit 2
}
$target = $cand | Sort-Object { $_.CreationDate } | Select-Object -First 1
$tp = [int]$target.ProcessId
$started = try { [Management.ManagementDateTimeConverter]::ToDateTime($target.CreationDate) } catch { (Get-Process -Id $tp -ErrorAction SilentlyContinue).StartTime }
$ageMin = [Math]::Round(((Get-Date) - $started).TotalMinutes, 1)
$tree = Get-Tree $tp

$a1 = Get-Activity
$logBefore = 0; $logPath = $LogFile
if (-not $logPath) {
    $lg = Get-ChildItem (Join-Path $root 'build\_review_own') -File -Filter 'commit*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($lg) { $logPath = $lg.FullName }
}
if ($logPath -and (Test-Path $logPath)) { $logBefore = (Get-Item $logPath).Length }
Start-Sleep -Seconds $SampleSeconds
$a2 = Get-Activity
$logAfter = 0; if ($logPath -and (Test-Path $logPath)) { $logAfter = (Get-Item $logPath).Length }
$procs2 = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
$tree2 = Get-Tree $tp
$compilers = @($procs2 | Where-Object { $tree2 -contains [int]$_.ProcessId -and $_.Name -match 'chinese|clang|ninja|cmake|lld|link|cl$' })

Say ''
Say ("看门狗（§17.34）—— 采样 {0} 秒，卡住门槛 {1} 分钟" -f $SampleSeconds, $StuckAfterMinutes) 'Cyan'
Say ("  目标任务   {0}（PID {1}，已跑 {2} 分钟）" -f ([regex]::Match([string]$target.CommandLine, '([\w_]+\.ps1)').Groups[1].Value), $tp, $ageMin)
Say ("  进程树     {0} 个进程：{1}" -f $tree.Count, (($procs2 | Where-Object { $tree2 -contains [int]$_.ProcessId } | ForEach-Object { $_.Name }) -join ' '))
Say ("  文件活动   {0} 个文件；采样前最新 {1}（{2}）→ 采样后最新 {3}（{4}）" -f $a2.Count, $a1.Newest.ToString('HH:mm:ss'), $a1.NewestName, $a2.Newest.ToString('HH:mm:ss'), $a2.NewestName)
Say ("  日志       {0}：{1} → {2} 字节" -f $(if ($logPath) { Split-Path $logPath -Leaf } else { '(未指定)' }), $logBefore, $logAfter)
Say ("  编译器进程 {0}" -f $(if ($compilers.Count) { (($compilers | ForEach-Object { $_.Name + '(' + $_.ProcessId + ')' }) -join ' ') } else { '无' }))

$filesGrew = ($a2.Count -gt $a1.Count) -or ($a2.Newest -gt $a1.Newest)
$logGrew = ($logAfter -gt $logBefore)
$hasCompiler = ($compilers.Count -gt 0)
if ($ageMin -lt $StuckAfterMinutes) {
    Say ("  判定       ✅ 活跃（还没到 {0} 分钟门槛，本来就该在跑）" -f $StuckAfterMinutes) 'Green'
    exit 0
}
if ($filesGrew -or $logGrew -or $hasCompiler) {
    $why = @()
    if ($filesGrew) { $why += '采样窗口内有文件写入' }
    if ($logGrew) { $why += '日志在增长' }
    if ($hasCompiler) { $why += '有编译器进程在跑' }
    Say ("  判定       ✅ 活跃（{0}）" -f ($why -join '；')) 'Green'
    exit 0
}
Say '  判定       ⚠ 疑似卡住：门槛已过，且采样窗口内【无文件写入 / 无编译器进程 / 日志不增长】' 'Red'
Say '  下一步     ① 看最后写入的是哪个产物/探针 -> 定位卡在哪个条目' 'Yellow'
Say '             ② 若在等锁/等输入/网络：可 job_kill 后重跑（本仓库不联网、构建树可复用）' 'Yellow'
Say '             ③ 把本输出（进程树 + 最后写入时间）附在汇报里，别只说"卡了"' 'Yellow'
exit 1
