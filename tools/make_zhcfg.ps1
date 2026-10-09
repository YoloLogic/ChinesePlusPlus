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
#    pwsh -NoProfile -File tools\make_zhcfg.ps1 -Mode system         # 用机器上的 VS（§18.48 可选项）
#
#  §18.48【两种地基，用户可选，自带为默认】：
#    · bundled（默认）：cfg 里除了 zhstdlib 的 5 条，还写**包内地基目录**（lib\stl 等）⇒
#      **不装 VS 也能用**（头从包里来，不进 `Program Files`）。
#    · system：cfg 只写 zhstdlib 那 5 条，STL/UCRT/Win32 头交给 clang 自己探测到的 VS/SDK ⇒
#      与本项目 0.2 之前的行为逐字一致（最大兼容，但要装 VS）。
#    选了哪个由发行包安装时写进 `<BinDir>\toolchain.txt`；这里 -Check 会读它，保证核对的是**当前模式**。
#
#  单一事实来源：`tools\zh_includes.ps1`（Get-ZhIncludeDirs + §18.48 的 Get-ZhSubstrateDirs）。
# ============================================================================
param(
    [string] $BinDir,
    [string] $ZhRoot,
    [ValidateSet('bundled', 'system')][string] $Mode = 'system',
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

# §18.48：核对时要用**安装时选定的那个模式**（发行包里 install.ps1 写了 bin\toolchain.txt）
if ($Check) {
    $tf = Join-Path $BinDir 'toolchain.txt'
    if (Test-Path $tf) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($tf), 'mode\s*=\s*(\w+)')
        if ($m.Success -and $m.Groups[1].Value -in @('bundled', 'system')) { $Mode = $m.Groups[1].Value }
    }
}

#  §18.48 批2：bundled 模式下**搜索顺序是判据的一部分**，顺序错了就编不过：
#    ① zhstdlib 的中文头（我们自己的产物）；
#    ② **clang 资源目录** —— 必须排在所有地基**之前**：
#       · 它的**转发壳**（limits.h / stdint.h / vadefs.h / float.h / yvals_core.h）要
#         `#include_next` 找到"下一个搜索位置"的真身 —— 那就是我们地基里抄/手搓的那几件；
#       · 它的 **intrinsic 真身**（immintrin.h 等）必须先于 mingw 的同名件出现
#         （批1 实测：被 mingw 抢先时整个 <vector> 编不过）。
#    ③ 地基：STL 抄件 / 手搓件 / mingw 抄件。
#  并且用 **`-nostdinc`** 把 clang 自动塞进来的 VS/SDK 路径**整条去掉** —— 这样"零 VS"是
#  命令行层面的事实（`-v` 里零 `Program Files`），不只是"恰好没用到"。
function Find-ClangResourceDir([string] $Bin) {
    $cands = @(
        (Join-Path (Split-Path $Bin -Parent) 'lib\clang'),
        (Join-Path (Split-Path (Split-Path $Bin -Parent) -Parent) 'lib\clang')
    )
    foreach ($c in $cands) {
        if (-not (Test-Path $c)) { continue }
        $hit = Get-ChildItem $c -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
               ForEach-Object { Join-Path $_.FullName 'include' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

$lines = @()
if ($Mode -eq 'bundled') {
    $resDir = Find-ClangResourceDir $BinDir
    if (-not $resDir) { throw 'bundled 模式找不到 clang 资源头目录（lib\clang\<ver>\include）—— 它是转发壳的兜底，必须有' }
    $lines += '-nostdinc'                      # 去掉 clang 自动加的 VS/SDK 路径（零 VS 的关键）
    #  mingw 的 UCRT 头用 `_UCRT` 决定"暴露 UCRT 那套 API"（实测：不定义时
    #  `quick_exit`/`at_quick_exit` 不声明，MSVC STL 的 <cstdlib> 就编不过）。
    $lines += '-D_UCRT'
}
foreach ($p in (Get-ZhIncludeDirs $ZhRoot)) {
    $lines += '-isystem'
    $lines += ('"' + ($p.Replace('\', '/')) + '"')
}
if ($Mode -eq 'bundled') {
    foreach ($p in (@($resDir) + @(Get-ZhSubstrateDirs $ZhRoot))) {
        $lines += '-isystem'
        $lines += ('"' + ($p.Replace('\', '/')) + '"')
    }
    #  §18.48 批3/批4：链接层。用**我们随包的 lld-link**、**逐个按绝对路径**把我们的 CRT +
    #  导入库交给链接器（实测：只靠 -L/搜索顺序会让 VS 的同名库先被读到 —— 那是"假成功"）。
    #  批4 把 `-nostdlib` 改成四个 /nodefaultlib: —— 实测 `-nostdlib` 会连带掐掉 clang 自动
    #  加的 `-defaultlib:clang_rt.*`，于是 -fsanitize / --coverage 链不上；四个开关只顶掉
    #  Microsoft 的默认库，保留 clang 自己的运行库。`-Wl,` 在 -c 编译时只报一条
    #  unused-command-line-argument 警告，实测不会报错。
    $crtDir = Join-Path $ZhRoot 'lib\crt'
    if (Test-Path $crtDir) {
        $lines += '-fuse-ld=lld'
        foreach ($lib in @('libcmt','oldnames','vcruntime140','vcruntime140_1','msvcp140','ucrt','ucrtbase',
                           'kernel32','user32','gdi32','comctl32','ole32','oleaut32','shell32','advapi32','uuid',
                           'mingwex','mingw32')) {
            $f = Join-Path $crtDir ($lib + '.lib')
            if (Test-Path $f) { $lines += ('-Wl,' + $f.Replace('\', '/')) }
        }
        foreach ($nd in @('libcmt','oldnames','libcpmt','msvcprt')) {
            $lines += ('-Wl,/nodefaultlib:' + $nd)
        }
        #  批4 实测：MSVC 的 <vector>/<string> 在 ASan 下会发 `/DEFAULTLIB:stl_asan`，
        #  链接器就按 clang 给的 -libpath: 去 **VS 安装目录**读它 —— 那是 bundled 地基
        #  唯一漏向 VS 的链接依赖。顶掉它；它里面只有两个注解开关，我们自己在
        #  vendor\crt\asan-annotate.cpp 里发（值 true，与它一致）。
        $lines += '-Wl,/nodefaultlib:stl_asan'
        #  批4 实测的**静态库顺序坑**：我们把 libcmt.lib 写在最前面，而
        #  `??_7type_info@@6B@`（type_info 的 vftable，见 vendor\crt\typeinfo.cpp）
        #  的**引用**来自 clang 自己后加的 clang_rt.* ⇒ 扫到 libcmt.lib 时它还"没有未定义"，
        #  成员就没被拉进来，链接报 undefined symbol。微软的做法是目标文件里写
        #  `/include:` 指令；这里等价地显式加一条：让它在扫任何库之前就是未定义。
        $lines += '-Wl,/include:??_7type_info@@6B@'
    } else {
        Write-Host '  [warn] lib\crt 不在 ⇒ bundled 模式只能编译、不能链接（§18.48 批3）' -ForegroundColor Yellow
    }
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
