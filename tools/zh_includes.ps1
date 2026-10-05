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

$script:ZhRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# 各来源目录（顺序即搜索顺序；中文名全局唯一由第 10 道守卫保证 ⇒ 不会出现同名歧义）
$script:ZhDirs = @('标准库', '别名', 'C运行库', 'windows系统')

function Get-ZhIncludeDirs {
    <#  返回**实际存在的**搜索目录（含根），给需要逐个处理路径的地方用 #>
    param([string] $Root = $script:ZhRoot)
    $list = @((Join-Path $Root 'zhstdlib'))
    foreach ($d in $script:ZhDirs) { $list += (Join-Path (Join-Path $Root 'zhstdlib') $d) }
    return $list
}

function Get-ZhIncludeArgs {
    <#  返回拼好的 `-isystem"…"` 参数串（给 cmd /c 的命令行用）#>
    param([string] $Root = $script:ZhRoot)
    $args = @()
    foreach ($p in (Get-ZhIncludeDirs $Root)) { $args += "-isystem`"$p`"" }
    return ($args -join ' ')
}

function Get-ZhProductDirs {
    <#  只返回**产品所在**的子目录（根目录在迁移完成后不再放产品）—— 扫描产物时用 #>
    param([string] $Root = $script:ZhRoot)
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
    param([Parameter(Mandatory = $true)][string] $Name, [string] $Root = $script:ZhRoot)
    foreach ($d in (@((Join-Path $Root 'zhstdlib')) + (Get-ZhProductDirs $Root))) {
        $p = Join-Path $d $Name
        if ([System.IO.File]::Exists($p)) { return $p }
    }
    return $null
}
