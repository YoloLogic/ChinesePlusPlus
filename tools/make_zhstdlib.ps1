# ============================================================================
#  make_zhstdlib.ps1 -- 从微软 STL 生成中文标准库的一个头文件
#
#  配方六步（见 docs\标准库汉化\标准库汉化方案.md 第三节）：
#    1. 换 include 守卫（不抢微软的）
#    2. _STD_BEGIN -> 名域 标准 { 名域 细节 { + 使用 名域 std;
#       _STD_END   -> } }
#       【必须搬进自己的名域】—— 否则内部件与微软的撞名（实测 20 个重定义）
#       【必须写 使用 名域 std;】—— 否则对 std 内部件的引用全变未声明（实测 20 处）
#    3. 类型名 -> 中文（含 _ 开头的内部件，用户要求"完全翻译"）
#    4. 成员名 -> 中文
#    5. 手工理嵌套名域引用（pmr 那类）
#    6. 追加派生层：标准::向量 : 公开 细节::向量实现（补回英文名）
#
#  用法：
#      powershell -File tools\make_zhstdlib.ps1 -Header vector
#      powershell -File tools\make_zhstdlib.ps1 -Header vector -OutDir E:\tmp\z
#
#  ⚠ VS 版本号在下面写死；换了 VS 版本要改 $vsInc。
# ============================================================================
param(
    [string] $Header = 'vector',
    [string] $OutDir = ''
)

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx   = Join-Path $root 'build\Release\bin\chinese++.exe'
$vsInc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
if (-not (Test-Path $vsInc)) { throw "MSVC STL 不在 $vsInc —— 换 VS 版本请改脚本顶部的路径" }
if (-not (Test-Path $cxx))   { throw "找不到编译器 $cxx" }
if (-not $OutDir) { $OutDir = Join-Path $root 'zhstdlib' }
#  §18.26 方案②：汉化库搜索路径的单一事实来源（产品按来源分文件夹后，不再是"-isystem zhstdlib"一条）
. (Join-Path $root 'tools\zh_includes.ps1')
$zhIncArgs = Get-ZhIncludeArgs $root
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
#  译名表（本表的种子。做后续头文件时逐步扩充，最终覆盖 2,128 个公开名）
#
#  规则（见方案 §2.2）：先查关键字表 ChineseKeywords.def，再查诊断表
#  ChineseDiagnostics.def（字符串 / 迭代器 / 容器 等已在那里定下），都没有才新定。
# ---------------------------------------------------------------------------

# ---- 类型名（含 _ 开头的内部件 —— 用户要求内部件也翻）----
$typeMap = [ordered]@{
    # 公开类（原本英文里唯一的公开类就是 vector，它变成"实现"那一层）
    'vector'                     = '向量实现'
    # 12 个内部件
    '_Vector_val'                = '_向量值'
    '_Vector_iterator'           = '_向量迭代器'
    '_Vector_const_iterator'     = '_向量常量迭代器'
    '_Vec_iter_types'            = '_向量迭代器类型'
    '_Value_init_tag'            = '_值初始化标签'
    '_Vbase_compare_three_way'   = '_位基三路比较'
    '_Wrap_alloc'                = '_包装分配器'
    '_Vb_iter_base'              = '_位迭代器基类'
    '_Vb_reference'              = '_位引用'
    '_Vb_const_iterator'         = '_位常量迭代器'
    '_Vb_iterator'               = '_位迭代器'
    '_Vb_val'                    = '_位值'
}

# ---- 成员名（vector 的公开成员）----
$memberMap = [ordered]@{
    'push_back'        = '压入'
    'pop_back'         = '弹出末尾'
    'emplace_back'     = '就地压入'
    'emplace'          = '就地构造'
    'insert'           = '插入'
    'erase'            = '擦除'
    'clear'            = '清空'
    'size'             = '尺寸'
    'capacity'         = '容量'
    'empty'            = '为空'
    'reserve'          = '预留'
    'resize'           = '调整大小'
    'shrink_to_fit'    = '收缩到合适'
    'at'               = '取'
    'front'            = '首个'
    'back'             = '末个'
    'data'             = '数据'
    'begin'            = '开始'
    'end'              = '结束'
    'cbegin'           = '常量开始'
    'cend'             = '常量结束'
    'rbegin'           = '反向开始'
    'rend'             = '反向结束'
    'crbegin'          = '常量反向开始'
    'crend'            = '常量反向结束'
    'swap'             = '交换'
    'assign'           = '赋值'
    'max_size'         = '最大尺寸'
    'get_allocator'    = '取分配器'
}

