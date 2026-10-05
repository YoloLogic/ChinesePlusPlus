# ============================================================================
#  check_zhpaths.ps1 -- §18.26 汉化库【搜索路径】一致性守卫（第 25 道）
#
#  为什么必须有：方案②把汉化库产品按来源分文件夹（标准库 / 别名 / C运行库 / windows系统），
#  用户写法**一个字不变**（`#包含 <向量>`）靠的是"把这些子目录都上 include 搜索路径"。
#  而这条路径列表出现在**很多入口**（生成器、守卫、文档、打包脚本）——
#  **少一条就"某个头找不到"**，正是本项目最怕的"靠人记得"。
#  ⇒ 单一事实来源 = tools\zh_includes.ps1（$ZH_DIRS）；本守卫核对所有入口与它一致。
#
#  判据（每个"提到 isystem 且提到 zhstdlib"的文件，三选一）：
#    · 用了单一事实来源：出现 Get-ZhIncludeArgs / Get-ZhIncludeDirs / zh_includes.ps1 ✓
#    · 或把 5 个目录名（zhstdlib + 4 个来源目录）**都**写全 ✓
#    · 或命中白名单（每条都要写得出理由，不许当垃圾桶用）
#  范围：tools\（含子目录）、packaging\、tests\、examples\、docs\**\*.md
#
#  用法：pwsh -NoProfile -File tools\check_zhpaths.ps1 [-Quiet]
# ============================================================================
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')

$expectNames = @('zhstdlib') + $script:ZhDirs      # zhstdlib / 标准库 / 别名 / C运行库 / windows系统

# 白名单：每条都要有理由（"懒得改"不是理由）
$exempt = @(
    @{ Path = 'tools\zh_includes.ps1';       Why = '单一事实来源本身' },
    @{ Path = 'tools\check_zhpaths.ps1';     Why = '本守卫自己（判据文本里必然出现这些词）' },
    @{ Path = 'tools\library_plan_evidence\'; Why = '大检查时期的一次性证据脚本，不再维护、不进闸门' },
    @{ Path = 'docs\标准库汉化\标准库汉化方案.md'; Why = '见文件里的 §18.26：那段是"历史命令留档"，已在正文标注新写法' }
)

$files = @()
$files += @(Get-ChildItem (Join-Path $root 'tools') -Recurse -File -Include *.ps1, *.md, *.txt, *.json -ErrorAction SilentlyContinue)
foreach ($d in @('packaging', 'tests', 'examples')) {
    $p = Join-Path $root $d
    if (Test-Path $p) { $files += @(Get-ChildItem $p -Recurse -File -Include *.ps1, *.md, *.cmd, *.json, *.txt -ErrorAction SilentlyContinue) }
}
$files += @(Get-ChildItem (Join-Path $root 'docs') -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)

$bad = @(); $checked = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length + 1)
    if (@($exempt | Where-Object { $rel.StartsWith($_.Path) }).Count) { continue }
    $t = [System.IO.File]::ReadAllText($f.FullName)
    if ($t -notmatch 'isystem') { continue }
    if ($t -notmatch 'zhstdlib') { continue }        # 与汉化库无关的 isystem（微软/SDK 的 internal-isystem 等）
    #  ⚠ 判据要分两类文件，否则会假报（实测）：文档里 `-isystem <路径>` 这种**占位符**不带真路径，
    #    不能因为"同一份文档别处提到过 zhstdlib"就判它不一致。
    #    · 脚本（*.ps1/*.cmd）：路径常常通过变量（`-isystem"$out"`，$out=zhstdlib）⇒ 只能按文件判；
    #    · 文档（*.md）：要求**该处 `-isystem` 的参数本身就带 zhstdlib**，才纳入核对。
    if ($f.Extension -eq '.md') {
        if ($t -notmatch '-isystem\s*"?[^"\s]*zhstdlib') { continue }
    }
    $checked++
    if ($t -match 'Get-ZhIncludeArgs|Get-ZhIncludeDirs|zh_includes\.ps1') { continue }
    $missing = @($expectNames | Where-Object { $t -notmatch [regex]::Escape($_) })
    if ($missing.Count) { $bad += ("{0}：缺 {1}" -f $rel, ($missing -join '、')) }
}

# ---------------------------------------------------------------------------
#  §18.30：`<驱动名>.cfg`（"直接使用"用的那份）也是这张路径列表的一个**入口**。
#  它由 tools\make_zhcfg.ps1 从**同一个事实来源**生成 —— 这里直接交给它自己核对：
#  少写一条 = "某个头找不到"；被手改过也要红，否则"直接使用 / IDE 不标红"会悄悄坏掉。
#  编译器还没构建（没有 bin 目录）时跳过：那是"还没生成"，不是"不一致"。
# ---------------------------------------------------------------------------
$binDir = Join-Path $root 'build\Release\bin'
if (Test-Path $binDir) {
    & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhcfg.ps1') -Check -Quiet -BinDir $binDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host '❌ <驱动名>.cfg（§18.30「直接使用」）与搜索路径事实来源不一致' -ForegroundColor Red
        Write-Host '   修法：pwsh -NoProfile -File tools\make_zhcfg.ps1' -ForegroundColor Yellow
        exit 1
    }
    $checked++
}

if ($bad.Count) {
    Write-Host '❌ 汉化库搜索路径不一致（§18.26 方案②）—— 少一条就"某个头找不到"：' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Red }
    Write-Host '   修法：dot-source tools\zh_includes.ps1 后用 Get-ZhIncludeArgs（推荐）；或把 5 个目录名写全。' -ForegroundColor Yellow
    exit 1
}
if (-not $Quiet) { Write-Host ("搜索路径一致性守卫：通过（核对 {0} 个入口，期望 {1} 个目录）" -f $checked, $expectNames.Count) -ForegroundColor Green }
exit 0
