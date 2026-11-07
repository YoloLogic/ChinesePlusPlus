# ============================================================================
#  推送wiki.ps1 —— 把本目录的 .md 推到 GitHub Wiki
#
#  为什么需要脚本：
#    GitHub 的 wiki 仓库（<repo>.wiki.git）**只有在网页上创建第一页之后才存在**，
#    在那之前 git push 会报 "Repository not found"（试过，不是网络问题）。
#    所以：先在网页点一次「Create the first page」，之后本脚本就能一条命令同步全部页面。
#
#  用法：
#    pwsh -File 推送wiki.ps1                    # 默认推 YoloLogic/ChinesePlusPlus
#    pwsh -File 推送wiki.ps1 -仓库 YoloLogic/CDZC
# ============================================================================
param(
    [string]$仓库 = 'YoloLogic/ChinesePlusPlus',
    [string]$消息 = '更新 wiki 页面'
)

$ErrorActionPreference = 'Stop'
$本目录 = $PSScriptRoot
$wikiUrl = "https://github.com/$仓库.wiki.git"

Write-Host ('目标 wiki：' + $wikiUrl)

# 先看 wiki 仓库存不存在
$ls = & git ls-remote $wikiUrl 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '⚠ wiki 仓库还不存在。GitHub 的规则是：' -ForegroundColor Yellow
    Write-Host '  必须在网页上创建**第一页**之后，wiki 的 git 仓库才会被建出来。' -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('  1) 打开 https://github.com/' + $仓库 + '/wiki') -ForegroundColor Cyan
    Write-Host '  2) 点右上角的 “Create the first page”' -ForegroundColor Cyan
    Write-Host '  3) 标题随便写（例如 Home），正文随便写一个字，Save' -ForegroundColor Cyan
    Write-Host '  4) 回来重跑本脚本' -ForegroundColor Cyan
    Write-Host ''
    Write-Host ('  也可以改用仓库内文档：https://github.com/' + $仓库 + '/tree/main/wiki')
    exit 2
}

$临时 = Join-Path $env:TEMP ('cdzc-wiki-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
& git clone --depth 1 $wikiUrl $临时 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Host ('  ' + $_) }

$页面 = Get-ChildItem $本目录 -File -Filter '*.md'
foreach ($p in $页面) {
    Copy-Item $p.FullName (Join-Path $临时 $p.Name) -Force
}
# wiki 侧的统一入口：Home.md 就是首页
Write-Host ('  同步 {0} 个页面：{1}' -f $页面.Count, (($页面 | ForEach-Object { $_.BaseName }) -join '、'))

Push-Location $临时
try {
    & git add -A
    & git -c user.name='YoloLogic' -c user.email='yolologic@users.noreply.github.com' commit -m $消息 2>&1 | Select-Object -First 2 | ForEach-Object { Write-Host ('  ' + $_) }
    & git push 2>&1 | Select-Object -Last 2 | ForEach-Object { Write-Host ('  ' + $_) }
    Write-Host ''
    Write-Host ('✓ 已推送：https://github.com/' + $仓库 + '/wiki') -ForegroundColor Green
} finally {
    Pop-Location
    Remove-Item $临时 -Recurse -Force -ErrorAction SilentlyContinue
}