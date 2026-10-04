# ============================================================================
#  中文打印「语句与声明关键字」守卫（第 24 道）—— §18.12：大检查 P-14
#
#  与第 22 道（tools\check_zhexpr.ps1）的分工：
#    · 第 22 道管**表达式**里的关键字（P-13：static_cast/new/delete/true/false/
#      nullptr/this/typeid/throw/sizeof.../协程三兄弟）；
#    · 这一道管**语句与声明**里的关键字（P-14：if/else/for/while/do/switch/case/
#      default/goto/continue/break/return/try/catch/asm/volatile/noexcept/requires，
#      以及声明侧的 namespace/struct/class/enum/typedef/using/concept/virtual/
#      static/extern/inline/constexpr/consteval/mutable/friend/thread_local/auto/
#      访问说明符 public/private/protected/标签关键字…）。
#
#  为什么分两道而不是合成一道：这两批是**两个问题**（P-13 由测试撞出来、P-14 是
#  顺着同一批往下捋登记出来的），分道之后"哪一批退回去了"一眼能看出来。
#  手法完全相同：`-ast-print` + **英文源码** —— 看到中文才说明**是打印器在翻**；
#  若用中文源码，"源码原样回显"也会给出中文，判据就分不清（D-02 的纪律）。
#
#  判据（四条）：
#    ① 语句探针：英文源码打印出来必须是中文（期望的中文词一个不少、英文词一个不剩）
#    ② 声明探针：同上
#    ③ 对称：同一份源码加 -fno-chinese-diagnostics，必须逐条回到英文
#    ④ 自测：判据必须**能失败**（合成输出串）
#
#  跑法：pwsh -NoProfile -File tools\check_zhstmt.ps1
#  退出码：0 = 全过；1 = 有失败
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$exe  = Join-Path $Root 'build\Release\bin\chinese++.exe'
$work = Join-Path $Root 'build\_zhstmt'
New-Item -ItemType Directory -Force $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }

if (-not (Test-Path $exe)) { 错 "找不到编译器：$exe"; exit 1 }

function 找禁词([string]$文本, [string[]]$禁) {
    $命中 = @()
    foreach ($w in $禁) {
        if ($文本 -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($w) + '(?![A-Za-z0-9_])')) { $命中 += $w }
    }
    return $命中
}

# ---------------------------------------------------------------------------
#  ④ 自测：判据必须能失败
# ---------------------------------------------------------------------------
$自测词 = @('if', 'return')
$自测无 = @(找禁词 '如果 (甲 < 乙) { 返回 1; }' $自测词)
$自测坏 = @(找禁词 'if (甲 < 乙) { return 1; }' $自测词)
if ($自测无.Count -eq 0 -and $自测坏.Count -eq 2) {
    过 "自测：判据确实能失败（英文 'if'/'return' 会被抓到，中文不误报）"
} else {
    错 ("自测失败：判据不按预期工作（中文误报 {0} 个、英文该抓的抓了 {1} 个）" -f $自测无.Count, $自测坏.Count)
}

