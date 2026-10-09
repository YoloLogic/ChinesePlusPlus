# ============================================================================
#  zh_includes.ps1 -- 汉化库【搜索路径】的单一事实来源（方案 ②，§18.26）
#
#  为什么要有这一份：
#    §18.26 起，zhstdlib\ 里的产品**按来源分文件夹**（标准库 / 别名 / C运行库 / windows系统）——
#    这是"用文件夹分类，不然无法管理"的直接落实。用户写法**一个字不变**（`#包含 <向量>`），
#    靠的是把这些子目录**都**加进 include 搜索路径（方案 ②）。
#    代价：这条路径列表出现在很多入口（生成器、守卫、文档、打包脚本、clangd 配置），
#    **少一条就"某个头找不到"** —— 而这正是本项目最怕的"靠人记得"。
#    ⇒ 所以路径列表只写在这一个文件里，PowerShell 侧一律 dot-source 本文件；
#      tools\check_zhpaths.ps1（第 25 道守卫）负责核对所有入口与这里一致。
#
#  用法：
#      . (Join-Path $root 'tools\zh_includes.ps1')
#      $zhInc = Get-ZhIncludeArgs $root          # 形如 -isystem"…\zhstdlib" -isystem"…\zhstdlib\标准库" …
#      & cmd /c "`"$cxx`" -std=c++20 $zhInc -fsyntax-only `"$src`""
#
#  ⚠ 根目录 `zhstdlib` 也留在列表里：迁移过程中产品还在旧位置时照样能编；
#    迁移完成后它是"顶层没有产品"的空壳，留着无害（将来顶层若再放产品也不必修列表）。
#  ⚠ `_来源\` **不在**列表里 —— 它放复制体/来源清单，不参与 include，
#    这样它天然不会 shadow 微软真头（`#include <winuser.h>` 命不中它）。
# ============================================================================

$script:ZhIncludeRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# 各来源目录（顺序即搜索顺序；中文名全局唯一由第 10 道守卫保证 ⇒ 不会出现同名歧义）
#
#  ⚠ ASCII NOTE（2026-10-06 实测，§18.48）：这 4 个目录名**用码点拼**，不在这里直接写汉字。
#    原因：本文件会随发行包一起发出去，由 **Windows PowerShell 5.1** 运行；
#    PS 5.1 读**无 BOM** 的文件时按 **ANSI 代码页**解码 —— 默认中文 Windows 是 GBK(936)，
#    于是直接写的汉字会变成乱码（实测：`标准库` → `鏍囧噯搴?`），
#    `<驱动名>.cfg` 就会指向**不存在的目录**、`#包含 <向量>` 当场失效。
#    （开发机若开了"UTF-8 全球语言支持"(ACP=65001) 则看不出问题 —— 所以必须用码点，
#      而不是"我这台机器上能跑"。码点写法的源码是纯 ASCII，任何代码页下都解出同一串汉字。）
$script:ZhDirs = @(
    (-join @([char]0x6807, [char]0x51C6, [char]0x5E93)),          # 标准库
    (-join @([char]0x522B, [char]0x540D)),                        # 别名
    ('C' + (-join @([char]0x8FD0, [char]0x884C, [char]0x5E93))),  # C运行库
    ('windows' + (-join @([char]0x7CFB, [char]0x7EDF)))           # windows系统
)

