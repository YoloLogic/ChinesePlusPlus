# ============================================================================
#  给小熊猫C++ 增加/更新一套「中文关键字 clang++」编译器配置
#
#  用法（先关闭小熊猫C++，否则退出时会覆盖）：
#      powershell -File E:\Chinese++\tools\setup_redpanda_clang.ps1
#
#  回退：把 redpandacpp.ini.<时间戳>.bak 覆盖回原文件（脚本会打印确切路径）
#
#  ────────────────────────────────────────────────────────────────────────
#  为什么需要这套配置
#  ────────────────────────────────────────────────────────────────────────
#  1) 小熊猫C++ 自带的 MinGW GCC 不认识中文关键字，所以要换成我们的 clang++。
#
#  2) 它的 MinGW 参数里有三个会让 clang 失败（已逐项实测）：
#       -Wl,--stack,<n>    -> link.exe 报 LNK1181（把数字当成 .obj 输入）
#       -fexec-charset=GBK -> clang 报 invalid value 'GBK'
#       -D_DEBUG           -> 见第 3 条
#     其余（-O2 / -pipe / -s / -static）实测都能吃。
#
#  3) 最阴的一个是它自动加的 -D_DEBUG：
#       _DEBUG 会让 MSVC 的 STL 头文件切到调试版 STL，而调试版 STL 引用调试版
#       C 运行库里的 _CrtDbgReport；clang 在 MSVC 目标下默认链的却是发行版 CRT
#       （libcmt / libucrt），于是链接期报：
#           示例.o : error LNK2019: 无法解析的外部符号 _CrtDbgReport
#           示例.exe : fatal error LNK1120: 1 个无法解析的外部命令
#           clang++: error: linker command failed with exit code 1120
#
#       CLion 之所以没事，是因为 CMake 会同时传 -D_DEBUG -D_DLL -D_MT
#       -Xclang --dependent-lib=msvcrtd，把调试版 CRT 一起链进去；Dev-C++
#       只抄了 -D_DEBUG，没抄 CRT 选择，所以对不上。
#
#       -D_DEBUG 被 Dev-C++ 追加在自定义参数【之后】，-U_DEBUG 压不住它。
#       但 -include 的文件是在「命令行宏处理完之后、源文件内容之前」展开的，
#       所以用 tools/undef_debug.h 在里面 #undef _DEBUG 就能解决。
#       实测：同一命令行加不加这个 -include，退出码正好是 1120 与 0。
#
#  注意：不动原有的 MinGW 两套配置，只维护新增的这一套。
#        写普通英文 C++ 时，在工具栏下拉框切回 MinGW 即可。
# ============================================================================

$ErrorActionPreference = 'Stop'

$Ini       = Join-Path $env:APPDATA 'RedPandaIDE\redpandacpp.ini'
$BackupDst = 'E:\Chinese++\backup'
$ClangDir  = 'E:/Chinese++/build/Release/bin'
$ShimDef   = 'E:/Chinese++/tools/undef_debug.h'

Write-Output "配置文件: $Ini"
if (-not (Test-Path $Ini)) { Write-Output "找不到配置文件，先运行一次小熊猫C++ 再试。"; exit 1 }