# 派生层：在中文的基础上派生，把英文原名补回来
$derivedLayer = @'

// ============================================================================
//  第二层：在【中文的基础上】派生，把英文原名补回来
//
//  · 第一层（标准::细节::向量实现）是抄自 std::vector 的中文实现，成员名全中文
//  · 本层加回英文原名，所以 表.压入(1) 与 表.push_back(2) 在【同一个对象】上都能用
//  · 与微软的 std::vector 并存、顺序无关（实测两种顺序都过）
//  · 与英文接口的边界：非模板 / 泛型 / 迭代器 / 范围 for 都通；
//    只有"把 std::vector<T> 写死在模板推导位置"的接口需要显式转换一次
// ============================================================================
#include <vector>   // 兼容层要与英文 std::vector 互转，所以这里要引它

名域 标准 {

模板 <类型名 元素, 类型名 分配器 = std::allocator<元素>>
类型 向量 : 公开 细节::向量实现<元素, 分配器> {
    使用 基类 = 细节::向量实现<元素, 分配器>;
    使用 基类::基类;                                   // 继承全部构造函数

    // ---- 英文原名，逐个转发回中文名 ----
    模板 <类型名... 参数> 空型 push_back(参数&&... 值) { 基类::压入(static_cast<参数&&>(值)...); }
    空型 pop_back() { 基类::弹出末尾(); }
    模板 <类型名... 参数> 引用 emplace_back(参数&&... 值) { 返回 基类::就地压入(static_cast<参数&&>(值)...); }
    大小类型 size() 常量 { 返回 基类::尺寸(); }
    大小类型 capacity() 常量 { 返回 基类::容量(); }
    布尔 empty() 常量 { 返回 基类::为空(); }
    空型 clear() { 基类::清空(); }
    空型 reserve(大小类型 个数) { 基类::预留(个数); }
    空型 resize(大小类型 个数) { 基类::调整大小(个数); }
    空型 shrink_to_fit() { 基类::收缩到合适(); }
    引用 at(大小类型 位置) { 返回 基类::取(位置); }
    常量引用 at(大小类型 位置) 常量 { 返回 基类::取(位置); }
    引用 front() { 返回 基类::首个(); }
    引用 back() { 返回 基类::末个(); }
    指针 data() { 返回 基类::数据(); }
    迭代器 begin() { 返回 基类::开始(); }
    迭代器 end() { 返回 基类::结束(); }
    常量迭代器 begin() 常量 { 返回 基类::常量开始(); }
    常量迭代器 end() 常量 { 返回 基类::常量结束(); }
    空型 swap(向量& 别的) { 基类::交换(别的); }

    // ---- 与英文 std::vector 的桥（双向）----
    向量(常量 std::vector<元素, 分配器>& 别的) : 基类(别的.begin(), 别的.end()) {}
    运算符 std::vector<元素, 分配器>() 常量 {
        返回 std::vector<元素, 分配器>(基类::开始(), 基类::结束());
    }
};

}  // 名域 标准
'@

# ---------------------------------------------------------------------------
#  执行六步
# ---------------------------------------------------------------------------
$srcPath = Join-Path $vsInc $Header
if (-not (Test-Path $srcPath)) { throw "找不到 $srcPath" }
$text = [System.IO.File]::ReadAllText($srcPath)
$origLines = ([System.IO.File]::ReadAllLines($srcPath)).Count

Write-Host "=== 生成 <$Header> 的中文版 ===" -ForegroundColor Cyan
Write-Host "  源: $origLines 行"