# ---------------------------------------------------------------------------
#  【地基目录】（§18.48「把 VS 那层搬进来」批1）—— 与 $ZhDirs **必须分开**：
#    $ZhDirs 回答的是"**我们的产物**放在 zhstdlib 的哪个子目录"，10 个守卫拿它枚举产物
#    （`Get-ChildItem (Get-ZhIncludeDirs $root) -File`）；地基目录里是**抄来的/手搓的**东西，
#    混进去会让"产物数/名字数"当场变错。所以单列一份，只在**拼 include 搜索路径**时追加。
#    仓库里叫 vendor\msvc-stl，发行包里叫 lib\stl（打包时复制并按包内布局取名）。
#    lib\ucrt / lib\win32 / lib\compiler 是批2 的位置（UCRT 头 / Win32 头 / 手搓的编译器支撑头）。
# ---------------------------------------------------------------------------
$script:ZhSubstrateCandidates = @(
    'vendor\compiler-support', 'lib\compiler',   # §18.48 批2 手搓：vcruntime*.h 等编译器支撑头
    'vendor\msvc-stl',         'lib\stl',        # §18.48 批1 抄：开源 MSVC STL 头
    'vendor\mingw',            'lib\mingw',      # §18.48 批2 抄：mingw-w64 的 UCRT + Win32 头（public domain）
    'lib\ucrt',                'lib\win32'       # 预留：将来若按层拆包
)

function Get-ZhSubstrateDirs {
    <#  返回**实际存在的**地基目录（仓库布局或发行包布局都认） #>
    param([string] $Root = $script:ZhIncludeRoot)
    $list = @()
    foreach ($d in $script:ZhSubstrateCandidates) {
        $p = Join-Path $Root $d
        if (Test-Path $p) { $list += $p }
    }
    return $list
}

function Get-ZhIncludeDirs {
    <#  返回**实际存在的**搜索目录（含根），给需要逐个处理路径的地方用 #>
    param([string] $Root = $script:ZhIncludeRoot)
    $list = @((Join-Path $Root 'zhstdlib'))
    foreach ($d in $script:ZhDirs) { $list += (Join-Path (Join-Path $Root 'zhstdlib') $d) }
    return $list
}

function Get-ZhIncludeArgs {
    <#  返回拼好的 `-isystem"…"` 参数串（给 cmd /c 的命令行用）
        §18.48：**只返回 zhstdlib 的目录** —— 地基目录（vendor\msvc-stl / vendor\mingw / …）
        只由 `make_zhcfg.ps1` 写进 `<驱动名>.cfg`（发行包用，bundled 模式）。
        为什么不在守卫里也带上地基：守卫/生成器的编译是"仓库自检"，地基还没搬完之前带上它
        会把仓库自检搞红（实测：文档代码块守卫因为地基里 `_Mbstatet`/intrinsic 的未解交互而失败）。
        等批2/批3 全绿再考虑在开发树也默认走地基。 #>
    param([string] $Root = $script:ZhIncludeRoot)
    $args = @()
    foreach ($p in (Get-ZhIncludeDirs $Root)) { $args += "-isystem`"$p`"" }
    return ($args -join ' ')
}

function Get-ZhProductDirs {
    <#  只返回**产品所在**的子目录（根目录在迁移完成后不再放产品）—— 扫描产物时用 #>
    param([string] $Root = $script:ZhIncludeRoot)
    $list = @()
    foreach ($d in $script:ZhDirs) { $list += (Join-Path (Join-Path $Root 'zhstdlib') $d) }
    return $list
}

function Find-ZhProduct {
    <#  按【产物名】在根与各来源目录里找它（迁移期间旧位置还在也能找到）—— 生成器内部互引时用
        ⚠ 必须用 [System.IO.File]::Exists 而不是 Test-Path：
          Windows 路径**大小写不敏感**，产物 `Windows系统` 与来源目录 `windows系统` 在根目录下
          是"同一个名字"⇒ `Test-Path 'zhstdlib\Windows系统'` 命中的是**目录**，
          于是本函数会把目录当产物文件返回，调用方 ReadAllText(目录) 报「Access denied」（实测踩过）。 #>
    param([Parameter(Mandatory = $true)][string] $Name, [string] $Root = $script:ZhIncludeRoot)
    foreach ($d in (@((Join-Path $Root 'zhstdlib')) + (Get-ZhProductDirs $Root))) {
        $p = Join-Path $d $Name
        if ([System.IO.File]::Exists($p)) { return $p }
    }
    return $null
}