# ---------------------------------------------------------------------------
#  ①② 打印探针（都用**英文源码**：看到中文才证明是打印器在翻）
#     只看 stdout（打印出来的 AST）；诊断走 stderr，分开收 —— 合在一起会把
#     "源码行回显"也算进来，于是英文关键字"永远还在"（第 22 道踩过这个坑）。
# ---------------------------------------------------------------------------
function 检查打印探针([string]$名, [string]$源码, [string[]]$应含, [string[]]$禁词) {
    $src = Join-Path $work ($名 + '.cpp')
    $err = Join-Path $work ($名 + '.err.txt')
    [System.IO.File]::WriteAllText($src, $源码, $utf8)

    $中 = (& $exe '-std=c++20' -fsyntax-only -Xclang -ast-print $src 2>$err | Out-String)
    $诊断 = if (Test-Path $err) { [System.IO.File]::ReadAllText($err) } else { '' }
    if ($诊断 -match '\berror\s*:') {
        错 ("{0}：探针本身**编不过**（探针必须是能编的源码，否则打印出来的 AST 是残缺的）—— {1}" -f $名, (($诊断 -split "`n" | Where-Object { $_ -match '\berror\s*:' } | Select-Object -First 1) -join ''))
    }
    if ($中.Trim().Length -eq 0) { 错 ("{0}：-ast-print 没有任何输出（探针没打中）" -f $名); return }

    $缺 = @($应含 | Where-Object { -not $中.Contains($_) })
    if ($缺.Count -eq 0) { 过 ("{0}：{1} 个中文拼写全部出现" -f $名, $应含.Count) }
    else { 错 ("{0} 里缺这些中文拼写：{1}" -f $名, ($缺 -join '、')) }

    $残留 = @(找禁词 $中 $禁词)
    if ($残留.Count -eq 0) { 过 ("{0}：没有英文关键字残留" -f $名) }
    else { 错 ("{0} 里仍有英文关键字：{1}" -f $名, (($残留 | Sort-Object -Unique) -join '、')) }

    # ③ 对称：英文模式下必须逐条回到英文
    $英 = (& $exe '-std=c++20' -fno-chinese-diagnostics -fsyntax-only -Xclang -ast-print $src 2>$null | Out-String)
    $英缺 = @($禁词 | Where-Object { -not ($英 -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($_) + '(?![A-Za-z0-9_])')) })
    $英中 = @($应含 | Where-Object { $英.Contains($_) })
    if ($英缺.Count -eq 0 -and $英中.Count -eq 0) {
        过 ("{0} 对称：-fno-chinese-diagnostics 下逐条回到英文，一个中文拼写都不剩" -f $名)
    } else {
        错 ("{0} 对称失败：英文模式下缺英文 {1} 个（{2}）、还有中文 {3} 个（{4}）" -f $名, $英缺.Count, ($英缺 -join '、'), $英中.Count, ($英中 -join '、'))
    }
}

# ① 语句
$语句源码 = @'
int g(int x) {
  int s = 0;
  for (int i = 0; i < x; ++i) {
    if (i == 2)
      continue;
    else if (i == 3)
      break;
    switch (i) {
    case 1: s += 1; break;
    default: s += 2; break;
    }
    while (s < 5) { ++s; }
    do { ++s; } while (s < 3);
    if (i == 9) goto done;
  }
done:
  try { if (x < 0) throw 1; }
  catch (int) { s += 4; }
  return s;
}
'@
$语句应含 = @('如果 (', '否则 如果 (', '对于 (', '跳过;', '跳出;', '选择 (', '情形 1:', '默认:', '每当 (', '执行 ', '跳转 done', '尝试 ', '捕获 (', '返回 s;')
$语句禁词 = @('if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default', 'goto', 'continue', 'break', 'try', 'catch', 'return')
检查打印探针 'P03-语句' $语句源码 $语句应含 $语句禁词

# ② 声明（含标签关键字、存储类、访问说明符）
$声明源码 = @'
namespace ns { struct S { int x; }; }
enum E { A, B };
typedef int MyInt;
using Alias = int;
template <class T> concept C = true;
struct D : ns::S { virtual void f(); mutable int m; static int s; friend void g(D&); };
extern int ev;
static int sv = 0;
inline int iv() { return 0; }
constexpr int cv = 0;
thread_local int tv = 0;
class K { public: int p; private: int q; protected: int r; };
'@
$声明应含 = @('名域 ns', '结构 S', '枚举 E', '类型别名 ', '使用 Alias', '概念 C', '类型 T',
              '虚拟 ', '可变 ', '静态 ', '友元 ', '外部 ', '内联 ', '常量表达式 ', '线程局部 ',
              '公开:', '私有:', '受保护:')
$声明禁词 = @('namespace', 'struct', 'class', 'enum', 'typedef', 'using', 'concept', 'virtual',
              'mutable', 'static', 'friend', 'extern', 'inline', 'constexpr', 'thread_local',
              'public', 'private', 'protected')
检查打印探针 'P04-声明' $声明源码 $声明应含 $声明禁词