# --- 步 1：换守卫（找最前面的 #ifndef X / #define X 一对）---
$gm = [regex]::Match($text, '(?m)^#ifndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\r?\n#define\s+\1\b')
if (-not $gm.Success) { throw "没找到 include 守卫，无法换名" }
$oldGuard = $gm.Groups[1].Value
$newGuard = '_ZH_' + ($Header.ToUpper() -replace '[^A-Z0-9]', '_') + '_'
$text = $text.Replace("#ifndef $oldGuard", "#ifndef $newGuard").Replace("#define $oldGuard", "#define $newGuard")
Write-Host "  步1 守卫: $oldGuard -> $newGuard"

# --- 步 2：搬进 标准::细节 + 兜底 ---
$nb = ([regex]::Matches($text, '_STD_BEGIN')).Count
$ne = ([regex]::Matches($text, '_STD_END')).Count
$text = $text.Replace('_STD_BEGIN', "名域 标准 { 名域 细节 {`n使用 名域 std;")
$text = $text.Replace('_STD_END', '} }')
Write-Host "  步2 名域: _STD_BEGIN x$nb / _STD_END x$ne -> 名域 标准 { 名域 细节 { + 使用 名域 std;"

# --- 步 3+4：类型名、成员名 ---
$nType = 0; $nMember = 0
foreach ($k in $typeMap.Keys) {
    $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count
    if ($c -gt 0) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $typeMap[$k]); $nType += $c }
}
foreach ($k in $memberMap.Keys) {
    $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count
    if ($c -gt 0) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $memberMap[$k]); $nMember += $c }
}
Write-Host "  步3 类型名: $nType 处（$(($typeMap.Keys) -join ', ') 共 $($typeMap.Count) 个）"
Write-Host "  步4 成员名: $nMember 处（$($memberMap.Count) 个）"

# --- 步 5：手工理 pmr 那两处 ---
#
#  ⚠ 这里**不能**对 polymorphic_allocator 做全局替换：文件顶部有
#      #include <xpolymorphic_allocator.h>
#  全局替换会把它改成 <xstd::pmr::polymorphic_allocator.h> —— 文件名被改坏，
#  立刻 fatal error: 找不到文件 'xstd::pmr::polymorphic_allocator.h'。
#  （本项目已有同类教训：verify_chinese_keywords.py 第一版整文件替换把注释里的
#    60 处文档改坏。凡是"整文件替换"都要先想清楚它会碰到哪些非代码文本。）
#  所以只在【那一条 using 语句】里替换。
$before = $text
$text = [regex]::Replace($text,
    'using\s+向量实现\s*=\s*_STD\s+向量实现<([^;]*?),\s*polymorphic_allocator<([^;]*?)>>\s*;',
    'using 向量实现 = 标准::细节::向量实现<$1, std::pmr::polymorphic_allocator<$2>>;')
Write-Host ("  步5 pmr 修补: {0}" -f $(if ($text -ne $before) { '已改（只动了那一条 using 语句）' } else { '未命中（形参名可能不同，需手工看）' }))

# --- 步 6：追加派生层 ---
$text = $text + $derivedLayer

# --- 写出 ---
New-Item -ItemType Directory -Force $OutDir | Out-Null
$outPath = Join-Path $OutDir '向量'
[System.IO.File]::WriteAllText($outPath, $text, $utf8)
$outLines = ([System.IO.File]::ReadAllLines($outPath)).Count
Write-Host "  步6 派生层: 已追加"
Write-Host ""
Write-Host ("  输出: {0}  ({1} 行，源 +{2})" -f $outPath, $outLines, ($outLines - $origLines)) -ForegroundColor Green

# ---------------------------------------------------------------------------
#  步 4b：让【我们的编译器】当这次改名的校对
#
#  为什么会撞：文本替换分不清"我们类的成员"和"借用类型的同名成员"。
#  实测 <vector> 里 29 个成员名有 3 个会撞 —— begin / end 撞
#  std::initializer_list 的 begin/end，swap 撞 std::swap。
#  编译器分得清，而且它给出行列号。所以：编译 → 读它报的"没有名为 X 的成员"
#  → 按坐标把那一个标识符改回英文 → 再编译，直到干净。
#
#  这一步是【必须的】，不是补丁：它是"成员名改名"能自动化的唯一可靠办法。
# ---------------------------------------------------------------------------
$headerName = Split-Path $outPath -Leaf
$probe = Join-Path $env:TEMP ('zhprobe_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.cpp')
[System.IO.File]::WriteAllText($probe,
    "#包含 <$headerName>`n整数 主函数(){ 标准::$($typeMap['vector'].Replace('实现',''))<整数> 表; 表.压入(1); 返回 0; }`n", $utf8)

