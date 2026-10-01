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
  行为：先跑 regen；末尾一行不含「全部通过」就**拒绝提交**并退出 1（工作树不动）。
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
    Write-Host '❌ regen 未全部通过 —— 拒绝提交（工作树保持原样）' -ForegroundColor Red
    Write-Host ("   末尾一行：{0}" -f $tail) -ForegroundColor Red
    Write-Host '   若确实要提交（例如只改文档），请显式说明理由后手工提交。' -ForegroundColor Yellow
    exit 1
}
Write-Host ''
Write-Host '✅ regen 全部通过 —— 允许提交' -ForegroundColor Green
& git -C $root add -A
& git -C $root commit -F $MessageFile
if ($LASTEXITCODE -ne 0) { Write-Host '提交失败（可能没有改动）' -ForegroundColor Yellow; exit 1 }
& git -C $root log --oneline -1