# ---------------------------------------------------------------------------
#  ⑤ 源码扫描：两个打印器里**不许再留**"等于已译关键字"的英文字面量
#
#  为什么探针之外还要扫描：探针只覆盖它**触发到**的那几条分支 ——
#  `asm`/`volatile`/`goto *`/`consteval`/`noexcept(`/`requires`/`operator""`
#  这些很难在 `-ast-print` 里自然出现（要构造特定语法），扫描把**整张表**钉住。
#  反过来说，扫描**也替代不了探针**：它证明不了"编译器真的打出来"。
#  ⇒ 两个都要。（P-14 实施时正是扫描先扫出漏掉的 `return`/`default`/`typename `，
#    而探针随后又扫出 `static`/`extern` 走的是**另一条**打印路径 —— 互为补充。）
# ---------------------------------------------------------------------------
$kwPath = Join-Path $Root 'llvm-main\clang\include\clang\Basic\ChineseKeywords.def'
$已译 = @{}
if (Test-Path $kwPath) {
    foreach ($l in [System.IO.File]::ReadAllLines($kwPath)) {
        $m = [regex]::Match($l, '^\s*ZH_(?:KEYWORD|OPERATOR_KEYWORD|VIRT_SPECIFIER|CONTEXTUAL_KEYWORD)\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([^\s,]+)')
        if ($m.Success) { $已译[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
}
# 有意保留 / 已被覆盖的（逐条写理由）
$扫描豁免 = @{
    'template' = '`template` 的用户拼写中文表里两种并存（`template<>` 与 `模板<>`），回显哪个都不算错 —— 与第 18 道守卫的"有意不列黑名单"同一条口径'
}
$扫描豁免行 = @{
    'Spelling = "alignof";' = 'UETT_AlignOf 的**默认**拼写，紧随其后就被共用的 getPrintedKeywordSpelling 覆盖（见同函数）；Policy.Alignof/UnderscoreAlignof/__alignof 三种上游开关要先摆好'
}

# 判据写成函数：真扫描跑一次，自测（合成行）再跑一次 —— 判据必须**能失败**
function 找关键字字面量([string]$行) {
    $中 = @()
    if ($行.TrimStart().StartsWith('//')) { return $中 }
    if ($行 -match 'getPrintedKeywordSpelling') { return $中 }   # 帮手自己的英文兜底实参
    if ($扫描豁免行.ContainsKey($行.Trim())) { return $中 }
    foreach ($m in [regex]::Matches($行, '"([A-Za-z_][A-Za-z0-9_]*)( |\(|:|;|)?"')) {
        $w = $m.Groups[1].Value
        if (-not $已译.ContainsKey($w)) { continue }
        if ($扫描豁免.ContainsKey($w)) { continue }
        $中 += $w
    }
    return $中
}

$自测扫有 = @(找关键字字面量 '      OS << "return";')
$自测扫无 = @(找关键字字面量 '      OS << 返回;')
$自测扫帮 = @(找关键字字面量 '      OS << getPrintedKeywordSpelling(Policy, tok::kw_return, "return");')
if ($自测扫有.Count -eq 1 -and $自测扫有[0] -eq 'return' -and $自测扫无.Count -eq 0 -and $自测扫帮.Count -eq 0) {
    过 "源码扫描自测：英文关键字字面量会被抓到，中文与帮手调用不误报"
} else {
    错 ("源码扫描自测失败：该抓 {0} 个 / 中文误报 {1} 个 / 帮手误报 {2} 个" -f $自测扫有.Count, $自测扫无.Count, $自测扫帮.Count)
}

$扫描漏 = @()
foreach ($f in @('StmtPrinter.cpp', 'DeclPrinter.cpp')) {
    $path = Join-Path $Root ('llvm-main\clang\lib\AST\' + $f)
    if (-not (Test-Path $path)) { 错 ("找不到打印器源码：{0}" -f $f); continue }
    $i = 0
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        $i++
        foreach ($w in @(找关键字字面量 $line)) { $扫描漏 += ("{0}:{1} '{2}'（应为 {3}）" -f $f, $i, $w, $已译[$w]) }
    }
}
if ($扫描漏.Count -eq 0) {
    过 ("源码扫描：StmtPrinter / DeclPrinter 里没有'已译关键字的英文'字面量（对照 {0} 个关键字拼写）" -f $已译.Count)
} else {
    错 ("源码扫描：打印器里还有英文关键字字面量 —— " + ($扫描漏 -join '；'))
}

Write-Host ''
if ($script:fail -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host ("  => FAIL（{0} 条）" -f $script:fail) -ForegroundColor Red
exit 1
