# ============================================================================
#  中文打印「表达式关键字」守卫（§18.9：大检查 P-13 的回归判据）
#
#  背景（判据要解决的问题）：
#    第 18 道守卫（check_zhdiag_leak.ps1）看的是**消息正文里的英文关键字名**，
#    它靠一张 26 个词的黑名单"扫正文"。而表达式打印器漏出来的那一类
#    （`static_cast<…>`、`new`/`delete`、`true`/`false`、`this`、`typeid`…）
#    **不适合放进那张全局黑名单** —— 同一个词可能正是"代码里要照写的名字"
#    （`operator new`、`__super`、`'std::size_t'`），一扫就误报。
#    ⇒ 这一道改用**正面探针**：拿**英文源码**去编，断言打印出来的是**中文**。
#
#  判据（四条，都要成立）：
#    ① 诊断探针：英文源码（`static_assert(sizeof(int) > 99)`）产生的诊断正文里
#       必须出现**中文拼写**（`大小(整数)`）。用英文源码是有意的 ——
#       这样"源码原样回显"也会露成英文，正面命中才说明**是打印器在翻**
#       （D-02 的纪律：正例探针必须证明那个词真的起了作用）。
#    ② `-ast-print` 探针：英文源码里的 `new`/`delete`/`this`/`typeid`/
#       `static_cast`/`true`/`false`/`nullptr`/`throw`/`sizeof...` 打印出来必须是中文。
#    ③ 对称：同一份源码加 `-fno-chinese-diagnostics`，上面两样都必须回到英文
#       —— 证明我们只是"中文模式给中文"，没有把英文模式也改坏。
#    ④ 自测：判据必须**能失败**（合成输出串），否则等于没有检查。
#
#  跑法：pwsh -NoProfile -File tools\check_zhexpr.ps1
#  退出码：0 = 全过；1 = 有失败
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$exe  = Join-Path $Root 'build\Release\bin\chinese++.exe'
$work = Join-Path $Root 'build\_zhexpr'
New-Item -ItemType Directory -Force $work | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }

if (-not (Test-Path $exe)) { 错 "找不到编译器：$exe"; exit 1 }

# ---------------------------------------------------------------------------
#  自测：判据必须能失败
# ---------------------------------------------------------------------------
function 找禁词([string]$文本, [string[]]$禁) {
    $命中 = @()
    foreach ($w in $禁) {
        if ($文本 -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($w) + '(?![A-Za-z0-9_])')) { $命中 += $w }
    }
    return $命中
}

#  表达式关键字：中文拼写 → 英文拼写（对应关系必须与 ChineseKeywords.def 一致，
#  下面会去表里核，防止"脑中造词"）
$对照 = @(
    @('sizeof',     '大小'),
    @('alignof',    '对齐值'),
    @('static_cast',    '静态转换'),
    @('dynamic_cast',   '动态转换'),
    @('reinterpret_cast', '重释转换'),
    @('const_cast',     '常量转换'),
    @('new',        '新建'),
    @('delete',     '删除'),
    @('this',       '自身'),
    @('true',       '真值'),
    @('false',      '假值'),
    @('nullptr',    '空指针'),
    @('typeid',     '类型标识'),
    @('throw',      '抛出')
)
$禁词 = @($对照 | ForEach-Object { $_[0] })

$自测有 = @(找禁词 "静态断言失败，因为不满足要求（表达式） 'sizeof(int) > 99'" $禁词)
$自测无 = @(找禁词 "静态断言失败，因为不满足要求（表达式） '大小(整数) > 99'" $禁词)
if ($自测有.Count -eq 1 -and $自测有[0] -eq 'sizeof' -and $自测无.Count -eq 0) {
    过 "自测：判据确实能失败（英文残留被抓到 'sizeof'，纯中文不误报）"
} else {
    错 ("自测失败：判据不按预期工作（该抓的抓了 {0} 个、纯中文误报 {1} 个）" -f $自测有.Count, $自测无.Count)
}

# 对照表不许凭空造词：每个英文词都必须能在 ChineseKeywords.def 里对上中文
$kwPath = Join-Path $Root 'llvm-main\clang\include\clang\Basic\ChineseKeywords.def'
$kwTxt  = if (Test-Path $kwPath) { [System.IO.File]::ReadAllText($kwPath) } else { '' }
$造词 = @(); $译错 = @()
foreach ($p in $对照) {
    $en = $p[0]; $zh = $p[1]
    $m = [regex]::Match($kwTxt, 'ZH_(?:KEYWORD|OPERATOR_KEYWORD)\(\s*' + [regex]::Escape($en) + '\s*,\s*([^\s,]+)')
    if (-not $m.Success) { $造词 += $en }
    elseif ($m.Groups[1].Value -ne $zh) { $译错 += ("{0}：表里是 {1}，这里是 {2}" -f $en, $m.Groups[1].Value, $zh) }
}
if ($造词.Count -gt 0) { 错 ("对照表里有 {0} 个词不在 ChineseKeywords.def 里（判据不许凭空造词）：{1}" -f $造词.Count, ($造词 -join ' ')) }
elseif ($译错.Count -gt 0) { 错 ("对照表和关键字表对不上：{0}" -f ($译错 -join '；')) }
else { 过 ("对照表 {0} 个词与 ChineseKeywords.def 逐条一致（判据与关键字表同源）" -f $对照.Count) }