$rev = @{}
foreach ($k in $memberMap.Keys) { $rev[$memberMap[$k]] = $k }

for ($round = 1; $round -le 10; $round++) {
    #  ⚠ 必须钉住 `-fdiagnostics-column-unit=byte`：下面把列号直接当字节偏移用
    #    （$off = $Col - 1）。2026-10-03 §18.5 把默认列号口径改成显示列后，
    #    这里会算歪、撤回静默失效 —— 见 make_zhstdlib2.ps1 里同一处的长注释。
    $raw = & cmd /c "`"$cxx`" -std=c++20 -fdiagnostics-column-unit=byte -isystem`"$OutDir`" -ferror-limit=0 -fsyntax-only `"$probe`" 2>&1"
    $hits = @()
    foreach ($l in @($raw)) {
        if ([string]$l -match "$headerName`:(\d+):(\d+): error: .*没有名为（成员名） '([^']+)' 的成员") {
            $hits += [pscustomobject]@{ Line = [int]$Matches[1]; Col = [int]$Matches[2]; Name = $Matches[3] }
        }
    }
    if ($hits.Count -eq 0) {
        Write-Host ("  步4b 第 {0} 轮: 编译器校对通过，无同名冲突" -f $round) -ForegroundColor Green
        break
    }
    $lines = [System.IO.File]::ReadAllLines($outPath)
    $fixed = 0; $skipped = 0; $missed = 0
    foreach ($h in ($hits | Sort-Object Line, Col -Descending)) {
        if (-not $rev.ContainsKey($h.Name)) { $skipped++; continue }
        $idx = $h.Line - 1
        if ($idx -lt 0 -or $idx -ge $lines.Count) { continue }
        $line = $lines[$idx]
        # ⚠ 关键：clang 报的列号是【字节】偏移，不是字符偏移。
        #   实测 3045 行：前 32 字节 = "        插入(开始(), _Ilist."（中文一字 3 字节），
        #   所以第 33 列正是第二个「开始」的起点。按字符算会全部落空（第一版就是这样，
        #   10 轮只改中 1 处）。所以这里一律用 UTF-8 字节比对，再折回字符下标。
        $lineBytes = [System.Text.Encoding]::UTF8.GetBytes($line)
        $nameBytes = [System.Text.Encoding]::UTF8.GetBytes($h.Name)
        $off = $h.Col - 1
        if ($off -lt 0 -or ($off + $nameBytes.Length) -gt $lineBytes.Length) { $missed++; continue }
        $ok = $true
        for ($i = 0; $i -lt $nameBytes.Length; $i++) {
            if ($lineBytes[$off + $i] -ne $nameBytes[$i]) { $ok = $false; break }
        }
        if (-not $ok) { $missed++; continue }
        $charIdx = [System.Text.Encoding]::UTF8.GetString($lineBytes, 0, $off).Length
        $lines[$idx] = $line.Remove($charIdx, $h.Name.Length).Insert($charIdx, $rev[$h.Name])
        $fixed++
    }
    [System.IO.File]::WriteAllLines($outPath, $lines, $utf8)
    Write-Host ("  步4b 第 {0} 轮: 编译器指出 {1} 处借用类型同名成员，改回英文 {2} 处（跳过 {3}，坐标没对上 {4}）" -f `
        $round, $hits.Count, $fixed, $skipped, $missed)
    if ($fixed -eq 0) { Write-Host "  !! 一处都没改中，停止循环（避免空转）" -ForegroundColor Yellow; break }
}
Remove-Item $probe -Force -ErrorAction SilentlyContinue

$finalLines = ([System.IO.File]::ReadAllLines($outPath)).Count
Write-Host ""
Write-Host ("  最终: {0}  ({1} 行)" -f $outPath, $finalLines) -ForegroundColor Green
