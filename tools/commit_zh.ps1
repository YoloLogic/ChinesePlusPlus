<#
  commit_zh.ps1 —— **由 regen 结果把关的提交**（§17.16）

  为什么要有这个脚本（一次真实失误）：
    第 139 轮我把 `git commit` 直接串在命令链末尾，**没看 regen 的退出码**。
    regen 的输出其实是「重新生成失败 0 个；**全量验证退出码 1**；…」，
    而我只看到"重新生成失败 0 个"就以为绿了 —— 于是把一个**调试配置探针 FAIL**
    的状态提交了上去，随后只能 `git revert`。

  判据（写进方案 §17.16）：
    **"重新生成 0 失败" ≠ 全绿。** 允许提交的唯一证据是 regen 末尾那句
        `重新生成 + 全量验证 + 真实用例 + 用法对照表 + 铁律①：全部通过`
    把"检查"和"动作"写在同一条命令链里、却不读结果，等于把提交交给运气。

  用法：
      pwsh -File tools\commit_zh.ps1 -MessageFile .git\ZH_MSG.txt
  行为：先跑 regen；末尾一行不含「全部通过」就**拒绝提交**并退出 1。

  §18.11 补的（"闸门拒绝提交 ≠ 工作树完好"）：拒绝提交时**不再只是"不 add / 不 commit"** ——
    P-12 那次实测，拒绝提交之后**生成器已经把产物改坏了**留在工作树里
    （`zhstdlib` 两个文件与 HEAD 不同、内容编不过），靠人手工 `git checkout -- zhstdlib` 恢复。
    "靠人记得"正是本项目一直在消灭的东西 ⇒ 现在拒绝提交时会：
      ① 比 regen 前后两份 `git status --porcelain`，取**本次 regen 新弄脏的**路径
         （**用户原本就未提交的改动一律不碰**）；
      ② 把这些文件的当前内容先**留档**到 `build\_review_own\regen_failed_<时间戳>\`；
      ③ 再 `git checkout --` 把它们**恢复成 HEAD 的样子**（未跟踪的新文件只报告、不删）。
    要临时关掉：设 `ZH_NO_REGEN_ROLLBACK=1`。
#>
param([Parameter(Mandatory = $true)][string] $MessageFile)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$log  = Join-Path $root 'build\commit_zh.log'

Write-Host '=== 提交前跑全量 regen（结果把关）===' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
#  §17.34 长任务看门狗：regen 全量常跑 25–45 分钟 —— **超过 25 分钟必须有「卡没卡」的证据**。
#  为什么（2026-10-01 实测误判）：我只看了 `third_party\`（那里早跑完了）就说"卡了"，
#  其实闸门正在实例化守卫里编探针（写的是 `build\_zhinst`）。教训：**「某处没动静」≠「卡住」**，
#  判定必须看**多个活动源 + 进程树 + 采样 delta**，这正是 tools\check_stuck.ps1 干的事。
#  ⚠ 监测器**绝不影响判定**：起不来 / 报错都只打一行提示，不改 $tail、不参与"全部通过"。
#    要关掉：设环境变量 ZH_NO_WATCHDOG=1。
# ---------------------------------------------------------------------------
$wdLog = Join-Path $root 'build\_review_own\watchdog.log'
$wdJob = $null
if ($env:ZH_NO_WATCHDOG -ne '1') {
    try {
        $wdJob = Start-Job -ScriptBlock {
            param($script, $out)
            while ($true) {
                Start-Sleep -Seconds 300
                $v = & pwsh -NoProfile -File $script -RootPattern 'regen_zhstdlib' -SampleSeconds 10 2>&1 | Out-String
                $verdict = if ($LASTEXITCODE -eq 1) { '疑似卡住' } elseif ($LASTEXITCODE -eq 2) { '任务已结束' } else { '活跃' }
                Add-Content -Path $out -Value ("[{0}] 看门狗：{1}" -f (Get-Date).ToString('HH:mm:ss'), $verdict)
                if ($LASTEXITCODE -eq 1) { Add-Content -Path $out -Value $v }
            }
        } -ArgumentList (Join-Path $root 'tools\check_stuck.ps1'), $wdLog
        Write-Host ("  （§17.34 看门狗已随行：每 5 分钟判一次「卡没卡」，结论写 {0}）" -f 'build\_review_own\watchdog.log') -ForegroundColor DarkGray
    } catch {
        Write-Host ('  ⚠ 看门狗没起来（不影响判定）：' + $_.Exception.Message) -ForegroundColor Yellow
        $wdJob = $null
    }
}

# ---------------------------------------------------------------------------
#  §18.11 拒绝提交时的"工作树完好"保证：先记下此刻的脏清单，
#  regen 之后再取一次，差集就是**本次 regen 新弄脏的**（用户原本的改动不在里面）。
# ---------------------------------------------------------------------------
function Get-DirtyMap {
    $m = @{}
    foreach ($l in @(& git -C $root status --porcelain 2>$null)) {
        if ($l.Length -lt 4) { continue }
        $st = $l.Substring(0, 2)
        $p  = $l.Substring(3).Trim()
        if ($p -match ' -> ') { $p = ($p -split ' -> ')[-1] }
        $p = $p.Trim('"')
        if ($p -ne '') { $m[$p] = $st }
    }
    return $m
}
$脏之前 = Get-DirtyMap

& pwsh -NoProfile -File (Join-Path $root 'tools\regen_zhstdlib.ps1') 2>&1 |
    Tee-Object -FilePath $log | Select-Object -Last 3

if ($wdJob) {
    try {
        Stop-Job $wdJob -ErrorAction SilentlyContinue
        Remove-Job $wdJob -Force -ErrorAction SilentlyContinue
        if (Test-Path $wdLog) {
            $verdicts = @(Get-Content $wdLog -ErrorAction SilentlyContinue | Where-Object { $_ -match '看门狗' })
            if ($verdicts.Count) { Write-Host ('  §17.34 看门狗全程结论：' + (($verdicts | Select-Object -Last 4) -join ' | ')) -ForegroundColor DarkGray }
            else { Write-Host '  §17.34 看门狗：本次 regen 不到 5 分钟就结束了（无需判定）' -ForegroundColor DarkGray }
        }
    } catch { }
}

$tail = [string](Get-Content $log -Tail 1)
if ($tail -notmatch '全部通过') {
    Write-Host ''
    Write-Host '❌ regen 未全部通过 —— 拒绝提交' -ForegroundColor Red
    Write-Host ("   末尾一行：{0}" -f $tail) -ForegroundColor Red

    # §18.11：把**本次 regen 新弄脏的**东西留档 + 恢复（用户原本的改动不碰）
    $脏之后 = Get-DirtyMap
    $新增 = @($脏之后.Keys | Where-Object { -not $脏之前.ContainsKey($_) })
    $可恢复 = @($新增 | Where-Object { $脏之后[$_] -notmatch '\?\?' })
    $新文件 = @($新增 | Where-Object { $脏之后[$_] -match '\?\?' })
    if ($env:ZH_NO_REGEN_ROLLBACK -eq '1') {
        Write-Host '   （ZH_NO_REGEN_ROLLBACK=1：不做自动恢复，工作树保持原样）' -ForegroundColor Yellow
    } elseif ($新增.Count -eq 0) {
        Write-Host '   ✅ 工作树与 regen 前一致（本次 regen 没有留下任何改动）' -ForegroundColor Green
    } else {
        $存 = Join-Path $root ('build\_review_own\regen_failed_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-Item -ItemType Directory -Force $存 | Out-Null
        foreach ($p in $新增) {
            $src = Join-Path $root $p
            if (Test-Path $src -PathType Leaf) {
                $dst = Join-Path $存 $p
                New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
                Copy-Item $src $dst -Force
            }
        }
        if ($可恢复.Count -gt 0) {
            & git -C $root checkout -- @可恢复 2>&1 | Out-Null
            Write-Host ("   ↩ 已把本次 regen 弄脏的 {0} 个**已跟踪**文件恢复成 HEAD 的样子（坏内容留档在 {1}）" -f $可恢复.Count, ($存.Replace($root + '\', ''))) -ForegroundColor Yellow
            $可恢复 | Select-Object -First 8 | ForEach-Object { Write-Host ("        " + $_) -ForegroundColor DarkYellow }
            if ($可恢复.Count -gt 8) { Write-Host ("        …（共 {0} 个）" -f $可恢复.Count) -ForegroundColor DarkYellow }
        }
        if ($新文件.Count -gt 0) {
            Write-Host ("   ⚠ 另有 {0} 个**未跟踪**的新文件留着没删（自己看一眼要不要留）：" -f $新文件.Count) -ForegroundColor Yellow
            $新文件 | Select-Object -First 8 | ForEach-Object { Write-Host ("        " + $_) -ForegroundColor DarkYellow }
        }
        $复核 = @((Get-DirtyMap).Keys | Where-Object { -not $脏之前.ContainsKey($_) })
        if ($复核.Count -eq 0) { Write-Host '   ✅ 复核：现在的工作树 == regen 之前的状态' -ForegroundColor Green }
        else { Write-Host ("   ⚠ 复核：还剩 {0} 个（未跟踪文件，见上）" -f $复核.Count) -ForegroundColor Yellow }
    }

    Write-Host '   若确实要提交（例如只改文档），请显式说明理由后手工提交。' -ForegroundColor Yellow
    exit 1
}
Write-Host ''
Write-Host '✅ regen 全部通过 —— 允许提交' -ForegroundColor Green
& git -C $root add -A
& git -C $root commit -F $MessageFile
if ($LASTEXITCODE -ne 0) { Write-Host '提交失败（可能没有改动）' -ForegroundColor Yellow; exit 1 }
& git -C $root log --oneline -1
