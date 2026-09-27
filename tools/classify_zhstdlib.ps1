# 阶段 1b：给 112 个公开头分类 —— 决定哪些"抄一份"、哪些只能"别名"
#
# 分类规则（机械、可复核）：
#   甲 C 包装头   : 有同名 .h 对件（cstddef -> stddef.h）。它自己没有实现，
#                   只是把 C 库名字搬进 std。**只能别名，不能抄**（铁律 4）。
#   乙 C++ 库头   : 有自己的实现（在 _STD_BEGIN 块里定义类），**抄一份 + 派生**。
#   丙 工具/转发头: 没有 _STD_BEGIN（纯转发，一行自己的东西都没有）
#                   或 只有模板/宏、不定义实体类 —— **待定，逐个看**。
$ErrorActionPreference = 'Stop'
$vsInc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$out   = 'E:\Chinese++\build\_zhstdlib_classify.md'

$headers = Get-ChildItem $vsInc -File |
           Where-Object { $_.Extension -eq '' -and $_.Name -notmatch '^x' } |
           Select-Object -ExpandProperty Name | Sort-Object

# C++ 标准规定的 26 个 "C 包装头"（[support] / [depr.c.headers]）。
# 用固定清单，不用"同名 .h 对件"猜 —— 那条规则不可靠：stddef.h 不在 MSVC 目录里
# （clang 自带一份），于是 cstddef 被误判。
$cWrappers = @('cassert','ccomplex','cctype','cerrno','cfenv','cfloat','cinttypes',
               'ciso646','climits','clocale','cmath','csetjmp','csignal','cstdalign',
               'cstdarg','cstdbool','cstddef','cstdint','cstdio','cstdlib','cstring',
               'ctgmath','ctime','cuchar','cwchar','cwctype')

$rows = @()
foreach ($h in $headers) {
    $text  = [System.IO.File]::ReadAllText((Join-Path $vsInc $h))
    $lines = ([System.IO.File]::ReadAllLines((Join-Path $vsInc $h))).Count

    $stdBegin = ([regex]::Matches($text, '_STD_BEGIN')).Count
    # ⚠ 正则必须容许前缀（_EXPORT_STD 等）。第一版写成 ^\s*(class|struct)，
    #   于是 `_EXPORT_STD class latch {` 这种被漏掉，把乙类误判成丁类。
    $classes  = ([regex]::Matches($text, '(?m)^\s*(?:_EXPORT_STD\s+|_CRTIMP2_PURE\s+)?(?:class|struct)\s+[A-Za-z_]')).Count
    $uses     = ([regex]::Matches($text, '(?m)^\s*using\s')).Count
    $incX     = ([regex]::Matches($text, '#include\s*<x[A-Za-z0-9_]*>')).Count
    $sib = ''

    $cat = if ($cWrappers -contains $h) { '甲 C包装头' }
           elseif ($classes -gt 0)      { '乙 自含实现' }
           else                          { '丁 薄壳（实体在内部头）' }

    $rows += [pscustomobject]@{
        Header = $h; Cat = $cat; Lines = $lines
        Sibling = $sib
        StdBegin = $stdBegin; Classes = $classes; Uses = $uses
        Note = $(if ($cat -like '甲*') { '把 C 库名字搬进 std' }
                 elseif ($cat -like '乙*') { "自己定义 $classes 个实体类" }
                 elseif ($incX -gt 0) { "只是 #include <x...> 的壳（$incX 个）" }
                 else { '无实体类' })
    }
}

'=== 分类汇总 ==='
$rows | Group-Object Cat | Sort-Object Name | ForEach-Object {
    $sum = ($_.Group | Measure-Object Lines -Sum).Sum
    "  {0,-14} {1,4} 个  {2,8:N0} 行" -f $_.Name, $_.Count, $sum
}
''
'=== 甲类（C 包装头）—— 只能别名，不能抄 ==='
($rows | Where-Object Cat -like '甲*' | ForEach-Object { "  {0,-16} -> {1,-22} {2,5} 行  using {3}" -f $_.Header,$_.Sibling,$_.Lines,$_.Uses }) -join "`n"
''
'=== 丙类（工具/转发头）—— 待逐个看 ==='
($rows | Where-Object Cat -like '丙*' | ForEach-Object { "  {0,-24} {1,5} 行  {2}" -f $_.Header,$_.Lines,$_.Note }) -join "`n"
''
'=== 乙类（C++ 库头）个数与最大的 10 个 ==='
$b = $rows | Where-Object Cat -like '乙*'
"  共 $($b.Count) 个 / $(($b | Measure-Object Lines -Sum).Sum) 行"
$b | Sort-Object Lines -Descending | Select-Object -First 10 | ForEach-Object { "  {0,-22} {1,6} 行  类 {2}" -f $_.Header,$_.Lines,$_.Classes }

# 写出完整表格
$md = @('# 112 个公开头分类（阶段 1b 产物，由 tools\classify_zhstdlib.ps1 生成）','',
        '| 头 | 类别 | 行数 | 同名 .h | _STD_BEGIN | 实体类 | using | 说明 |',
        '|---|---|---|---|---|---|---|---|')
foreach ($r in $rows) { $md += ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f `
    $r.Header, $r.Cat, $r.Lines, $r.Sibling, $r.StdBegin, $r.Classes, $r.Uses, $r.Note) }
[System.IO.File]::WriteAllLines($out, $md, (New-Object System.Text.UTF8Encoding($false)))
''
"完整表格已写到 $out"