# ---------------------------------------------------------------------------
#  ① 诊断探针：英文源码 → 诊断正文里必须出现中文拼写
#     用 `static_assert` 是因为它会把**整条表达式**打出来（err_static_assert_
#     requirement_failed），而常量表达式里能放的东西正好覆盖 sizeof / cast /
#     布尔字面量 / nullptr / typeid。
# ---------------------------------------------------------------------------
$诊断探针 = @(
    @('D01-sizeof',        'static_assert(sizeof(int) > 99);',                    '大小(整数)'),
    @('D02-static_cast',   'static_assert(static_cast<int>(1.5) > 99);',          '静态转换<整数>(1.5)'),
    @('D03-布尔字面量',    'static_assert(true == false);',                        '真值 == 假值'),
    @('D04-nullptr',       'static_assert(nullptr != nullptr);',                  '空指针 != 空指针')
)

function 取诊断正文([string]$输出) {
    $行 = @()
    foreach ($l in ($输出 -split "`n")) {
        if ($l -match '\b(error|warning|note|fatal error)\s*:') {
            $m = [regex]::Match($l, '\b(?:error|warning|note|fatal error)\s*:\s*(.*)$')
            $b = if ($m.Success) { $m.Groups[1].Value } else { $l }
            $b = $b -replace '\s*\[-W[^\]]*\]\s*$', ''
            $行 += $b.Trim()
        }
    }
    return $行
}

foreach ($p in $诊断探针) {
    $名 = $p[0]; $源码 = $p[1]; $应含 = $p[2]
    $src = Join-Path $work ($名 + '.cpp')
    [System.IO.File]::WriteAllText($src, $源码, $utf8)

    $正文 = 取诊断正文 (& $exe '-std=c++20' -fsyntax-only $src 2>&1 | Out-String)
    if ($正文.Count -eq 0) { 错 ("{0}：一条诊断都没产生（探针没打中 = 没查过）" -f $名); continue }
    $全部 = $正文 -join ' / '
    if ($全部.Contains($应含)) {
        过 ("{0}：诊断里打的是中文拼写「{1}」" -f $名, $应含)
    } else {
        错 ("{0}：诊断里没看到「{1}」—— 实际：{2}" -f $名, $应含, $全部)
    }
    # 禁词：正文里不许出现英文拼写
    $残留 = @()
    foreach ($b in $正文) { $残留 += 找禁词 $b $禁词 }
    if ($残留.Count -eq 0) { 过 ("{0}：诊断正文里没有英文关键字残留" -f $名) }
    else { 错 ("{0}：诊断正文里仍有英文关键字 —— {1}" -f $名, (($残留 | Sort-Object -Unique) -join '、')) }

    # ③ 对称：英文模式下必须回到英文
    $英 = 取诊断正文 (& $exe '-std=c++20' -fno-chinese-diagnostics -fsyntax-only $src 2>&1 | Out-String)
    if ($英.Count -eq 0) { 错 ("{0}：英文模式下一条诊断都没有 —— 开关或探针坏了" -f $名) }
    elseif (($英 -join ' ').Contains($应含)) { 错 ("{0}：英文模式下竟然也打中文「{1}」" -f $名, $应含) }
    else { 过 ("{0}：英文模式（-fno-chinese-diagnostics）回到英文那套" -f $名) }
}

# ---------------------------------------------------------------------------
#  ② `-ast-print` 探针：表达式打印器里其余几条路
#     为什么能这么测：`-ast-print` 走的就是 StmtPrinter/DeclPrinter，
#     与诊断里打印表达式**同一个**打印器（见 ASTConsumers.cpp 的 Print 分支）。
#     同样用**英文源码**，看到中文才说明是打印器在翻。
# ---------------------------------------------------------------------------
$打印源码 = @'
namespace std { class type_info; }
struct A { int x; int f() { return this->x; } };
struct B { virtual ~B() {} };
struct D : B {};
template <class... Ts> int cnt() { return sizeof...(Ts); }
int main() {
  A *p = new A;
  delete p;
  bool b = true;
  b = false;
  int *q = nullptr;
  int n = static_cast<int>(1.5);
  B bo; B *bp = &bo;
  D *dp = dynamic_cast<D*>(bp);
  int *ip = const_cast<int*>(q);
  long lp = reinterpret_cast<long>(q);
  const std::type_info &ti = typeid(int);
  bool tb = &ti != nullptr;
  try { throw 1; } catch (int) { }
  return n + (q ? 1 : 0) + (b ? 1 : 0) + cnt<int>() + (dp ? 1 : 0) +
         (ip ? 1 : 0) + (int)lp + (tb ? 1 : 0);
}
'@
$打印应含 = @('新建', '删除', '自身', '真值', '假值', '空指针', '静态转换<',
              '动态转换<', '常量转换<', '重释转换<', '类型标识(', '抛出', '大小...(')