# --- 0. 前置检查 ----------------------------------------------------------
$proc = Get-Process -Name RedPandaIDE -ErrorAction SilentlyContinue
if ($proc) {
    Write-Output "!! 小熊猫C++ 正在运行（PID $($proc.Id -join ',')），请先关闭它，否则修改会被覆盖。"
    exit 2
}
if (-not (Test-Path ($ShimDef -replace '/', '\'))) {
    Write-Output "!! 找不到 $ShimDef，它用来抵消 Dev-C++ 自动加的 -D_DEBUG，必须先有它。"
    exit 3
}

# --- 1. 备份（就地一份 + 工作区一份） ------------------------------------
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$BakSame = "$Ini.$stamp.bak"
New-Item -ItemType Directory -Force -Path $BackupDst | Out-Null
$BakWs   = Join-Path $BackupDst "redpandacpp.ini.$stamp.bak"
Copy-Item $Ini $BakSame -Force
Copy-Item $Ini $BakWs   -Force
Write-Output "备份1: $BakSame"
Write-Output "备份2: $BakWs"

# --- 2. 读入并保留原有换行风格 -------------------------------------------
$text = [System.IO.File]::ReadAllText($Ini, [System.Text.Encoding]::UTF8)
$nl   = if ($text -match "`r`n") { "`r`n" } else { "`n" }
Write-Output ("换行风格: " + $(if ($nl -eq "`r`n") { 'CRLF' } else { 'LF' }))

# --- 3. 如果已有我们那套，先整体删掉（保证重复运行不会叠加） --------------
if ($text -match '(?m)^\[CompilerSet_2\]') {
    $text = [regex]::Replace($text, "(?s)\[CompilerSet_2\].*?(?=\r?\n\[)", '')
    Write-Output "检测到旧的 [CompilerSet_2]，已移除，稍后重建。"
}

# --- 4. 组装编译器配置集 --------------------------------------------------
# Name 里的中文按 QSettings 的写法转义成 \xXXXX（该文件本身就这么存中文，
# 例如 C=E:/\x6c49\x8bed\x7f16\x7a0b/... 就是「E:/汉语编程/...」）
$extra = "-std=c++20 -include $ShimDef"
$lines = @(
    '[CompilerSet_2]'
    "ccompiler=$ClangDir/clang.exe"
    "cppcompiler=$ClangDir/clang++.exe"
    'debugger=E:/c++/mingw64/bin/gdb.exe'
    'debug_server=E:/c++/mingw64/bin/gdbserver.exe'
    'make=E:/c++/mingw64/bin/mingw32-make.exe'
    'windres=E:/c++/mingw64/bin/windres.exe'
    'cc_cmd_opt_debug_info=on'
    'cc_cmd_opt_warning_all=on'
    'link_cmd_opt_stack_size=0'
    'useCustomCompileParams=true'
    "customCompileParams=$extra"
    'useCustomLinkParams=false'
    'customLinkParams='
    'AddCharset=false'
    'StaticLink=false'
    'ExecCharset=UTF-8'
    'PersistInAutoFind=false'
    'forceEnglishOutput=false'
    'preprocessingSuffix=p'
    'compilationProperSuffix=s'
    'assemblingSuffix=o'
    'executableSuffix=exe'
    'DumpMachine=x86_64-pc-windows-msvc'
    'Version=24.0.0'
    'Name=\x4e2d\x6587\x5173\x952e\x5b57 clang++ 24'
    'Target=x86_64'
    'CompilerType=0'
    "Bins=$ClangDir, E:/c++/mingw64/bin"
    'C=@Invalid()'
    'Cpp=@Invalid()'
    'Libs=@Invalid()'
)
$block = ($lines -join $nl) + $nl

# --- 5. 插入 + 保证计数与默认项 -------------------------------------------
if ($text -notmatch '(?m)^\[CompilerSets\]') {
    Write-Output "!! 配置文件里没有 [CompilerSets] 段，格式可能不对，已中止（备份已生成）。"
    exit 4
}
$text = $text -replace '(?m)^\[CompilerSets\]', ($block + $nl + '[CompilerSets]')
$text = $text -replace '(?m)^count=\d+(\s*)$',        'count=3$1'
$text = $text -replace '(?m)^defaultIndex=\d+(\s*)$', 'defaultIndex=2$1'

[System.IO.File]::WriteAllText($Ini, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Output ""
Write-Output "已写入 [CompilerSet_2]（下拉框显示为「中文关键字 clang++ 24」，且已设为当前配置）"
Write-Output "自定义编译参数: $extra"
Write-Output ""
Write-Output "现在打开小熊猫C++，打开 E:\Chinese++\examples\expr_calc.cpp 按 F11 即可。"
Write-Output ""
Write-Output "回退命令（如需）："
Write-Output "    Copy-Item '$BakSame' '$Ini' -Force"
