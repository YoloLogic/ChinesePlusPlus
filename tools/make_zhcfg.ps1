# ============================================================================
#  make_zhcfg.ps1 -- 让「只敲 chinese++ 文件.cpp」真的成立：生成 <驱动名>.cfg
#
#  为什么需要它（§18.30，2026-10-05 实测）：
#    汉化库产品按来源分文件夹（标准库 / 别名 / C运行库 / windows系统）之后，用户写法没变
#    （`#包含 <向量>`），靠的是"把这些目录都上 include 搜索路径"。但那条列表以前只出现在
#    **每个入口自己拼**的地方（生成器、守卫、文档命令）——于是有两处实测的窟窿：
#      ① 命令行 / VS Code 任务：裸驱动 `chinese++.exe -std=c++20 x.cpp` 报
#         「找不到文件（名字）'向量'」，用户必须自己记得 5 条 -isystem（正是本项目最怕的"靠人记得"）；
#      ② IDE：clangd 走 `--query-driver` 问编译器要搜索路径，拿到的也是"没有 zhstdlib"那份
#         ⇒ 实测 `clangd --check` 报 `pp_file_not_found: 找不到文件（名字）'向量'`
#         —— **代码是对的，编辑器里却是红的**。
#    修法**不用重编编译器**：clang 会自动读**与驱动同目录、同调用名**的 `<驱动名>.cfg`。
#    实测：放 `chinese++.cfg` 则 `chinese++.exe` 读它；放 `clang.cfg` 则 `chinese++.exe` **不读**；
#    放 `clang++.cfg` 则 `clang++.exe` 读它。⇒ 一处生成，命令行 / IDE / 任务 / CMake 全部跟着对。
#
#  ⚠ 三条实测坑（写错任何一条都会"看起来配了、其实没生效"）：
#    · cfg 里 `\` 是**转义符** ⇒ 路径必须写正斜杠（`E:\A\B` 被吃成 `E:A B`，`-###` 里可见）；
#    · cfg **按空白拆** ⇒ 路径含空格必须加引号（发行包可能被解压到 `C:\Program Files\…`）；
#    · **相对路径按"当前工作目录"解析**（反向判别实测：cfg 写 `cfgtest3/../inc`，
#      CWD=上一层时编得过 ⇒ 基准是 CWD，不是 cfg 所在目录）⇒ 只能用绝对路径。
#      代价与 `.vscode`/`env.cmd` 那套一致：**移动目录后重跑本脚本**。
#
#  用法：
#    pwsh -NoProfile -File tools\make_zhcfg.ps1                      # 写 <仓库>\build\Release\bin
#    pwsh -NoProfile -File tools\make_zhcfg.ps1 -Check               # 只核对（红了=过期或被手改）
#    pwsh -NoProfile -File tools\make_zhcfg.ps1 -BinDir <目录> -ZhRoot <目录>   # 发行包安装时用
#
#  单一事实来源：`tools\zh_includes.ps1` 的 Get-ZhIncludeDirs（第 25 道守卫连带管这里）。
# ============================================================================
param(
    [string] $BinDir,
    [string] $ZhRoot,
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
. (Join-Path $root 'tools\zh_includes.ps1')

if (-not $ZhRoot) { $ZhRoot = $root }
if (-not $BinDir) { $BinDir = Join-Path $root 'build\Release\bin' }
if (-not (Test-Path $BinDir)) { throw "没有这个目录：$BinDir（先构建编译器，或显式给 -BinDir）" }

# BOM-less UTF-8：带 BOM 会吃掉第一行（实测）
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 驱动名 -> cfg 名。三条都要写：
#   · `chinese++.cfg` —— 用户/任务/CMake 用 `chinese++.exe` 时；
#   · `clang++.cfg`   —— 用 `clang++.exe`（同一文件的硬链接）时；
#   · `clang.cfg`     —— **IDE 必需**：实测 clangd 的"回退命令"用的是它自己旁边的 `clang`
#       （`--check` 日志：Generic fallback command is: [...\bin\clang -std=c++20 …]），
#       而 clangd 的路径提取只对**匹配 `--query-driver` 的那个驱动**生效 ⇒ 只写 chinese++.cfg
#       时，IDE 里 `#包含 <向量>` **照样红**（实测 pp_file_not_found 依旧）。
#       代价：C 模式也会多这 5 条搜索路径（产品都是 C++ 的，C 里引到只会报"这是 C++ 的"）——
#       换来的是"编辑器不再是红的"，值。
$names = @('chinese++.cfg', 'clang++.cfg', 'clang.cfg')

$lines = @()
foreach ($p in (Get-ZhIncludeDirs $ZhRoot)) {
    $lines += '-isystem'
    $lines += ('"' + ($p.Replace('\', '/')) + '"')
}
$text = ($lines -join "`n") + "`n"

$bad = @(); $checked = 0
foreach ($n in $names) {
    $f = Join-Path $BinDir $n
    if ($Check) {
        $checked++
        if (-not (Test-Path $f)) { $bad += ($n + '：不存在'); continue }
        if ([System.IO.File]::ReadAllText($f) -ne $text) {
            $bad += ($n + '：内容与 tools\zh_includes.ps1 不一致（少一条搜索路径就「某个头找不到」）')
        }
    } else {
        [System.IO.File]::WriteAllText($f, $text, $utf8)
    }
}

if ($Check) {
    if ($bad.Count) {
        Write-Host '❌ 编译器的 <驱动名>.cfg 过期或与事实来源不一致（§18.30）：' -ForegroundColor Red
        $bad | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Red }
        Write-Host '   修法：pwsh -NoProfile -File tools\make_zhcfg.ps1（重写）' -ForegroundColor Yellow
        exit 1
    }
    if (-not $Quiet) { Write-Host ("直接使用配置：通过（{0} 个 cfg == 搜索路径单一事实来源）" -f $checked) -ForegroundColor Green }
    exit 0
}
if (-not $Quiet) { Write-Host ("直接使用配置：写好 {0} 个（{1}）" -f $names.Count, $BinDir) -ForegroundColor Green }
exit 0