# 上面每一条对应的英文拼写（对称检查用；`-ast-print` 里没写的构造不强求）
$打印应含英 = @('new', 'delete', 'this', 'true', 'false', 'nullptr', 'static_cast',
                'dynamic_cast', 'const_cast', 'reinterpret_cast', 'typeid', 'throw', 'sizeof')
function 检查打印探针([string]$名, [string]$源码, [string[]]$应含, [string[]]$应含英) {
    $src = Join-Path $work ($名 + '.cpp')
    $err = Join-Path $work ($名 + '.err.txt')
    [System.IO.File]::WriteAllText($src, $源码, $utf8)

    # ⚠ 只看 **stdout**（打印出来的 AST）；诊断走 stderr，**必须分开收** ——
    #   合在一起会把"源码行回显"（编译器报错时打的那几行源码）也算进来，
    #   于是英文关键字"永远还在"，判据就废了（第一版就是这么假红的）。
    $中 = (& $exe '-std=c++20' -fsyntax-only -Xclang -ast-print $src 2>$err | Out-String)
    $诊断 = if (Test-Path $err) { [System.IO.File]::ReadAllText($err) } else { '' }
    if ($诊断 -match '\berror\s*:') {
        错 ("{0}：探针本身**编不过**（探针必须是能编的源码，否则打印出来的 AST 是残缺的）—— {1}" -f $名, (($诊断 -split "`n" | Where-Object { $_ -match '\berror\s*:' } | Select-Object -First 1) -join ''))
    }
    if ($中.Trim().Length -eq 0) { 错 ("{0}：-ast-print 没有任何输出（探针没打中）" -f $名); return }

    $缺 = @($应含 | Where-Object { -not $中.Contains($_) })
    if ($缺.Count -eq 0) { 过 ("{0}：{1} 个中文拼写全部出现" -f $名, $应含.Count) }
    else { 错 ("{0} 里缺这些中文拼写：{1}" -f $名, ($缺 -join '、')) }
    $残留 = @(找禁词 $中 $应含英)
    if ($残留.Count -eq 0) { 过 ("{0}：没有英文关键字残留" -f $名) }
    else { 错 ("{0} 里仍有英文关键字：{1}" -f $名, (($残留 | Sort-Object -Unique) -join '、')) }

    # ③ 对称：同一份源码在英文模式下必须逐条回到英文
    $英 = (& $exe '-std=c++20' -fno-chinese-diagnostics -fsyntax-only -Xclang -ast-print $src 2>$null | Out-String)
    $英缺 = @($应含英 | Where-Object { -not ($英 -match ('(?<![A-Za-z0-9_])' + [regex]::Escape($_) + '(?![A-Za-z0-9_])')) })
    $英中 = @($应含 | Where-Object { $英.Contains($_) })
    if ($英缺.Count -eq 0 -and $英中.Count -eq 0) {
        过 ("{0} 对称：-fno-chinese-diagnostics 下逐条回到英文，一个中文拼写都不剩" -f $名)
    } else {
        错 ("{0} 对称失败：英文模式下缺英文 {1} 个（{2}）、还有中文 {3} 个（{4}）" -f $名, $英缺.Count, ($英缺 -join '、'), $英中.Count, ($英中 -join '、'))
    }
}

检查打印探针 'P01-ast-print' $打印源码 $打印应含 $打印应含英

# 协程三兄弟（`co_await`/`co_yield`/`co_return`）需要一份**能编过**的最小协程才看得到，
# 所以单独一份（含 <coroutine>；promise 型的每个成员都 noexcept，否则 clang 会报错）。
$协程源码 = @'
#include <coroutine>
struct Await {
  bool await_ready() noexcept { return true; }
  void await_suspend(std::coroutine_handle<>) noexcept {}
  void await_resume() noexcept {}
};
struct Task {
  struct promise_type {
    Task get_return_object() noexcept { return {}; }
    Await initial_suspend() noexcept { return {}; }
    Await final_suspend() noexcept { return {}; }
    void return_void() noexcept {}
    void unhandled_exception() {}
    Await yield_value(int) noexcept { return {}; }
  };
};
Task f() {
  co_await Await{};
  co_yield 1;
  co_return;
}
'@
检查打印探针 'P02-协程' $协程源码 @('协程等待', '协程产出', '协程返回') @('co_await', 'co_yield', 'co_return')

Write-Host ''
if ($script:fail -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host ("  => FAIL（{0} 条）" -f $script:fail) -ForegroundColor Red
exit 1
