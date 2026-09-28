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
& pwsh -NoProfile -File (Join-Path $root 'tools\regen_zhstdlib.ps1') 2>&1 |
    Tee-Object -FilePath $log | Select-Object -Last 3

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
