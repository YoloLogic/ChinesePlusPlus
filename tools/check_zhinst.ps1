# ============================================================================
#  check_zhinst.ps1 —— §17.20 「每个中文名都要能被真正用起来」实例化守卫
#
#  为什么要有它（2026-09-30 实测的事故）：
#    别名轨道的测试台从不把条目里的反引号-n 转成真换行 -> 整段用例写成一行 ->
#    `#包含` 之后的记号全被当"多余记号"（只警告）-> **43 个别名产物的"用法用例"
#    从没真正用过任何名字**，只证明"产品能解析"。修好测试台后立刻暴露 18/43 有真 bug
#    （endl/ends/flush/ws 一实例化就编不过、正则查找特征形参推导冲突…）。
#    结论：**"头能 include" != "名能用"**，而这正是用户验收判据最容易被绕过的地方。
#
#  判据（三条互不替代，一起记账）：
#    ① 自动探针：类型 -> 声明该类型的对象指针；**模板 -> 从表的 tparam/模板头合成实参**
#       （`向量<整数>`、`位集<1>`）；常量 -> 读一次；非模板函数 -> 取一次地址。
#       每个产物一个 TU，**编成 exe 并真跑**（不只 -fsyntax-only）。
#    ② 条目用例覆盖：名字出现在该条目自带用例里（那里的用例现在是真编译 + 真运行的）。
#    ③ 未覆盖：模板函数 / 概念 / 命名空间 / 预处理行等"无法自动生成实参"的名字，
#       必须写明**原因分类** —— 账要诚实显示"还缺"，不许把做不到的混进"已覆盖"。
#    ④ §17.21 模板函数「合成实参真调用」探针：**表里有名字 != 名字能被调用**。
#       别名层的手写签名（`生成` = std::generate 却写成返回 `输出迭代`）以前藏在
#       ③里没人看得见；现在模板函数也按形参合成见证**真调一次**，
#       见下面 §17.21 一节（A 级调用 / B 级显式模板实参）。
#
#  名字来源：三张生成器表（不是手写清单）。新增名字自动进账。
#    · 深度轨道 make_zhstdlib2.ps1 -ExportJson（产品公开名 + tparam + types/手写层）
#    · 别名轨道 make_zhalias.ps1   -ExportJson（常量/类型/函数/原样 四型）
#    · C  轨道 make_zhc.ps1 的 $T 表（类型/函数）
#
#  用法：
#    pwsh -File tools\check_zhinst.ps1              # 跑全量 + 重写台账
#    pwsh -NoProfile -File tools\check_zhinst.ps1 -Check        # 只校验台账（闸门用）
#    pwsh -NoProfile -File tools\check_zhinst.ps1 -Only 向量,时间   # 只跑某几个产物（调试）
#    pwsh -NoProfile -File tools\check_zhinst.ps1 -Shards 1     # 关并行（调试/对照，~20 分钟）
#  并行等价性口径（§17.38）：分片**连续**切、按序合并 -> 台账与串行**逐字节一致**；
#  `-PartialOut`/`-ManifestFile`/`-Shard` 是父进程给子进程用的，正常别手敲。
# ============================================================================
param([switch] $Check, [switch] $Quiet, [string[]] $Only = @(),
      #  §17.38 分片并行（父进程建清单 + 合并；子进程各跑连续的一片）
      [int] $Shards = 0, [int] $Shard = 0, [string] $PartialOut = '', [string] $ManifestFile = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx = Join-Path $root 'build\Release\bin\chinese++.exe'
$out = Join-Path $root 'zhstdlib'
$work = Join-Path $root 'build\_zhinst'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$ledger = Join-Path $root 'docs\标准库汉化\实例化台账.md'
$zhName = '[\u4e00-\u9fff][\w\u4e00-\u9fff]*'

function Test-ZhName([string] $s) { return ($s -match ('^' + $zhName + '$')) }

# ---------------------------------------------------------------------------
#  模板实参合成：把 `模板 <类型名 元素, 类型名 分配器 = ...>` 变成 `整数`
#    · 有默认值的形参不传；类型形参**按角色**给见证；非类型形参传 `1`
#    · 全默认 -> 返回 $null（调用方用裸名字）
# ---------------------------------------------------------------------------
#  §17.23 类型形参要**按角色**给见证：一律给 `整数` 会当场炸 ——
#  实测 `标准::细节::映射实现<整数, 整数, 整数, 整数>` 报
#  `std::pointer_traits<int> 中没有名为 rebind 的成员`（第四个形参是分配器）。
#  §17.31 视图类模板的"范围见证"要**多种形状**：容器只满足一部分视图的约束 ——
#  `elements_view`（键视图/值视图）要"元素是 pair 的范围"、`join_view`（连接视图）要"元素是范围的范围"。
#  所以同一个别名会出 3 条候选（任意一条编过即算这个名字能实例化）。
$script:ViewWitness = '标准::引用视图<标准::向量<整数>>'
$script:ViewWitnessVariants = @(
    '标准::引用视图<标准::向量<整数>>',
    '标准::引用视图<标准::向量<标准::向量<整数>>>',
    '标准::引用视图<标准::向量<std::pair<整数, 整数>>>'
)
function Get-RoleArg([string] $decl, [string[]] $all, [int] $idx) {
    $nm = ($decl -split '\s+')[-1].TrimEnd('.')
    if ($nm -match '分配器|分配|allocator|_Al') {
        #  容器内部件的分配器形参受**静态断言**约束：必须是 `allocator<pair<const Key, Value>>`
        #  （实测：给 `std::allocator<整数>` 会炸在 `_MISMATCHED_ALLOCATOR_MESSAGE`）。
        #  判据：它前面有几个类型形参 —— ≥2 个（键/值）就是 pair 型分配器，1 个是元素型分配器。
        $before = @($all[0..([Math]::Max(0, $idx - 1))] | Where-Object { $_ -match '^类型名' }).Count
        if ($idx -ge 2 -and $before -ge 2) { return 'std::allocator<std::pair<常量 整数, 整数>>' }
        return 'std::allocator<整数>'
    }
    if ($nm -match '比较|谓词|_Pr$|^_Pr') { return '通用见证' }
    #  §17.31 `函数`/`_Fn` 也要**可调用**见证，而且视图类模板要的是**一元**可调用 ——
    #  给 `std::less<整数>` 会撞「约束未满足」（`invocable<less<int>&, int&>` 为假，它是二元的）。
    #  `通用见证` 同时有一元/二元两个重载，两种位置都能满足。
    if ($nm -match '函数|_Fn$|^_Fn|操作$|_Op$') { return '通用见证' }
    if ($nm -match '散列|哈希|_Hasher|_Hash') { return 'std::hash<整数>' }
    if ($nm -match '键相等|_Keyeq') { return 'std::equal_to<整数>' }
    if ($nm -match '相等|_Eq') { return 'std::equal_to<整数>' }
    if ($nm -match '特征|traits|_Traits') { return 'std::char_traits<字符>' }
    #  §17.27 视图/范围类模板的形参要**真范围**（给 `整数` 会报「约束未满足」，实测 19 处）；
    #  `_Ki` 是 subrange_kind 枚举值、`比` 是 `ratio<>`（给 `1` 会撞静态断言）。
    #  §17.28 但**视图类模板**要的是"真视图"：`transform_view<向量<整数>, F>` 撞「约束未满足」
    #  （容器不是 view），给 `标准::引用视图<标准::向量<整数>>`（ref_view）才对。
    if ($nm -match '^_Vw$|视图类型|可作视图') { return $script:ViewWitness }
    if ($nm -match '^_Rng$|^_Range$|范围类型|可借范围') { return '标准::向量<整数>' }
    if ($nm -match '^_Pat$|^_Pattern$|^模式$') { return '标准::向量<整数>' }
    #  §17.28 `某类型`（`位` 那一族的 `模板 <类型名 某类型> … 名(某类型 值)`）要给**无符号**见证：
    #  `std::countr_zero(整数)` / `std::rotr(整数, 整数)` 对**有符号**类型没有匹配重载（实测 7 个全卡这）。
    if ($nm -match '^某类型$|^通用类型$') { return '无符号 整数' }
    if ($nm -match '^_Ki$|^_Kind$|^种类$') { return 'std::ranges::subrange_kind::sized' }
    if ($nm -match '^比|^_R1$|^_R2$|^_R$|ratio') { return 'std::ratio<1, 1>' }
    if ($nm -match '^_CharT$|^_Elem$|^_元素$|字符类型') { return '字符' }
    if ($nm -match '^_Out$|^_OutIt$|输出迭代') { return '整数*' }
    #  §17.33 成员函数（std::mem_fn 那一族的形参）要**真成员函数指针**当见证：
    #  给 整数 会撞「没有与 'mem_fn' 匹配的函数」，而这**不是**签名病（注册是对的）。
    if ($nm -match '^成员函数$|^_Pmf$') { return 'decltype(&std::string::size)' }
    #  §17.39 **哨兵必须与迭代器不是同一类型**：`公共迭代器实现<_Iter, _Se>` 的约束里有
    #  `!same_as<_Iter, _Se>`，两个都给 `整数*` 必失败（§17.36 记的"约束未满足"就是这个）✗。
    #  哨兵给 `常量 整数*`：它仍满足 `sentinel_for<整数*>`，但与 `整数*` 不是同一类型 ✓。
    #  ⚠ 只拆**哨兵**：`尾`（尾迭代器）**必须和 `首` 同类型**（`距离(首,尾)` 一族要求 same_as），
    #  一起改就会换一批名字去死 —— "改一个见证 = 动一片名字"，必须收窄。
    if ($nm -match '^_Se$|^_Sentinel$|^哨兵') { return '常量 整数*' }
    #  §17.40 **指针形参**要有指针见证：`检查数组迭代器<_Ptr>` 里有
    #  `static_assert(is_pointer_v<_Ptr> && is_object_v<remove_pointer_t<_Ptr>>)` ——
    #  默认给 `整数` 必然撞这个断言 ✗，给 `整数*` 才是一次真实例化 ✓。
    if ($nm -match '^_Ptr$|^_Pointer$|^指针') { return '整数*' }
    if ($nm -match '^_It$|^_Iter$|^_Iterator$|^迭代|迭代$|^尾$|^首$') { return '整数*' }
    return '整数'
}
function Get-TemplateArgs([string] $decl) {
    if (-not $decl) { return $null }
    $m = [regex]::Match($decl, '模板\s*<(?<body>.*)>\s*$')
    if (-not $m.Success) { return $null }
    $body = $m.Groups['body'].Value
    $parts = @(); $depth = 0; $cur = ''
    foreach ($ch in $body.ToCharArray()) {
        if ($ch -eq '<' -or $ch -eq '(') { $depth++ }
        elseif ($ch -eq '>' -or $ch -eq ')') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $parts += $cur; $cur = '' } else { $cur += $ch }
    }
    if ($cur.Trim()) { $parts += $cur }
    $nd = @()   # 不带默认值的形参（顺序保留）—— 角色判定要看"它前面有几个类型形参"
    #  §17.31 例外：`subrange` 的 `_Ki`（subrange_kind）**即使有默认值也要显式给 `sized`** ——
    #  默认值是 `unsized`，配上 `整数*` 这种随机访问迭代器会撞约束（实测 `子范围` 就卡这）。
    foreach ($p in $parts) {
        $pp = $p.Trim()
        if (-not $pp) { continue }
        if ($pp -match '=') {
            if ($pp -match '^类型名\s+(_Ki|_Kind)\b') { $nd += ($pp -split '=')[0].Trim() }
            continue
        }
        $nd += $pp
    }
    #  §17.43 **非类型形参**：形参的类型写成"本模板已声明的类型形参名"时，它是**值**形参
    #  （实测 `模板 <类型名 某类型, 某类型 值> 使用 整数常量 = std::integral_constant<…>`：
    #   第二个形参是值 -> 给 `1` -> `标准::整数常量<整数, 1>` ✓）。
    #  若是值**包**（`某类型... 值`）-> **直接不传**（空包合法：`标准::整数序列<整数>` ✓）。
    #  一次销掉 `整数序列` / `整数常量` 两个公开名（§17.43 归属判定）。
    $typeParamNames = @()
    foreach ($p in $parts) {
        $pp0 = ($p -split '=')[0].Trim()
        $tm = [regex]::Match($pp0, '^(?:类型名|class|typename)\s+([\w\u4e00-\u9fff]+)$')
        if ($tm.Success) { $typeParamNames += $tm.Groups[1].Value }
    }
    $args = @()
    for ($i = 0; $i -lt $nd.Count; $i++) {
        #  ⚠ 值包的写法是 `某类型... 值`（**点号跟着类型名**）—— 判类型形参名之前必须先把点号去掉，
        #  否则 `某类型...` 匹配不上 `某类型`，包就漏判成"类型形参"（实测 `整数序列<无符号 整数, 整数>` ✗）。
        $head = ($nd[$i] -split '\s+')[0].TrimEnd('.')
        if ($typeParamNames -contains $head) {
            if ($nd[$i] -match '\.\.\.') { continue }   # 值包：不传（空包合法）
            $args += '1'
            continue
        }
        #  ⚠ 深拷贝里关键字混用：形参可能写成 `类型名 X`，也可能还是 `class X` / `typename X`
        #  （实测 `模板 <class _Kty, class _类型, class _Pr, class _分配器>`）—— 两种都要认。
        #  §17.36 形参分类改**默认当类型**：受约束形参（input_or_output_iterator _Iter）、
        #  概念名+形参名的写法都不是 类型名 开头；只有明确的非类型关键字才给 1。
        if ($nd[$i] -match '^(std::size_t|size_t|std::ptrdiff_t|ptrdiff_t|整数|无符号 整数|布尔|bool|int|长整型|自动)\b') { $args += '1' }
        else { $args += (Get-RoleArg $nd[$i] $nd $i) }
    }
    if ($args.Count -eq 0) { return $null }
    return ($args -join ', ')
}
#  §17.23 内部件的模板头**不一定在本行**，而且深拷贝里的关键字可能还是英文
#  （实测：`template <class _Kty, class _类型, class _Pr, class _分配器>` 的下一行才是
#   `class 映射实现 : public _树<…>`）—— 所以从「class/类型 X」这一行**回头看**最近的 `模板 <…>`。
function Get-ImplArgsFromText([string] $text, [string] $impl) {
    if (-not $text) { return $null }
    #  §17.40 类名前面可能夹**宏**：实测 `template <class _Ptr> class _DEPRECATE_STDEXT_ARR_ITERS 检查数组迭代器 {`
    #  —— 老正则要求 `class` **紧跟**名字 ✗ -> 实参整段取不到 -> 只剩 `<>` -> 记成"太少个模板实参"，
    #  而真因是"我没找到模板头"。放宽成"同一行里，类关键字之后出现过这个名字"。
    $cm = [regex]::Match($text, '(?m)^\s*(?:类型|类|结构|class|struct)\s+[^\n]*?(?<![\w\u4e00-\u9fff])' + [regex]::Escape($impl) + '(?![\w\u4e00-\u9fff])')
    if (-not $cm.Success) { return $null }
    $before = $text.Substring(0, $cm.Index)
    #  ⚠ 前缀必须写 `.*`（贪婪）才会命中**最近**的那个模板头；否则正则从文件开头第一个
    #    `template <` 一路吞到类声明前（实测把 `_映射特征` 的类体整段当成模板头）。
    #  ⚠ 模板头与类声明之间常夹**注释行**（实测 公共迭代器实现 就是这样）—— 不能要求"紧邻"。
    #  取最后 4 行里**最后一个** 模板 <...>（贪婪前缀 = 最近的）。
    #  §17.39 模板头与类声明之间还夹着 **requires 子句**（实测 `公共迭代器实现`）：
    #      _EXPORT_STD template <input_or_output_iterator _Iter, sentinel_for<_Iter> _Se>
    #          requires (!same_as<_Iter, _Se> && copyable<_Iter>)
    #      class 公共迭代器实现 {
    #  老写法要求"模板头就是这几行的最后一行"（`>\s*$` 收尾），被 requires 行一挡就取不到实参 ✗
    #  -> 改成**从尾部往上逐行扫**，第一条「…模板 <…>」且以 `>` 收尾的行就是它。
    #  `(.*)>` 贪婪取到**行内最后一个** `>`，所以形参带默认值 `= std::vector<整数>` 也照样对。
    $cand = @($before -split "`n" | Select-Object -Last 16)
    for ($li = $cand.Count - 1; $li -ge 0; $li--) {
        $lm = [regex]::Match([string]$cand[$li], '(?:模板|template)\s*<(.*)>\s*$')
        if ($lm.Success) { return (Get-TemplateArgs ('模板 <' + $lm.Groups[1].Value + '>')) }
    }
    return $null
}

# ---------------------------------------------------------------------------
#  §17.21 模板函数「合成实参真调用」探针
#
#  事故（实测）：别名层 `生成` 的签名写成
#    `模板 <类型名 迭代, 类型名 输出迭代, 类型名 生成器> 输出迭代 生成(迭代 首, 迭代 尾, 生成器 丙)`
#  而 std::generate 返回 void —— `输出迭代` 只出现在返回类型里，永远推导不出来，
#  用户一写 `标准::生成(首, 尾, 丙)` 就是「没有匹配的函数」。旧守卫对模板函数
#  **一律不做探针**（记「模板函数-无探针」），于是"根本调不通"能长期藏在"未覆盖"里。
#  护栏口径：**表里有名字 != 名字能被调用**；模板函数也要真的调一次。
#
#  两级（都真编译；调用写在**永不被调用的 lambda 里** —— 证明的是"能实例化调用"，
#  不是运行时行为，于是不会把算法的 UB 引到探针进程里）：
#    A 调用探针    `标准::名(见证…)`            普通推导调用
#    B 显式实参探针 `标准::名<见证类型…>(见证…)`  A 失败才跑：把"只在返回类型里出现的
#      形参"当显式模板实参传进去。**合法**的（`时长转换<目标时长>`）在 B 下通过；
#      **签名有病**的（`生成`）在 B 下实例化函数体，报错**正落在这个名字自己的定义行**
#      —— 只有这一种判真失败。B 的报错落在别处 = 见证表达不出，记「未覆盖」，
#      不冤判库。
# ---------------------------------------------------------------------------
function Split-TopLevel([string] $s) {
    $o = @(); $depth = 0; $cur = ''
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '<' -or $ch -eq '(' -or $ch -eq '[') { $depth++ }
        elseif ($ch -eq '>' -or $ch -eq ')' -or $ch -eq ']') { $depth-- }
        if ($ch -eq ',' -and $depth -eq 0) { $o += $cur; $cur = '' } else { $cur += $ch }
    }
    if ($cur.Trim()) { $o += $cur }
    return $o
}
function Get-TemplateBody([string] $line) {
    $i = $line.IndexOf('模板'); if ($i -lt 0) { return '' }
    $j = $line.IndexOf('<', $i); if ($j -lt 0) { return '' }
    $depth = 0
    for ($k = $j; $k -lt $line.Length; $k++) {
        $ch = $line[$k]
        if ($ch -eq '<') { $depth++ }
        elseif ($ch -eq '>') { $depth--; if ($depth -eq 0) { return $line.Substring($j + 1, $k - $j - 1) } }
    }
    return ''
}
function Get-FuncParams([string] $line) {
    $m = [regex]::Match($line, '([\u4e00-\u9fff][\u4e00-\u9fff_0-9]*)\s*\(([^()]*)\)\s*(?:不抛出|noexcept)?\s*\{')
    if (-not $m.Success) { return $null }
    return @{ Name = $m.Groups[1].Value; Params = (Split-TopLevel $m.Groups[2].Value) }
}
#  见证种类：组=整数数组（迭代器）、出=输出缓冲、壹=左值、丙=变参 lambda、引=随机引擎、范=向量
function New-WitnessDecl([string[]] $kinds, $id) {
    $d = @()
    if ($kinds -contains '组') { $d += "        整数 组$id[8]{0,1,2,3,4,5,6,7};" }
    if ($kinds -contains '出') { $d += "        整数 出$id[32]{};" }
    if ($kinds -contains '壹') { $d += "        整数 壹$id = 1;" }
    if ($kinds -contains '无') { $d += "        无符号 整数 无$id = 1;" }
    if ($kinds -contains '丙') { $d += "        自动 丙$id = [](自动&&... 参){ 返回 1; };" }
    if ($kinds -contains '引') { $d += "        标准::默认随机引擎 引$id{};" }
    if ($kinds -contains '范') { $d += "        标准::向量<整数> 范$id{1,2,3,4};" }
    if ($kinds -contains '复') { $d += "        标准::复数<整数> 复$id{1, 2};" }
    return ($d -join "`n")
}
#  §17.31 模板别名/模板类型的探针行：视图类模板出**多条范围形状**候选，
#  其余只出一条。返回第一条；第 2/3 条塞进调用方给的引用槽。
function Get-AliasProbeLine($n, $id) {
    $isView = ($n.Template -match '视图|_Vw')
    $tries = $(if ($isView) { @(0, 1, 2) } else { @(0) })
    $made = @()
    foreach ($vi in $tries) {
        $script:ViewWitness = $script:ViewWitnessVariants[$vi]
        $a = Get-TemplateArgs $n.Template
        if ($a) { $made += ("    {0}<{1}>* 针{2}_{3} = 空指针; (空型)针{2}_{3};" -f ('标准::' + $n.Name), $a, $id, $vi) }
        elseif ($n.Template -and $vi -eq 0) { $made += ("    标准::{0}<>* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id) }
    }
    $script:ViewWitness = $script:ViewWitnessVariants[0]
    $script:AliasSlot2 = $(if ($made.Count -ge 2) { $made[1] } else { $null })
    $script:AliasSlot3 = $(if ($made.Count -ge 3) { $made[2] } else { $null })
    if ($made.Count -ge 1) { return $made[0] }
    return $null
}
#  §17.32 **跨产物复用真实实例化**：内部件的宿主常常是"要一个 traits 类当实参"的模板
#  （`class _哈希` 的模板头只有 `template <class _特征>`），角色见证给不出 traits
#  —— 但**容器**那边写着真实形态：`class 无序映射实现 : public _哈希<_无序映射特征<_Kty, _类型,
#  _无序哈希比较<_Kty,_Hasher,_Keyeq>, _分配器, false>>`。
#  所以：把全库扫一遍，给每个类名记下**第一次被真实实例化时的实参文本**，再把其中的叶子标识符
#  按角色替换（`_Hasher`→`std::hash<整数>` 等），得到可用的宿主实参 —— 零猜测、零额外编译。
$script:InstMap = @{}
#  §17.32 深度感知地取 `类名<...>` 的实参文本（正则抓不了任意嵌套：
#  `_哈希<_无序映射特征<…<_无序哈希比较<…>>>`）—— 用配对计数扫。
function Get-FirstInstantiation([string] $text, [string] $cls) {
    $m = [regex]::Match($text, [regex]::Escape($cls) + '\s*<')
    if (-not $m.Success) { return '' }
    $j = $m.Index + $m.Length - 1
    $depth = 0
    for ($k = $j; $k -lt $text.Length; $k++) {
        $ch = $text[$k]
        if ($ch -eq '<') { $depth++ }
        elseif ($ch -eq '>') { $depth--; if ($depth -eq 0) { return $text.Substring($j + 1, $k - $j - 1) } }
    }
    return ''
}
#  把实例化实参文本里的**叶子标识符**按角色替换（嵌套结构递归）
#  ⚠ 两条实测踩过的坑（§17.32）：
#    ① 角色判定要传 `类型名 X` 形态的数组 —— 直接传裸标识符会让"分配器前面有几个类型形参"数成 0，
#       于是 `_分配器` 退化成 `std::allocator<整数>`，撞容器的 `_MISMATCHED_ALLOCATOR_MESSAGE` 静态断言；
#    ② 结果里的类名要**限定** `标准::细节::`（探针 TU 在全局作用域，裸 `_无序映射特征` 看不见）。
function Get-SubstitutedArgs([string] $argsText) {
    $parts = Split-TopLevel $argsText
    $roleAll = @()
    foreach ($pp2 in $parts) {
        $t2 = $pp2.Trim()
        if (-not $t2) { continue }
        if ($t2 -match '^(true|false|真值|假值|\d+)$') { $roleAll += ('整数 ' + $t2) } else { $roleAll += ('类型名 ' + $t2) }
    }
    $out = @(); $i = -1
    foreach ($p in $parts) {
        $t = $p.Trim()
        if (-not $t) { continue }
        $i++
        if ($t -match '^[\w\u4e00-\u9fff]+\s*<') {
            $nm = [regex]::Match($t, '^([\w\u4e00-\u9fff]+)\s*<(.*)>\s*$')
            $cls2 = $nm.Groups[1].Value
            if ($cls2 -notmatch '^(std|标准)') { $cls2 = '标准::细节::' + $cls2 }
            $body2 = (Get-SubstitutedArgs $nm.Groups[2].Value)
            #  §17.37 内层实参表为空（`_树<>`、`_树值<_树<>>` 这类）时**必须补 `<>`**，不能退化成裸类名：
            #  能进这个分支就说明原文带尖括号，即它是个模板 id；`X<>` 是合法拼写而裸名不是类型。
            #  实测畸形候选 `标准::细节::_树值<标准::细节::<>>` 就是空体被拼坏的结果。
            if ($body2) { $out += ($cls2 + '<' + $body2 + '>') } else { $out += ($cls2 + '<>') }
        } elseif ($t -match '^(true|false|真值|假值|\d+)$') { $out += $t }
        elseif ($t -match '^[\w\u4e00-\u9fff]+\.\.\.$') { $out += '整数' }   # §17.36 包形参（_Inner...）
        elseif ($t -match '^[\w\u4e00-\u9fff]+$') { $out += (Get-RoleArg $roleAll[$i] $roleAll $i) }
        else { $out += $t }
    }
    return ($out -join ', ')
}
function Get-Witness([string] $type, [string] $pname, $id) {
    #  返回 @{ Expr; Kind } ；$null = 这个形参见证不出来（整个名字不做探针）
    $t = ($type.Trim() -replace '^const\s+', '') -replace '\s*[&*]+\s*$', ''
    $k = ''
    if ($t -match '^输出迭代|^输出迭代器|^插入迭代') { $k = '出' }
    elseif ($t -match '迭代|哨兵|_Se$') { $k = '组' }
    #  §17.26 复数的自由函数（`标准::常用对数` 等）形参是 `细节::复数实现<元素>&` ——
    #  给 `整数` 会炸，得给一个**真的复数对象**（原生头同样写法能编：实测 复数<整数> 也行）。
    elseif ($t -match '复数实现') { $k = '复' }
    elseif ($t -match '^(谓词|比较|一元操作|二元操作|生成器|函数|成员函数|操作|条件|判据)$') { $k = '丙' }
    elseif ($t -match '^(值类型|大小类型|距离类型|类型1|类型2|元素|别的|替换类型|整数类型|实数类型)$') { $k = '壹' }
    #  §17.28 `某类型` 给**无符号**左值（`位` 一族对 `整数` 没有匹配重载）
    elseif ($t -match '^(某类型|通用类型)$') { $k = '无' }
    elseif ($t -match '^成员函数$|^_Pmf$') { $k = '成' }
    elseif ($t -match '^(std::size_t|std::ptrdiff_t|size_t|整数|长整型|无符号整数)$') { $k = '壹' }
    elseif ($t -match '^范围类型$') { $k = '范' }
    elseif ($pname -match '^引擎$' -and $t -match '^引擎$') { $k = '引' }
    else { return $null }
    $expr = switch ($k) {
        '组' { if ($pname -match '尾') { "组$id + 8" } elseif ($pname -match '中') { "组$id + 2" } else { "组$id" } }
        '出' { if ($pname -match '尾') { "出$id + 32" } else { "出$id" } }
        '壹' { "壹$id" }
        '无' { "无$id" }
        '成' { '&std::string::size' }
        '丙' { "丙$id" }
        '引' { "引$id" }
        '范' { "范$id" }
        '复' { "复$id" }
        default { return $null }
    }
    return @{ Expr = $expr; Kind = $k }
}
# ---------------------------------------------------------------------------
#  §17.22 未覆盖的"账目质量"：判据②要求**剩余项都带理由登记为边界且有消除路径**。
#  只有"未覆盖"四个字不算登记 —— 每个名字都要能看出①为什么没覆盖②下一步怎么销。
# ---------------------------------------------------------------------------
function Get-ReasonClass([string] $r) {
    if ($r -match '^手写层') { return '手写层·嵌套成员（需宿主类型）' }
    if ($r -match '^概念') { return '概念（模板实参合成不出）' }
    if ($r -match '^调用探针编不过') { return '模板函数（调用探针编不过）' }
    if ($r -match '^调用探针表达不出') { return '模板函数（显式实参也编不过）' }
    if ($r -match '^变参转发器') { return '变参转发器（一元/二元都编不过）' }
    if ($r -match '重载') { return '重载函数（需具体实参）' }
    if ($r -match '合成实参不适用') { return '模板类型/别名/内部件（合成实参不适用）' }
    if ($r -match '-无探针') { return '无探针（见证表表达不出）' }
    return '其它'
}
#  ⚠ 台账必须**可复算**（同一次生成跑两遍要一字不差，否则闸门的 -Check 永远报"已过期"）。
#  探针文件名里带 `[Math]::Abs($n.Name.GetHashCode())`，而 .NET 的字符串 hash **每个进程随机化** ——
#  报错文本一旦原样进账，两遍就是两份不同的账。所以进账前只留**编译器的话**，去掉
#  `盘符:\…\build\_zhinst\p_xxx_n123.cpp:12:9:` 这段"我们自己的路径 + 随机 hash"。
#  确定性短 id（FNV-1a）：`.NET` 的 `String.GetHashCode` **每个进程随机化**，
#  一旦它进了探针变量名/文件名，报错文本就会带上随机数 -> 台账不可复算（§17.22.1 实测）。
function Get-StableId([string] $s) {
    $h = [int64]2166136261
    foreach ($c in $s.ToCharArray()) {
        $h = $h -bxor [int64][int][char]$c
        $h = ($h * 16777619) % 4294967296
    }
    return [int]($h % 2000000000)
}
function Get-ErrBrief([string] $e) {    if (-not $e) { return '' }
    $m = [regex]::Match($e, 'error:\s*(.*)$')
    $t = $(if ($m.Success) { $m.Groups[1].Value } else { $e })
    $t = $t -replace '[A-Za-z]:\\[^:]*\\build\\_zhinst\\[^:]*', '<探针>'
    #  编译器会把我们的**探针变量名**原样写进消息（`针988430044_2`）—— 这是另一条随机来源。
    #  变量名现在已是确定性计数器，这里再做一道保险：把任何长数字串归一化。
    $t = $t -replace '(?<=\D)\d{6,}(?=\D|$)', '#'
    $t = $t -replace '\b(针f?|探B?|壹|组|出|丙|引|范)\d+(?:_\d+)?', '$1#'
    return $t.Trim()
}
function Get-FixPath([string] $reason, [string] $kind) {
    if ($reason -match '^手写层') { return '按它的宿主类型写嵌套探针（`标准::宿主<实参>::名`），或给条目补一条真用它的用例' }
    if ($reason -match '^概念') { return '给它的模板形参加见证（`Get-TypeArgWitness`），或补一条真用一次概念的用例' }
    if ($reason -match '^调用探针|^模板函数') { return '把该形参的见证加进 `Get-Witness`，或给条目补一条真调用用例' }
    if ($reason -match '^变参转发器') { return '补一条带**真实参类型**的调用用例（打印/格式化类要格式串，整数哑实参天然不匹配）' }
    if ($reason -match '重载') { return '补一条带具体实参的调用用例（取地址有歧义 -> 直接调用）' }
    if ($reason -match '合成实参不适用') { return '给条目补一条真用一次的用例；这正是"条目用例"该干的事（见台账"用例覆盖"列）' }
    if ($reason -match '-无探针') { return '扩见证表（`Get-Witness` / `Get-TemplateArgs`），或补一条真用例' }
    return '补一条真用例，或扩见证表（判责规则见 tools\check_zhinst.ps1 顶部）'
}
#  §17.27 **静态宿主推断**：`types` 里的成员 typedef（`尺寸类型`/`常量局部迭代器`/`键类型`…）
#  不是 `细节::` 下的顶层类型，而是某个类模板的成员。宿主不用猜、也不用编译器试：
#  在产物正文里找到它的声明行（`使用 名 = …` / `using 名 = …`），往上找**最近的、缩进更小的**
#  类/结构声明 —— 深拷贝的缩进是稳定的（每层 4 空格）。宿主自身的模板实参用同一套合成。
#  返回 ''=推断不出；否则返回宿主表达式（两次都返回：调用方自己决定试哪个命名空间）。
function Get-EnclosingHost([string] $text, [string] $name) {
    if (-not $text) { return '' }
    $lines = $text -split "`n"
    $declIdx = -1; $declIndent = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*(?:使用|using)\s+' + [regex]::Escape($name) + '\s*=')) {
            $declIdx = $i
            $declIndent = ([regex]::Match($lines[$i], '^\s*')).Length
            break
        }
    }
    if ($declIdx -lt 0) { return '' }
    for ($i = $declIdx - 1; $i -ge 0; $i--) {
        $l = $lines[$i]
        if ($l -notmatch '\S') { continue }
        if (([regex]::Match($l, '^\s*')).Length -ge $declIndent) { continue }
        $cm = [regex]::Match($l, '^\s*(?:类型|类|结构|class|struct)\s+([\w\u4e00-\u9fff]+)')
        if ($cm.Success) {
            $cls = $cm.Groups[1].Value
            $ia = Get-ImplArgsFromText $text $cls
            return [pscustomobject]@{ Class = $cls; Args = $ia }
        }
    }
    return ''
}
function Get-WitnessIncludes([string[]] $kinds) {
    $inc = @()
    if ($kinds -contains '引') { $inc += '随机' }
    if ($kinds -contains '范') { $inc += '向量' }
    if ($kinds -contains '复') { $inc += '复数' }
    if ($kinds -contains '成') { $inc += '字符串' }
    return $inc
}
#  §17.23 宿主限定的成员探针：`标准::映射<整数, 整数>::尺寸类型* 针 = 空指针;`
#  深轨道的这些名字本来就活在类体里（`类型 映射 : 公开 细节::映射实现<键,映射值,比较,分配器>`），
#  顶层 `标准::尺寸类型` 当然找不到 —— §17.22 之前这一整批只有一句"需宿主类型"，从没真试过宿主形态。
#  ⚠ 形参别叫 `$host` —— `$Host` 是 PowerShell 的**只读自动变量**（host UI 对象），
#    同名形参一调用就报「无法覆盖变量 host，因为它是只读变量或常量」（实测踩过）。
function Get-NestedLine([string] $hostExpr, $n, $id) {
    switch ([string]$n.Inner) {
        '类型' { return ("    {0}::{1}* 针{2} = 空指针; (空型)针{2};" -f $hostExpr, $n.Name, $id) }
        '模板别名' { $a = Get-TemplateArgs $n.Template; if ($a) { return ("    {0}::{1}<{2}>* 针{3} = 空指针; (空型)针{3};" -f $hostExpr, $n.Name, $a, $id) } }
        '常量' { return ("    (空型){0}::{1};" -f $hostExpr, $n.Name) }
        '函数' { return ("    自动 针f{0} = &{1}::{2}; (空型)针f{0};" -f $id, $hostExpr, $n.Name) }
    }
    return $null
}
function Get-TypeArgWitness([string] $body, $id) {
    #  模板形参 -> 显式模板实参；有一个见证不出来就返回 $null（B 级探针不做）
    if (-not $body) { return $null }
    $args = @()
    foreach ($p in (Split-TopLevel $body)) {
        $t = $p.Trim(); if (-not $t) { continue }
        if ($t -match '=') { $t = ($t -split '=')[0].Trim() }
        $nm = ($t -split '\s+')[-1].TrimEnd('.')
        if ($t -match '^类型名') {
            if ($nm -match '^(迭代|迭代1|迭代2|输出迭代|输出迭代器|随机迭代)$') { $args += '整数*' }
            elseif ($nm -match '^(谓词|比较|一元操作|二元操作|生成器|函数|成员函数|操作|条件|判据)$') { $args += "decltype(丙$id)" }
            elseif ($nm -match '^(值类型|大小类型|距离类型|类型1|类型2|元素|别的|替换类型|整数类型|实数类型)$') { $args += '整数' }
            else { return $null }
        } else { $args += '1' }
    }
    if (-not $args.Count) { return $null }
    return ($args -join ', ')
}
function New-TplProbe($n, $id, [string] $prodPath) {
    #  返回 @{ Name; Kind; Line(A); LineB; DefLine } ；$null = 见证表达不出，不做探针
    if (-not $n.Raw) { return $null }
    $fp = Get-FuncParams $n.Raw
    if (-not $fp) { return $null }
    $wits = @(); $kinds = @()
    foreach ($pd in $fp.Params) {
        $t = $pd.Trim(); if (-not $t) { continue }
        $pm = [regex]::Match($t, '^(.*?)[\s&*]+([\u4e00-\u9fff][\u4e00-\u9fff_0-9]*)$')
        if (-not $pm.Success) { return $null }
        $w = Get-Witness $pm.Groups[1].Value $pm.Groups[2].Value $id
        if (-not $w) { return $null }
        $wits += $w.Expr
        if ($kinds -notcontains $w.Kind) { $kinds += $w.Kind }
    }
    if (-not $wits.Count) { return $null }
    $decl = New-WitnessDecl $kinds $id
    $lineA = "    自动 探$id = [](){`n$decl`n        标准::$($n.Name)($($wits -join ', '));`n    };`n    (空型)探$id;"
    $lineB = $null
    $ta = Get-TypeArgWitness (Get-TemplateBody $n.Raw) $id
    if ($ta) { $lineB = "    自动 探B$id = [](){`n$decl`n        标准::$($n.Name)<$ta>($($wits -join ', '));`n    };`n    (空型)探B$id;" }
    #  这个名字在产物里的定义行号：判真失败要求报错**正落在这行**
    $defLine = 0
    if (Test-Path $prodPath) {
        $txt = [System.IO.File]::ReadAllText($prodPath)
        $dl = [regex]::Match($txt, '(?m)^.*[\s(]' + [regex]::Escape($n.Name) + '\s*\(')
        if ($dl.Success) { $defLine = @($txt.Substring(0, $dl.Index) -split "`n").Count }
    }
    return [pscustomobject]@{ Name = $n.Name; Kind = '模板函数探针'; Line = $lineA; LineB = $lineB; DefLine = $defLine; ExtraInc = (Get-WitnessIncludes $kinds) }
}

# ---------------------------------------------------------------------------
#  从「原样」/手写层的 C++ 行里提名字、类别与模板头
# ---------------------------------------------------------------------------
function Get-NamesFromLine([string] $line) {
    $out = @()
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('//') -or $t.StartsWith('#')) { return $out }
    if ($t -match '^\s*名域\s+[\w\u4e00-\u9fff]+\s*\{' -or $t -eq '}') { return $out }
    $tmpl = ''
    $mt = [regex]::Match($t, '^(模板\s*<.*?>)\s')
    if ($mt.Success) { $tmpl = $mt.Groups[1].Value }
    $m = [regex]::Match($t, '^模板\s*<[^>]*>\s*概念\s+(' + $zhName + ')')
    #  §17.22 概念也能机器探针：`(空型)标准::概念名<整数…>;` —— 概念求值对任何实参都良构
    #  （不满足只是求值为 false，不是编译错误），所以"合成实参"这条路对概念是通的。
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '概念'; Template = $tmpl }) }
    $m = [regex]::Match($t, '^模板\s*<[^>]*>\s*使用\s+(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '模板别名'; Template = $tmpl }) }
    $m = [regex]::Match($t, '^使用\s+(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '类型'; Template = '' }) }
    if ($t -match '^模板\s*<') {
        #  ⚠ 名字必须是「参数表后紧跟函数体 `{`」的那个 —— 不能取行里第一个 `名(`：
        #    `声明类型(自动) 变换(...) { ... }`（decltype(auto) 返回类型，§16.52）里第一个
        #    `名(` 是关键字 `声明类型`，取它会**用假名顶掉真名** —— 真名就此不在账上。
        #    实测（2026-09-30）：`时长转换`/`时间点转换`/`时钟转换`/`时长上取整`/`时长四舍五入`/
        #    `生成规范数`/`变换`… 一整批真名被一个 `声明类型` 顶掉。**账上少一个名字，
        #    比多一个假名更坏**：少的那几个永远没人去覆盖。
    if ($t -match '\)\s*:\s*') { return $out }   # §17.36 ctor 初始化列表里的 名( 不是函数名（基类(值) {}）
    $m = [regex]::Match($t, '(' + $zhName + ')\s*\(([^()]*)\)\s*(?:不抛出|noexcept)?\s*\{')
        if (-not $m.Success) {
            $m2 = [regex]::Match($t, '\s(' + $zhName + ')\s*\(')   # 体在下一行：退回第一个，但关键字不算名字
            #  §17.42 关键字集：`运算符`（operator）也是**关键字不是名字** —— 我给 <字符串>/
            #  <字符串视图> 补 `std::hash` 特化时写了 `size_t 运算符()(...)`，提取器立刻
            #  多出两条假名字（`字符串|运算符`、`字符串视图|运算符`）并把它们记成"未覆盖" ✗。
            #  与 §17.36 的 `声明类型`（decltype）同一个病，一并排除。
            if ($m2.Success -and @('声明类型', '运算符', '自动', '返回') -notcontains $m2.Groups[1].Value) { $m = $m2 }
        }
        #  Raw = 原始签名行：§17.21 要从行里抠出「模板形参」和「函数形参」做调用探针
        if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '模板函数'; Template = $tmpl; Raw = $t }) }
        return $out
    }
    $m = [regex]::Match($t, '^内联\s+常量\s+[^=]+?\s(' + $zhName + ')\s*=')
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '常量'; Template = '' }) }
    #  ⚠ 同 §17.21.1 的教训，这一支也要守：**参数表后必须紧跟函数体 `{`** ——
    #  否则 `内联 声明类型(自动) 格式化参数版(std::string_view 甲, …)` 会把返回类型里的关键字
    #  `声明类型` 当成函数名，探针 `&标准::声明类型` 报「缺少非限定标识符」并被判**真失败**
    #  （实测：格式化文本 —— 与 §17.21.1 那次是同一个病，只是换了 `函数` 这一支）。
    $m = [regex]::Match($t, '(' + $zhName + ')\s*\(([^()]*)\)\s*(?:不抛出|noexcept)?\s*\{')
    if (-not $m.Success) {
        $m2 = [regex]::Match($t, '^(?:内联\s+|常量表达式\s+|静态\s+)*[\w:<>,\s&*]+\s(' + $zhName + ')\s*\(')
        #  §17.42 同上一支：关键字不算名字（`运算符` = operator）
        if ($m2.Success -and @('声明类型', '运算符', '自动', '返回') -notcontains $m2.Groups[1].Value) { $m = $m2 }
    }
    if ($m.Success) { return @([pscustomobject]@{ Name = $m.Groups[1].Value; Kind = '函数'; Template = '' }) }
    return $out
}

function Get-NamesFromCode([string] $code) {
    $r = @()
    foreach ($ln in ($code -split "`r?`n")) { $r += Get-NamesFromLine $ln }
    return $r
}

# ---------------------------------------------------------------------------
#  三张表 -> (产品, tparam, 名字, 用例文本)
# ---------------------------------------------------------------------------
#  §17.43 「公开名 / 内部名」两栏口径（用户 2026-10-02 拍板）：
#    · **公开名** = 用户能从 `标准::` 直接命名：`标准::X` / `标准::X<…>` / `标准::X<…>::名` / 库公开的 `标准::名`；
#    · **内部名** = 只能经 `标准::细节::…` 或私有成员命名 —— 单列一栏、**不计入公开覆盖率**，
#      但同样要有真实例化证据（不许当遮羞布）。
#  ⚠ 这张表是**分类注记**，不是名字来源（名字仍只来自三张生成器表）。
#    每一行都做过「原生对照」：原生**也不公开**同名 API，且我们没有转发。
#    （反过来：**原生公开而我们写不出来的 = 真 bug**，必须立刻修 —— 见 §17.43 的四象限。）
$script:InternalNames = @{
    '流缓冲类型' = '原生 std::ranges::basic_istream_view 也没有 streambuf_type（实测）'
    '独占锁实现' = '原生 std::unique_lock 的公开中文名是 标准::独占锁（实测可写）；本名是细节层实现类'
    '锁守卫实现' = '原生 std::lock_guard 的公开中文名是 标准::锁守卫（实测可写）；本名是细节层实现类'
    '键比较器'   = '原生 std::unordered_map 也不公开 key_compare（实测）；有序映射的 键比较器 经 标准::映射 已覆盖'
    '值比较'     = '同 键比较器（原生不公开 value_compare）'
}
function Get-NameScope([string] $n) {
    if ($script:InternalNames.ContainsKey($n)) { return '内部' }
    return '公开'
}

#  §17.38：**子进程跳过整段表解析**。三张表各要起一个 `-ExportJson` 子进程，实测每片启动
#  约 1.5 分钟；10 片就是 15 分钟的纯重复成本（比它要并行省下的还多）✗。
#  子进程的清单由父进程用 `Export-Clixml` 落盘，这里直接跳过，账不会因此变松：
#  清单内容仍然是**父进程刚解析出来的同一份**（§15.3：跑 0 条不算通过，所以父进程那句
#  `$rows` 全部来自分片的断言还在）。
if (-not $ManifestFile) {
$products = @()

# ① 别名轨道
$ajson = & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhalias.ps1') -ExportJson 2>$null | Out-String
$atab = $ajson | ConvertFrom-Json
foreach ($p in $atab.PSObject.Properties) {
    $names = @()
    foreach ($e in $p.Value.a) {
        switch ($e[0]) {
            '常量' { if (Test-ZhName $e[1]) { $names += [pscustomobject]@{ Name = $e[1]; Kind = '常量'; Template = '' } } }
            '类型' { if (Test-ZhName $e[1]) { $names += [pscustomobject]@{ Name = $e[1]; Kind = '类型'; Template = '' } } }
            '函数' { if (Test-ZhName $e[1]) { $names += [pscustomobject]@{ Name = $e[1]; Kind = '模板函数'; Template = '' } } }
            '原样' { $names += Get-NamesFromLine ([string]$e[1]) }
        }
    }
    $tests = ''
    if ($p.Value.PSObject.Properties.Name -contains 'tests') { foreach ($tc in $p.Value.tests) { $tests += ([string]$tc[1]) + "`n" } }
    $products += [pscustomobject]@{ Track = '别名'; Product = $p.Value.zh; TParam = ''; Names = @($names | Sort-Object Name -Unique); Tests = $tests }
}

# ② 深度轨道
$djson = & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhstdlib2.ps1') -ExportJson 2>$null | Out-String
$dtab = $djson | ConvertFrom-Json
#  §17.32 预扫：给每个内部件类名收集**所有**真实实例化（带所属产物）。
#  为什么是「所有」：`_哈希` 在库里是**两个不同的类**（xhash 的哈希表 / xstring 的字符串哈希），
#  「第一个命中」会抓错；而 traits 类往往声明在**容器**里（`无序映射:31 class _无序映射特征`），
#  探针 TU 必须把那个产物也引进来才看得见。所以：多候选 + 各自带所属产物。
$script:FileCache = @()
Get-ChildItem $out -File -ErrorAction SilentlyContinue | ForEach-Object { $script:FileCache += ,@($_.Name, [System.IO.File]::ReadAllText($_.FullName)) }
foreach ($pp in $dtab.PSObject.Properties) {
    if (-not (($pp.Value.PSObject.Properties.Name -contains 'types') -and $pp.Value.types)) { continue }
    foreach ($kk in $pp.Value.types.PSObject.Properties) {
        $vn = [string]$kk.Value
        if (-not $script:InstMap.ContainsKey($vn)) { $script:InstMap[$vn] = @() }
        foreach ($fc in $script:FileCache) {
            $body = Get-FirstInstantiation $fc[1] $vn
            if (-not $body) { continue }
            if (@($script:InstMap[$vn] | ForEach-Object { $_.Text }) -notcontains $body) {
                $script:InstMap[$vn] += @{ Text = $body; Product = $fc[0] }
            }
            if ($script:InstMap[$vn].Count -ge 4) { break }
        }
    }
}
foreach ($p in $dtab.PSObject.Properties) {
    $zh = $p.Value.zh
    $tp = ''
    if (($p.Value.PSObject.Properties.Name -contains 'tparam') -and $p.Value.tparam) { $tp = [string]$p.Value.tparam.decl }
    $names = @()
    #  产品名只有当它在产品正文里**确实被声明为类型**时才当类型探针 —— 否则会误报
    #  （`数值算法`/`版本`/`字符转换` 这类头是"只有函数/只有宏"的，`标准::数值算法` 不是类型）。
    $declaresType = $false; $pubName = $zh      # 每轮显式复位（PowerShell 的 if 不建作用域，不复位会串到下一个产物）
    $prodFile = Join-Path $out $zh
    $ptxt = ''
    if (Test-Path $prodFile) { $ptxt = [System.IO.File]::ReadAllText($prodFile) }
    if (Test-ZhName $zh) {
        $pubName = $zh
        if (($p.Value.PSObject.Properties.Name -contains 'pub') -and $p.Value.pub) { $pubName = [string]$p.Value.pub }
        if ($ptxt) {
            $declaresType = ($ptxt -match ('(?m)^\s*(?:类型|使用)\s+' + [regex]::Escape($pubName) + '\b'))
        }
        if ($declaresType) { $names += [pscustomobject]@{ Name = $pubName; Kind = $(if ($tp) { '模板类型' } else { '类型' }); Template = $tp } }
    }
    #  §17.23 宿主表达式：嵌套成员探针必须写成 `标准::宿主<实参>::名`。
    #    · 公开宿主 = `标准::<pub>`；有模板形参就带**合成实参**（`Get-TemplateArgs` 那套）
    #    · 内部件宿主 = `标准::细节::<X>`（`types` 里的内部实现类）
    $hostPub = ''
    if ($declaresType) {
        $ha = Get-TemplateArgs $tp
        $hostPub = $(if ($ha) { "标准::$pubName<$ha>" } else { "标准::$pubName" })
    }
    $hostImps = @()
    $implArgs = @{}   # 内部件名 -> 它自己的合成实参（从产物正文的 `模板 <…> 类型 X` 精确取）
    $memberHost = @{}  # §17.27 成员 typedef 名 -> 静态推断出的宿主 @{Class;Args}
    $memberHostCross = @{}  # §17.32 成员 typedef 名 -> 跨产物真实实例化形态的宿主表达
    #  §17.40 产物里**实际出现过的名域**（`名域 细节stdext {` 这种）。用途：内部件名不一定住在
    #  `标准::细节`，实测 `检查数组迭代器`/`未检查数组迭代器` 住在 `标准::细节stdext` —— 只会拼
    #  `标准::细节::<名>` 的话，编译器给的正解（`细节stdext::检查数组迭代器`）也用不上 ✗。
    #  ⚠ 只是"候选"：拼错的名域编不过是无害失败，而且**全程不出这个产物**，没有跨产物包含的污染风险。
    $nss = @()
    if ($ptxt) {
        foreach ($mm in [regex]::Matches($ptxt, '(?m)^\s*名域\s+([\w\u4e00-\u9fff]+)\s*\{')) {
            $nsn = $mm.Groups[1].Value
            if ($nsn -ne '标准' -and $nss -notcontains $nsn) { $nss += $nsn }
        }
    }
    if (($p.Value.PSObject.Properties.Name -contains 'types') -and $p.Value.types) {
        foreach ($k in $p.Value.types.PSObject.Properties) {
            $v = [string]$k.Value
            if ((Test-ZhName $v) -and -not $v.StartsWith('_')) {
                $names += [pscustomobject]@{ Name = $v; Kind = '内部实现类'; Template = '' }
                #  内部件多半是**类模板**：`标准::细节::映射实现` 不是类型，得带实参（§17.23）。
                #  实参**从产物正文里精确取**（`模板 <…> 类型 映射实现 : …`），不靠猜个数：
                $ia = Get-ImplArgsFromText $ptxt $v
                #  §17.39 实参取不到分两种：**形参全有默认值**（`屏障实现<_完成函数 = 默认>`）
                #  -> 正解是 `标准::细节::$v<>`；或是真没解析出来 -> 那也是一条无害候选。
                #  以前退化成**裸名**（不是类型，必失败）✗。
                $hostImps += $(if ($ia) { "标准::细节::$v<$ia>" } else { "标准::细节::$v<>" })
                $implArgs[$v] = $ia
                #  §17.27 这个成员 typedef 的**真实宿主**（静态推断，零编译）
                $eh = Get-EnclosingHost $ptxt $v
                if ($eh) {
                    $memberHost[$v] = $eh
                    #  §17.32 该宿主的**跨产物真实实参**：多候选（`_哈希` 在库里是两个不同的类，
                    #  「第一个命中」会抓错），每条带上它被找到的那个产物（探针 TU 要引它才看得见 traits 类）
                    if ($script:InstMap.ContainsKey($eh.Class)) {
                        $cands = @()
                        foreach ($ic in @($script:InstMap[$eh.Class])) {
                            $sub = Get-SubstitutedArgs ([string]$ic.Text)
                            #  §17.39 同上一处：`$sub` 为空说明这里抓到的宿主是**全默认形参**模板
                            #  -> `宿主<>` 才是合法拼写（以前直接跳过，等于这条候选不存在）✗。
                            if ($sub) { $cands += @{ Expr = ("标准::细节::" + $eh.Class + "<" + $sub + ">"); Product = [string]$ic.Product } }
                            else { $cands += @{ Expr = ("标准::细节::" + $eh.Class + "<>"); Product = [string]$ic.Product } }
                        }
                        if ($cands.Count) { $memberHostCross[$v] = $cands }
                    }
                }
            }
        }
    }
    #  手写层（extra/deriveExtra/prologue）里提的名字：既有**顶层自由函数**（复数/C数学 的
    #  `常用对数`/`反余弦`），也有**嵌套成员名**（`基类`/`常量反向迭代器`）。
    #  §17.22 起不再**一律**记成"手写层"黑洞（那样这些名字连一次编译都没过）：
    #  保留它**自己是什么**（Inner），顶层先按那个探针真试一次，试不过才软记账为
    #  「手写层·X：顶层试不过（嵌套成员/需宿主实参）」—— 账要能看出"差在哪一步"。
    foreach ($field in 'extra', 'deriveExtra', 'prologue', 'deriveTypes') {
        if (($p.Value.PSObject.Properties.Name -contains $field) -and $p.Value.$field) {
            foreach ($n2 in (Get-NamesFromCode ([string]$p.Value.$field))) {
                $names += [pscustomobject]@{ Name = $n2.Name; Kind = '手写层探针'; Inner = $n2.Kind; Template = $n2.Template; Raw = $n2.Raw }
            }
        }
    }
    $tests = ''
    if (($p.Value.PSObject.Properties.Name -contains 'tests') -and $p.Value.tests) { foreach ($tc in $p.Value.tests) { $tests += ([string]$tc[1]) + "`n" } }
    $products += [pscustomobject]@{ Track = '深度'; Product = $zh; TParam = $tp; Names = @($names | Sort-Object Name -Unique); Tests = $tests; HostPub = $hostPub; HostImps = @($hostImps); ImplArgs = $implArgs; MemberHost = $memberHost; MemberHostCross = $memberHostCross; Namespaces = @($nss) }
}

# ③ C 轨道（表在源码里）
#  §17.24 真实用例只在**导出**里（`t` 字段，见 make_zhc.ps1 的 $TESTS）—— 正文正则取不到，
#  所以单独调一次 -ExportJson 建映射。（正文正则仍是名字的来源，不动它。）
$ctestMap = @{}
$cj = & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhc.ps1') -ExportJson 2>$null | Out-String
if ($cj.Trim()) {
    $ctab = $cj | ConvertFrom-Json
    foreach ($pp in $ctab.PSObject.Properties) {
        if (($pp.Value.PSObject.Properties.Name -contains 't') -and $pp.Value.t) { $ctestMap[[string]$pp.Value.zh] = [string]$pp.Value.t }
    }
}
$ctext = [System.IO.File]::ReadAllText((Join-Path $root 'tools\make_zhc.ps1'))
foreach ($em in [regex]::Matches($ctext, "(?ms)^\s*'([a-z_][a-z0-9_.]*)'\s*=\s*@\{\s*zh\s*=\s*'([^']+)'\s*;?\s*a\s*=\s*@\((.*?)\)\s*\}")) {
    $names = @()
    foreach ($nm in [regex]::Matches($em.Groups[3].Value, "@\('(\S+?)','([^']+)','([^']*)'\)")) {
        $kind = $nm.Groups[1].Value; $nm2 = $nm.Groups[2].Value
        if (-not (Test-ZhName $nm2)) { continue }
        if ($kind -eq '类型') { $names += [pscustomobject]@{ Name = $nm2; Kind = '类型'; Template = '' } }
        elseif ($kind -eq '常量') { $names += [pscustomobject]@{ Name = $nm2; Kind = '常量'; Template = '' } }
        else { $names += [pscustomobject]@{ Name = $nm2; Kind = '模板函数'; Template = '' } }
    }
    #  §17.24 C 轨道也有真实用例了（`make_zhc.ps1` 的 `$TESTS`，**编译 + 运行**）；
    #  不接进来的话，这些用例在台账上等于不存在。
    $czh = $em.Groups[2].Value
    $ctests = ''
    if ($ctestMap.ContainsKey($czh)) { $ctests = [string]$ctestMap[$czh] }
    $products += [pscustomobject]@{ Track = 'C'; Product = $czh; TParam = ''; Names = @($names | Sort-Object Name -Unique); Tests = $ctests }
}

# ⚠ pwsh -File 把逗号列表当【一个字符串】传（老坑）—— 自己拆。
if ($Only.Count) {
    $Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $products = @($products | Where-Object { $Only -contains $_.Product })
}
if ($products.Count -eq 0) { throw "实例化守卫：选中的产物数为 0（-Only 写法不对？§15.3：跑 0 条的通过不是通过）" }
}   #  §17.38 表解析块到此结束（子进程 `-ManifestFile` 时整段跳过）

# ---------------------------------------------------------------------------
#  生成探针并编译运行
# ---------------------------------------------------------------------------
#  ⚠ §17.38：**子进程绝不能清 work 目录** —— 那会把兄弟分片的探针和日志一起删掉。
$isChild = [bool]$PartialOut
if (-not $isChild) {
    #  §17.44 清理要**带重试 + 说清原因**（用户 2026-10-02 实测的健壮性问题）：
    #    他跑重型守卫时工具调用超时了，但**超时只杀了工具调用、没杀子进程** —— 那个 check_zhinst -Check
    #    继续在后台跑了十几分钟，留下 4 个 chinese++ 子进程和 1900 多个临时文件；于是下一次
    #    `Remove-Item -Recurse -Force` 撞上文件占用，脚本在"准备阶段"以退出码 1 死掉，
    #    **错误信息看起来像"守卫/台账失败"，实际只是环境脏了** ✗ —— 这种误导必须消掉。
    if (Test-Path $work) {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
        for ($try = 1; $try -le 3 -and (Test-Path $work); $try++) {
            Start-Sleep -Milliseconds 1500
            Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
        }
        if (Test-Path $work) {
            $busy = @(Get-Process -Name 'chinese++', 'clang', 'clang-cl' -ErrorAction SilentlyContinue)
            throw ("实例化守卫：清不掉工作目录 {0} —— 上一次运行很可能还在跑（残留编译器进程 {1} 个）。" +
                   "请先结束它（Get-Process chinese++,clang,clang-cl | Stop-Process）再重跑。" +
                   "★ 这不是台账或产物的问题，也不是守卫失败 —— 是环境脏了。") -f $work, $busy.Count
        }
    }
}
New-Item -ItemType Directory -Force $work | Out-Null

# ---------------------------------------------------------------------------
#  §17.38 分片并行：为什么要有它
#    实测（§17.37 那一轮）：1164 个名字、116 个产物，**串行**要 20 分钟；
#    而闸门里要跑**两遍**（第一遍写台账，第二遍 -Check 证明可复算）→ 光守卫就 40 分钟。
#    这违背"护栏要能天天跑"的前提。处置：把产物切成 N 片，各起一个进程并行跑，
#    再按 0..N-1 顺序合并 —— 判据一条不动，只是把"串行等"换成"并行等"。
#
#    三条不变量（缺一条就不许并行）：
#      ① **分片必须连续**（第 i 片 = 第 [i*per, (i+1)*per) 个产物）：这样父进程按序合并出来的
#         行序与串行**逐字节一致**，台账仍可自证（跑完 `git diff` 台账必须为空）。
#      ② **子进程不写台账、不打总结**：只把自己那一片的账交给父进程（`-PartialOut`）。
#      ③ **跑 0 条不算通过**：父进程自己不再跑产物，所以 `$rows`/`$failAll` 全部来自分片；
#         任何一片没产出就直接 `throw`（不是"少一片也绿"）。
# ---------------------------------------------------------------------------
$shardMerged = $false
if ($ManifestFile) { $products = @(Import-Clixml -Path $ManifestFile) }   # 子进程：吃父进程建好的清单
#  §17.40 产物名 -> 它的**公开宿主表达式**（`标准::映射<整数, 整数>` 这种）。
#  用途：内部件的成员 typedef 在**公开容器**里常同名存在（`映射<整数,整数>::常量引用` 实测存在 ✓），
#  而 `细节::_树值<整数>::常量引用` 会因为 `整数` 不是 traits 类而必失败 ✗。
#  ⚠ 必须在**分片过滤之前**建：跨产物宿主指向的那个产物可能不在本分片里。
#  §17.40 这里曾建过"产物 -> 公开宿主表达式"的映射，用来给内部件成员出"公开容器宿主"候选。
#  实验证明这条路会污染探针 TU（详见 内部实现类 分支里的实验记录），已**撤回**；映射一并删掉。
if ($Shards -le 0) { $Shards = [Math]::Min(12, [Environment]::ProcessorCount) }
if ($Shards -gt 1 -and -not $isChild) {
    $manifestPath = Join-Path $work 'products.xml'
    @($products) | Export-Clixml -Path $manifestPath -Depth 8
    $self = (Get-Process -Id $PID).Path
    $procs = @(); $partFiles = @()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($si = 0; $si -lt $Shards; $si++) {
        $pf = Join-Path $work ("partial_{0}.xml" -f $si)
        $lg = Join-Path $work ("shard_{0}.log" -f $si)
        Remove-Item -Force $pf, $lg, ($lg + '.err') -ErrorAction SilentlyContinue
        $partFiles += $pf
        $procs += Start-Process -FilePath $self -NoNewWindow -PassThru `
            -RedirectStandardOutput $lg -RedirectStandardError ($lg + '.err') `
            -ArgumentList @('-NoProfile', '-File', $PSCommandPath, '-Quiet',
                            '-ManifestFile', $manifestPath, '-Shard', $si, '-Shards', $Shards, '-PartialOut', $pf)
    }
    $procs | ForEach-Object { $_.WaitForExit() }
    $rows = @(); $uncoveredAll = @(); $failAll = @()
    foreach ($pf in $partFiles) {
        if (-not (Test-Path $pf)) { throw ("实例化守卫：分片没产出（见 build\_zhinst\shard_*.log）：{0}" -f $pf) }
        $pp = Import-Clixml -Path $pf
        $rows += @($pp.Rows); $uncoveredAll += @($pp.Uncovered); $failAll += @($pp.Fail)
    }
    $sw.Stop()
    if (-not $Quiet) { Write-Host ("  §17.38 分片并行：{0} 片，{1:N1} 分钟（串行约 20 分钟）" -f $Shards, $sw.Elapsed.TotalMinutes) }
    $shardMerged = $true   # 让下面那行初始化不要再把合并好的账清掉
    $products = @()   # 父进程自己不再跑（账全部来自分片）
} elseif ($Shards -gt 1) {
    $n = $products.Count
    $per = [Math]::Ceiling($n / [double]$Shards)
    $from = [int]($Shard * $per)
    $to = [Math]::Min($n, [int](($Shard + 1) * $per)) - 1
    $products = @(if ($from -lt $n -and $from -le $to) { $products[$from..$to] } else { @() })
    if (-not $Quiet) { Write-Host ("  分片 {0}/{1}：{2} 个产物" -f $Shard, $Shards, $products.Count) }
}

#  ⚠ §17.38 踩过的坑：这行初始化**必须在分片合并之后**才不会再执行 ——
#  第一版把合并写在它前面，于是合并好的账当场被清成 0 条（报「一个名字都没提出来」）✗。
if (-not $shardMerged) { $rows = @(); $failAll = @(); $uncoveredAll = @() }
foreach ($p in $products) {
    $items = @(); $probed = @(); $byTest = @(); $uncovered = @{}; $tplItems = @(); $needInc = @()
    $nid = 0   # §17.22.1 探针变量名用**有序计数器**，不用 `GetHashCode`（每进程随机 -> 台账不可复算）
    foreach ($n in @($p.Names | Sort-Object Name -Unique)) {
        $used = $false
        if ($p.Tests -and $p.Tests -match [regex]::Escape($n.Name)) { $byTest += $n.Name; $used = $true }
        $nid++
        #  §17.37 **id 不能是纯数字**：多候选时我用「把 id 换成 id_序号」区分同名变量，
        #  纯数字 id 会把行里的字面量一起改掉 —— 实测生成过 `整数 壹1_2 = 1_2;`（`= 1;` 被改成 `= 1_2;`）✗✗。
        #  加字母前缀（`n1`）就没有这个歧义。
        $id = "n$nid"
        #  §17.21 模板函数走「合成实参真调用」探针（自成一批，见下面的 tpl 批）
        #  §17.22 手写层里的模板函数也走同一条路（它是"名字自己是什么"的一类）
        if ($n.Raw -and ($n.Kind -eq '模板函数' -or $n.Kind -eq '手写层探针')) {
            $tpn = New-TplProbe $n $id (Join-Path $out $p.Product)
            if ($tpn) {
                #  手写层名字**不判真失败**：它的调用上下文是我们合成的，错不一定在库（§17.22）
                if ($n.Kind -eq '手写层探针') { $tpn | Add-Member -NotePropertyName Soft -NotePropertyValue $true }
                $tplItems += $tpn; $probed += $n.Name; $used = $true; continue
            }
        }
        $line = $null; $line2 = $null; $line3 = $null; $line4 = $null; $line5 = $null; $line6 = $null
        switch ($n.Kind) {
            '类型' { $line = ("    {0}* 针{1} = 空指针; (空型)针{1};" -f ('标准::' + $n.Name), $id) }
            #  §17.23 内部件多半是**类模板**：`标准::细节::映射实现` 不是类型、`映射实现<整数,整数,整数,整数>` 才是。
            #  两条候选都出（裸名 + 带实参），任意一条编过即算能实例化。
            '内部实现类' {
                $line = ("    标准::细节::{0}* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id)
                $ia = ''
                if ($p.ImplArgs -and $p.ImplArgs.ContainsKey($n.Name)) { $ia = [string]$p.ImplArgs[$n.Name] }
                if ($ia) { $line2 = ("    标准::细节::{0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f $n.Name, $ia, $id) }
                #  §17.37 **全默认形参**的内部件（实测 `屏障实现<_完成函数 = 默认>`、`计数信号量实现<_Rep = ptrdiff_t>`）：
                #  Get-ImplArgsFromText 见到「有默认值」就把实参跳掉 -> $ia 为空 -> 只剩裸名候选，
                #  而裸名不是类型，必失败 ✗（这两个名字因此在台账里长期挂"未覆盖"）。
                #  正确写法是 `标准::细节::屏障实现<>`（实参表可以为空）——与 §17.26 模板别名那条同一个道理。
                #  取不到实参的原因是"全默认"或"没解析出来"，两种情况下 `<>` 都是**唯一可能编过**的形态；
                #  即使它其实不是模板，失败的只是一条候选，不会造成假绿。
                else { $line2 = ("    标准::细节::{0}<>* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id) }
                #  `types` 里混着成员 typedef（`尺寸类型`/`常量迭代器`）—— 它们不是 `细节::` 下的类，
                #  而是公开宿主的成员；一条宿主限定候选（§17.23）。公开宿主不是唯一可能
                #  （`范围` 的视图挂在 `标准::范围视图` 下），那部分由 §17.27 的"报错自带候选路径"补。
                if ($p.HostPub) { $line3 = ("    {0}::{1}* 针{2} = 空指针; (空型)针{2};" -f $p.HostPub, $n.Name, $id) }
                #  §17.32 跨产物真实实例化形态的宿主：**多候选**，每条把它所属产物加进探针包含集
                if ($p.MemberHostCross -and $p.MemberHostCross.ContainsKey($n.Name)) {
                    $ci9 = 0
                    foreach ($hx in @($p.MemberHostCross[$n.Name])) {
                        $ci9++
                        $items += [pscustomobject]@{ Line = ("    {0}::{1}* 针{2}x{3} = 空指针; (空型)针{2}x{3};" -f $hx.Expr, $n.Name, $id, $ci9); Name = $n.Name; Kind = $n.Kind }
                        if ($probed -notcontains $n.Name) { $probed += $n.Name }
                        $used = $true
                        if ($hx.Product -and $needInc -notcontains $hx.Product) { $needInc += $hx.Product }
                        if (([string]$hx.Expr -match '标准::向量') -and $needInc -notcontains '向量') { $needInc += '向量' }
                    }
                }
                if ($p.MemberHost -and $p.MemberHost.ContainsKey($n.Name)) {
                    $mh = $p.MemberHost[$n.Name]
                    $ha2 = [string]$mh.Args
                    #  §17.39 同前两处：全默认形参的宿主写成 `宿主<>`（以前是裸名，必失败）✗
                    $line4 = ("    标准::细节::{0}{1}::{2}* 针{3} = 空指针; (空型)针{3};" -f $mh.Class, $(if ($ha2) { "<$ha2>" } else { '<>' }), $n.Name, $id)
                }
                #  §17.40 **实验记录（已撤回，别再做）**：试过"同一个中文名在别的产物的公开宿主上"这条
                #  候选（`标准::映射<整数,整数>::常量引用` 单独编**确实能解析** ✓），实测确实销掉 5 个名字，
                #  但代价是**整批探针被打崩**：候选宿主所属产物要进探针包含集，而**跨产物 `#包含` 会污染
                #  整个 TU** —— `队列` 的自动探针 9 → **0**，`队列实现/后/基类/交换/优先队列实现` 5 个名字
                #  反过来被记成"未覆盖" ✗✗。这就是"跑 0 条的通过不是通过"要防的事，故**撤回**。
                #  消除路径：这类"内部件的成员名"改用**条目真用例**（用例 TU 是独立完整程序，可以自由包含
                #  多个产品），而不是往探针 TU 里塞别的产物。
                #  §17.40 **名域限定候选**：这个产物里实际出现过的名域各来一条（上限 4 条）。
                #  实测 `检查数组迭代器`/`未检查数组迭代器` 住在 `标准::细节stdext` —— 只会拼
                #  `标准::细节::<名>` 时，连编译器给出的正解都用不上 ✗。名域错 = 无害失败，
                #  而且它**全程在本产物内**，没有跨产物包含那种污染风险。
                if (($p.PSObject.Properties.Name -contains 'Namespaces') -and @($p.Namespaces).Count) {
                    $ni = 0
                    $iaNs = ''
                    if ($p.ImplArgs -and $p.ImplArgs.ContainsKey($n.Name)) { $iaNs = [string]$p.ImplArgs[$n.Name] }
                    foreach ($nsq in @($p.Namespaces)) {
                        $ni++
                        if ($ni -gt 3) { break }
                        #  ⚠ 名域**可能开在全局**（实测 `名域 细节stdext {` 不在 `标准::` 下 ——
                        #  `标准::细节stdext::X` 报「不是类、名域或枚举」✗，而编译器给的正解
                        #  `细节stdext::检查数组迭代器` 恰恰是**不带 `标准::` 前缀**的那个 ✓）。
                        #  所以两种前缀都出，让编译器裁决。
                        foreach ($pre in @('标准::', '')) {
                            $items += [pscustomobject]@{ Line = ("    {0}{1}::{2}* 针{3}s{4} = 空指针; (空型)针{3}s{4};" -f $pre, $nsq, $n.Name, $id, $ni); Name = $n.Name; Kind = $n.Kind }
                            #  §17.40 名域里的名字多半也是**类模板**：`检查数组迭代器<_Ptr>` 必须带实参，
                            #  裸名不是类型 ✗（实参取不到就给 `<>`，见 §17.37/§17.39 同一条口径）。
                            $items += [pscustomobject]@{ Line = ("    {0}{1}::{2}{3}* 针{4}s{5} = 空指针; (空型)针{4}s{5};" -f $pre, $nsq, $n.Name, $(if ($iaNs) { "<$iaNs>" } else { '<>' }), $id, $ni); Name = $n.Name; Kind = $n.Kind }
                        }
                        if ($probed -notcontains $n.Name) { $probed += $n.Name }
                        $used = $true
                    }
                }
            }
            '模板类型' { $line = Get-AliasProbeLine $n $id; $line2 = $script:AliasSlot2; $line5 = $script:AliasSlot3 }
            #  §17.26 形参**全带默认值**的模板别名（`模板 <类型名 值类型 = 空型> 使用 按位与 = std::bit_and<值类型>;`）
            #  以前 `Get-TemplateArgs` 返回 $null -> 一条探针都不出（36 个名字整片记「无探针」）。
            #  正确写法是 `标准::按位与<>`（空实参表合法）—— 实测能编。
            '模板别名' { $line = Get-AliasProbeLine $n $id; $line2 = $script:AliasSlot2; $line5 = $script:AliasSlot3 }
            '常量' { $line = ("    (空型)标准::{0};" -f $n.Name) }
            '函数' { $line = ("    自动 针f{0} = &标准::{1}; (空型)针f{0};" -f $id, $n.Name) }
            #  §17.22 概念探针：概念求值对任何实参都良构（不满足只求值为 false），
            #  所以"合成实参 + 求值一次"就是真实的实例化检查。
            '概念' {
                $a = Get-TemplateArgs $n.Template
                $arg = if ($n.Template) { '<' + $(if ($a) { $a } else { '' }) + '>' } else { '' }
                $line = ("    (空型)标准::{0}{1};" -f $n.Name, $arg)
            }
            #  §17.22 手写层名：先按它**自己是什么**在顶层试一次；试不过再软记账（嵌套成员要宿主）
            #  §17.23 同时出一条**宿主限定**候选：`标准::映射<整数, 整数>::尺寸类型` ——
            #    深轨道的这些名字本来就活在类体里（`类型 映射 : 公开 细节::映射实现<…>`），
            #    顶层当然找不到；以前这一整批只有一句"需宿主"，从没真试过宿主形态。
            '手写层探针' {
                switch ($n.Inner) {
                    '类型' { $line = ("    标准::{0}* 针{1} = 空指针; (空型)针{1};" -f $n.Name, $id) }
                    '模板别名' { $a = Get-TemplateArgs $n.Template; if ($a) { $line = ("    标准::{0}<{1}>* 针{2} = 空指针; (空型)针{2};" -f $n.Name, $a, $id) } }
                    '常量' { $line = ("    (空型)标准::{0};" -f $n.Name) }
                    '函数' { $line = ("    自动 针f{0} = &标准::{1}; (空型)针f{0};" -f $id, $n.Name) }
                }
                if ($p.HostPub) {
                    $line2 = (Get-NestedLine $p.HostPub $n $id)
                    #  §17.36 再补一条**类型形态**：基类 这种是派生类里的嵌套 typedef（不是函数、也不是
                    #  标准的 @('类型') 登记），只有 宿主::基类* 针 这种写法才证得了它存在（实测能编）。
                    $line6 = ("    {0}::{1}* 针{2}t = 空指针; (空型)针{2}t;" -f $p.HostPub, $n.Name, $id)
                    #  §17.35 **成员调用探针**：`擦除`/`查找`/`清空`/`交换`/`后` 这些是**派生层的成员函数**
                    #  （形如 `返回 基类::erase(...)`），顶层不存在 —— 只有拿一个**真实例**去调才算"真用一次"。
                    #  实参形状试三种：0 元 / 1 元（整数）/ 1 元（同类实例，给 `交换`）。任意一条编过即算。
                    if ($n.Inner -eq '函数' -or $n.Inner -eq '模板函数') {
                        $H = $p.HostPub
                        $line3 = ("    自动 探a{0} = [](){{ {1} 甲{0}{{}}; 甲{0}.{2}(); }}; (空型)探a{0};" -f $id, $H, $n.Name)
                        $line4 = ("    自动 探b{0} = [](){{ {1} 甲{0}{{}}; 整数 壹{0} = 1; 甲{0}.{2}(壹{0}); }}; (空型)探b{0};" -f $id, $H, $n.Name)
                        $line5 = ("    自动 探c{0} = [](){{ {1} 甲{0}{{}}; {1} 乙{0}{{}}; 甲{0}.{2}(乙{0}); }}; (空型)探c{0};" -f $id, $H, $n.Name)
                    }
                }
            }
            #  §17.22 别名 `函数` 形与 C 轨道的**变参转发器**：形状是固定的
            #  （`模板 <类型名... 参数> 声明类型(自动) 名(参数&&... 值) { 返回 std::英文(值...); }`），
            #  唯一未知的是**实参个数** -> 一元/二元各出一条候选，任意一条编过即算"能调用"。
            #  调用写在永不被调用的 lambda 里：C 轨道的包装器（`取字符串长度`(空指针) 之类）
            #  不能在探针进程里真跑，但"能实例化调用"正是要证的那件事。
            '模板函数' {
                foreach ($arity in 1, 2) {
                    $callArgs = $(if ($arity -eq 1) { "壹$id" } else { "壹$id, 壹$id" })
                    $ln = "    自动 探$arity$id = [](){ 整数 壹$id = 1; 标准::$($n.Name)($callArgs); };`n    (空型)探$arity$id;"
                    $items += [pscustomobject]@{ Line = $ln; Name = $n.Name; Kind = $n.Kind }
                }
                $probed += $n.Name; $used = $true
            }
        }
        #  ⚠ 同一名字可能有多条候选（裸名 / 带实参 / 宿主限定），它们会**同处一个 TU** ——
        #    变量名必须逐条区分，否则 `针<id>` 重定义（实测：6 个产物因此编不过）。
        $ci = 0
        foreach ($ln in @($line, $line2, $line3, $line4, $line5, $line6)) {
            if ($ln) {
                $ci++
                #  §17.37 只替换**标识符里的 id**（`针n1` -> `针n1_2`），不碰数字里长得像 id 的片段。
                #  id 现在带字母前缀，撞字面量已经不可能；这里再补一层数字边界，防止 `n1` 命中 `n12`。
                $idE2 = [regex]::Escape([string]$id)
                $lnx = $(if ($ci -eq 1) { $ln } else { ([string]$ln) -replace ("(?<![0-9])$idE2(?![0-9])", "$id`_$ci") })
                #  §17.27 合成实参里可能用到**别的中文头**（视图要 `标准::向量<整数>`、引擎要
                #  `标准::默认随机引擎`、复数见证要 `标准::复数`）—— 探针 TU 必须把它引进来，
                #  否则实参类型本身没定义，报错会伪装成"这个名字不行"（实测白丢一批）。
                if ($lnx -match '标准::向量' -and $needInc -notcontains '向量') { $needInc += '向量' }
                if ($lnx -match '默认随机引擎' -and $needInc -notcontains '随机') { $needInc += '随机' }
                if ($lnx -match '标准::复数' -and $needInc -notcontains '复数') { $needInc += '复数' }
                $items += [pscustomobject]@{ Line = $lnx; Name = $n.Name; Kind = $n.Kind }
                #  §17.37 **引用类型不能用指针探**：`常量引用` = `const 整数&`，写 `X* 针` 就是
                #  「指向引用的指针」，编不过 —— 而名字其实**解析出来了**（实测报错原文：
                #  `针# 被声明为指向类型为 标准::细节::集合实现<int>::常量引用 (aka const int &) 的引用的指针`）。
                #  别名声明 `使用 针a = X;` 对**任何**类型都合法（引用/数组/函数/void），
                #  而且同样证明"这个名字是个类型" —— 多一条候选，任意一条编过即算覆盖。
                $am = [regex]::Match($lnx, '^\s*(.+?)\*\s*针([A-Za-z0-9_]+)\s*=\s*空指针;\s*\(空型\)针\2;\s*$')
                if ($am.Success) {
                    $items += [pscustomobject]@{ Line = ("    使用 针a{0} = {1};" -f $am.Groups[2].Value, $am.Groups[1].Value.Trim()); Name = $n.Name; Kind = $n.Kind }
                }
                $probed += $n.Name; $used = $true
            }
        }
        if (-not $used) {
            $uncovered[$n.Name] = $(if ($n.Kind -eq '手写层探针') { '手写层·' + $n.Inner + '：顶层' + $(if ($p.HostPub) { '与宿主限定（`' + $p.HostPub + '::' + $n.Name + '`）' } else { '' }) + '都试不过' }                elseif ($n.Kind -eq '概念') { '概念：模板实参合成不出来（形参有默认值依赖等）' }
                else { $n.Kind + '-无探针' })
        }
    }
    $compiled = $null; $ran = $null
    if ($env:ZHINST_DUMP) { foreach ($it in @($items) + @($tplItems)) { Write-Host ("  [DUMP {0} | {1}] {2}" -f $p.Product, $it.Name, (([string]$it.Line) -replace "`n", ' ')) } }
    $safe = ($p.Product -replace '[\\/:*?"<>|]', '_')
    #  §17.20 阶段(5)：**C++23 条件壳**的分支要用 C++23 编（产品里有 `#如果 _HAS_CXX23`
    #  就说明它的名字只在 C++23 下存在）—— 这正是"壳的分支只有人工探针"那条欠账的机器化。
    $prodFile = Join-Path $out $p.Product
    $stdFlag = '-std=c++20'
    if ((Test-Path $prodFile) -and ([System.IO.File]::ReadAllText($prodFile) -match '_HAS_CXX23')) { $stdFlag = '-std=c++23' }
    $extraInc = @($needInc)   #  §17.27：合成实参用到的中文头（向量/随机/复数）要引进来
    function Invoke-Probe([string[]] $lines, [string] $tag) {
        $src = Join-Path $work ("p_$safe$tag.cpp"); $exe = Join-Path $work ("p_$safe$tag.exe")
        $inc = "#包含 <$($p.Product)>`n"
        foreach ($e in @($extraInc)) { if ($e) { $inc += "#包含 <$e>`n" } }
        #  §17.31 **见证结构**：视图类模板要"真可调用"的类型实参（一元谓词/函数、二元比较都可能），
        #  而 lambda 类型没法写进类型位置。这个结构两个重载都带上，两边都能满足。
        $inc += "结构 通用见证 { 布尔 运算符()(整数 值) 常量 { 返回 真值; } 布尔 运算符()(整数 左, 整数 右) 常量 { 返回 左 < 右; } };`n"
        $code = $inc + "整数 主函数(){`n" + ($lines -join "`n") + "`n    返回 0;`n}`n"
        [System.IO.File]::WriteAllText($src, $code, $utf8)
        & cmd /c "`"$cxx`" $stdFlag -isystem`"$out`" `"$src`" -o `"$exe`" > `"$work\o_$safe$tag.txt`" 2>&1"
        $cc = $LASTEXITCODE
        $rc = -1
        if ($cc -eq 0) { & $exe; $rc = $LASTEXITCODE }
        $errLines = @(Get-Content "$work\o_$safe$tag.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' })
        $firstErr = ''
        if ($errLines.Count -gt 0) { $firstErr = ([string]$errLines[0]).Trim() }
        return [pscustomobject]@{ CC = $cc; RC = $rc; Err = $firstErr }
    }
    #  二分找出编不过的条目 —— 整批编不过时避免逐个编（条目多时省成倍时间）
    function Find-BadItems([object[]] $list, [string] $tag) {
        $bad = @(); $queue = New-Object System.Collections.ArrayList
        [void]$queue.Add(@($list))
        while ($queue.Count -gt 0) {
            $g = @($queue[0]); $queue.RemoveAt(0)
            if ($g.Count -eq 0) { continue }
            if ($g.Count -eq 1) {
                $r = Invoke-Probe @($g[0].Line) ('_' + $tag + (Get-StableId $g[0].Name))
                if ($r.CC -ne 0) { $bad += $g[0] }
                continue
            }
            $r = Invoke-Probe @($g | ForEach-Object { $_.Line }) ('_' + $tag + 'G' + (Get-StableId $g[0].Name))
            if ($r.CC -ne 0) {
                $h = [int][Math]::Floor($g.Count / 2)
                [void]$queue.Add(@($g[0..($h - 1)]))
                [void]$queue.Add(@($g[$h..($g.Count - 1)]))
            }
        }
        return $bad
    }
    if ($items.Count) {
        $r0 = Invoke-Probe @($items | ForEach-Object { $_.Line }) ''
        if ($r0.CC -ne 0) {
            #  §17.20 判责规则：**按名字类别 + 报错性质**，不按报错位置。
            #    · 模板类型 / 模板别名 / 内部实现类：实参是我们**合成**的（`整数`/`1`），
            #      对"默认形参依赖前一个形参"的模板（`时间点<时钟, 时长 = 时钟::duration>`）
            #      哑实参天然不适用 -> 记「未覆盖（探针不可表达）」并从批量里剔掉，**不判库失败**。
            #    · 函数：**重载**取地址有歧义（`存在`/`当前路径` 各有多个重载）-> 同样记
            #      「未覆盖（重载函数：需具体实参）」，不判库失败。
            #    · 类型 / 常量（不需要实参）：编不过就是**库/表自己的问题** -> 真失败。
            $badLines = @(); $softNames = @{}; $okNames = @{}
            foreach ($it in $items) {
                $ri = Invoke-Probe @($it.Line) ('_n' + (Get-StableId $it.Name))
                if ($ri.CC -eq 0) { $okNames[$it.Name] = $true; continue }
                #  §17.27 **报错自带候选路径**：编译器对这类名字会说
                #  「namespace '标准' 中没有名为 '变换视图' 的类型；你是不是想写（类型名）'标准::范围视图::变换视图'？」
                #  —— 拿它再试一次（1 次编译/名字）。这条把"宿主不是公开宿主"的那批救回来，
                #  而且**不靠我们猜宿主**：路径是编译器自己给的。
                $sm = [regex]::Match([string]$ri.Err, '你是不是想写[^'']*''([^'']+)''')
                if ($sm.Success) {
                    $sug = $sm.Groups[1].Value
                    #  §17.40 探针行里的限定路径**不一定是 `标准::<名>`**：内部件探针写的是
                    #  `标准::细节::<名>`，老写法 `Replace('标准::' + 名, 建议)` 根本替换不上 ✗
                    #  —— 实测 `检查数组迭代器`：编译器自己给出正解 `细节stdext::检查数组迭代器`，
                    #  却因为这段替换空转而被记成"未覆盖"，白丢。
                    #  改成按"名字前面的整段限定符"替换（`[\w\u4e00-\u9fff:]*` 贪婪吃掉 `标准::细节::`）。
                    #  用 Remove/Insert 而不是 `-replace`：建议路径里若含 `$` 不会被当替换变量 ✗。
                    $pm2 = [regex]::Match([string]$it.Line, '[\w\u4e00-\u9fff:]*(?<![\w\u4e00-\u9fff])' + [regex]::Escape($it.Name))
                    $lnS = [string]$it.Line
                    if ($pm2.Success) { $lnS = $lnS.Remove($pm2.Index, $pm2.Length).Insert($pm2.Index, $sug) }
                    if ($lnS -ne [string]$it.Line) {
                        $riS = Invoke-Probe @($lnS) ('_s' + (Get-StableId $sug))
                        #  ⚠ §17.37：名字**换一条形态**编过了，但**原来那条编不过的候选不能留在合批里** ——
                        #  否则合批必炸，还会被报成「真失败」（实测 `惰性切分`：建议路径通了，
                        #  原始 `标准::惰性切分(...)` 仍留在批里 -> 整个产物判失败）。
                        #  进 $badLines = 从合批剔除；**不进 $softNames** = 不算未覆盖。
                        if ($riS.CC -eq 0) { $okNames[$it.Name] = $true; $badLines += $it.Line; continue }
                        #  §17.31 候选路径多半是 **CPO**（`标准::范围视图::切分`）——它们要**范围**当实参，
                        #  整数哑实参天然不匹配。把哑实参换成真容器（向量）再试；
                        #  二元 CPO 的**第二实参**可能是函数（变换/过滤/切分）也可能是整数（取前/丢弃前），
                        #  两种形状都试（1 次编译/形状）。
                        $idE = [regex]::Escape([string]$id)
                        $variants = @()
                        if ($lnS -match ('壹' + $idE + ',\s*壹' + $idE)) {
                            $variants += ($lnS -replace ('壹' + $idE + ',\s*壹' + $idE), ('范' + [string]$id + ', 通用见证()'))
                            $variants += ($lnS -replace ('壹' + $idE + ',\s*壹' + $idE), ('范' + [string]$id + ', 壹' + [string]$id))
                        } elseif ($lnS -match ('壹' + $idE)) {
                            $variants += ($lnS -replace ('壹' + $idE), ('范' + [string]$id))
                        }
                        foreach ($lv in $variants) {
                            $lnR = ([string]$lv).Replace('[](){ ', ("[](){ 标准::向量<整数> 范$id{}; "))
                            if ($lnR -eq $lnS) { continue }
                            $savedInc = @($extraInc)
                            if ($savedInc -notcontains '向量') { $extraInc = $savedInc + @('向量') }
                            $riR = Invoke-Probe @($lnR) ('_r' + (Get-StableId ($sug + $lnR.Length)))
                            $extraInc = $savedInc
                            if ($riR.CC -eq 0) { $okNames[$it.Name] = $true; break }
                        }
                        if ($okNames.ContainsKey($it.Name)) { $badLines += $it.Line; continue }
                        #  §17.37 范围 CPO 的真实形状还有 **(迭代器/范围, 个数)** 这种**两实参**形态
                        #  （`取前(组, 壹)` / `丢弃前(组, 壹)` / `计数(组, 壹)`），而合成见证可能只造出
                        #  一个整数，于是"见证形状不对"被记成"未覆盖"。只对**编译器亲自给出的**
                        #  `标准::范围视图::*` 路径补这两条形状（成本受控：仅这类名字、仅前几条失败后）。
                        if ($sug -like '标准::范围视图::*') {
                            $cpoShapes = @(
                                ("    自动 探k{0} = [](){{ 整数 组{0}[8]{{}}; 整数 壹{0} = 1; {1}(组{0}, 壹{0}); }}; (空型)探k{0};" -f $id, $sug),
                                ("    自动 探m{0} = [](){{ 标准::向量<整数> 范{0}{{}}; 整数 壹{0} = 1; {1}(范{0}, 壹{0}); }}; (空型)探m{0};" -f $id, $sug)
                            )
                            $si = 0
                            foreach ($cs in $cpoShapes) {
                                $si++
                                $savedInc2 = @($extraInc)
                                if ($cs -match '标准::向量' -and $savedInc2 -notcontains '向量') { $extraInc = $savedInc2 + @('向量') }
                                $riC = Invoke-Probe @($cs) ('_c' + (Get-StableId ($sug + 'sh' + $si)))
                                $extraInc = $savedInc2
                                if ($riC.CC -eq 0) { $okNames[$it.Name] = $true; break }
                            }
                            if ($okNames.ContainsKey($it.Name)) { $badLines += $it.Line; continue }
                        }
                    }
                }
                $soft = $false; $why = ''
                if ($it.Kind -in @('模板类型', '模板别名', '内部实现类')) { $soft = $true; $why = '探针不可表达（合成实参不适用）：' + (Get-ErrBrief $ri.Err) }
                elseif ($it.Kind -eq '函数' -and ($ri.Err -match 'overloaded|重载')) { $soft = $true; $why = '探针不可表达（重载函数：需具体实参）' }
                #  §17.22：手写层名与概念都是"我们替它合成上下文"，编不过**不判库失败**
                elseif ($it.Kind -eq '手写层探针') { $soft = $true; $why = '手写层·' + $it.Inner + '：顶层试不过（嵌套成员/需宿主实参）' }
                elseif ($it.Kind -eq '概念') { $soft = $true; $why = '概念：模板实参合成不出来（形参默认值依赖等）' }
                elseif ($it.Kind -eq '模板函数') { $soft = $true; $why = '变参转发器：一元/二元实参都试过，都编不过' }
                if ($soft) { $badLines += $it.Line; $softNames[$it.Name] = $why }
                else { $failAll += ("  [{0}] 探针编不过（{1}：{2}）：{3}" -f $p.Product, $it.Kind, $it.Name, $ri.Err) }
            }
            $items = @($items | Where-Object { $badLines -notcontains $_.Line })
            #  §17.22 **任意一条候选编过就算这个名字能调用** —— 同一名字可能有多条候选
            #  （变参转发器的一元/二元形态），只有"条条都编不过"才记未覆盖。
            foreach ($nm in $softNames.Keys) {
                if (-not $okNames.ContainsKey($nm)) {
                    #  §17.24 已被**真用例**覆盖的名字不再记未覆盖：用例真编译真运行（§17.19.58），
                    #  它已经不是"边界"。以前这里无条件记 —— 于是同一个名字既在"用例覆盖"里
                    #  又在"未覆盖"里（C 轨道补了 8 条用例后立刻暴露：48 覆盖 / 41 未覆盖）。
                    if ($byTest -notcontains $nm) { $uncovered[$nm] = $softNames[$nm] }
                    $probed = @($probed | Where-Object { $_ -ne $nm })
                }
            }
            if ($items.Count) { $r0 = Invoke-Probe @($items | ForEach-Object { $_.Line }) '' }
            else { $r0 = [pscustomobject]@{ CC = 0; RC = 0; Err = '' } }
        }
        $compiled = $r0.CC; $ran = $r0.RC
        if ($compiled -ne 0) { $failAll += ("  [{0}] 探针编不过：{1}" -f $p.Product, $r0.Err) }
        elseif ($ran -ne 0) { $failAll += ("  [{0}] 探针运行返回 {1}" -f $p.Product, $ran) }
    } else { $compiled = 0; $ran = 0 }
    # -----------------------------------------------------------------------
    #  §17.21 模板函数批：合成实参真调用（A 级）+ 显式模板实参（B 级）
    #    · 调用写在**永不被调用的 lambda** 里 -> 证明的是"能实例化调用"，不把算法
    #      的 UB 引进探针进程（探针 exe 仍要真跑，跑的是主批）
    #    · 整批编过 = 这批名字都调用得通；整批编不过 -> 二分找出编不过的，逐个定性
    #    · 判真失败的唯一条件：B 级报错**正落在这个名字自己的定义行** = 签名有病
    # -----------------------------------------------------------------------
    if ($tplItems.Count) {
        $extraInc = @()
        foreach ($ti in $tplItems) { foreach ($e in $ti.ExtraInc) { if ($extraInc -notcontains $e) { $extraInc += $e } } }
        $rT = Invoke-Probe @($tplItems | ForEach-Object { $_.Line }) '_t'
        if ($rT.CC -ne 0) {
            foreach ($it in @(Find-BadItems $tplItems 't')) {
                $id = Get-StableId $it.Name
                $ri = Invoke-Probe @($it.Line) ('_t' + $id)
                if ($ri.CC -eq 0) { continue }   # 单独编过：整批失败是别的名字拖累的
                $why = "调用探针编不过：$(Get-ErrBrief $ri.Err)"
                if ($it.LineB) {
                    $bi = Invoke-Probe @($it.LineB) ('_b' + $id)
                    if ($bi.CC -eq 0) { continue }   # 显式模板实参能调 -> 仍算"能调用"
                    $em = [regex]::Match([string]$bi.Err, 'zhstdlib.*?:(\d+):')
                    #  §17.22：手写层名字（Soft）**不判真失败** —— 它的调用上下文是我们合成的，
                    #  错不一定在库；定义行命中也不足以定罪。
                    if (-not $it.Soft -and $it.DefLine -gt 0 -and $em.Success -and [int]$em.Groups[1].Value -eq $it.DefLine) {
                        $failAll += ("  [{0}] 模板函数签名病（显式模板实参下报错正落在定义行 {1}）：{2} -> {3}" -f $p.Product, $it.DefLine, $it.Name, $bi.Err)
                        continue
                    }
                    $why = $(if ($it.Soft) { '手写层·模板函数：调用探针编不过（' } else { '调用探针表达不出（显式实参也编不过）：' }) + "$(Get-ErrBrief $bi.Err)"
                }
                #  §17.24 同主批：已被真用例覆盖的名字不记未覆盖
                if ($byTest -notcontains $it.Name) { $uncovered[$it.Name] = $why }
                $probed = @($probed | Where-Object { $_ -ne $it.Name })
            }
        }
        $extraInc = @()
    }
    #  §17.22 逐名登记未覆盖：名字 + 类别 + 原因 + 消除路径（判据②：剩余项也是"有账的边界"）
    #  §17.43 再加一栏**归属**（公开 / 内部）—— 用户 2026-10-02 拍板的两栏口径。
    foreach ($k in $uncovered.Keys) {
        $kn = @($p.Names | Where-Object { $_.Name -eq $k } | Select-Object -First 1)
        $kKind = $(if ($kn.Count) { [string]$kn[0].Kind } else { '?' })
        $reason = [string]$uncovered[$k]
        $uncoveredAll += [pscustomobject]@{
            轨道 = $p.Track; 产物 = $p.Product; 名字 = $k; 类别 = $kKind; 归属 = (Get-NameScope $k)
            原因 = $reason; 分类 = (Get-ReasonClass $reason); 消除路径 = (Get-FixPath $reason $kKind)
        }
    }
    $pubUn = @($uncovered.Keys | Where-Object { (Get-NameScope $_) -eq '公开' } | Sort-Object)
    $intUn = @($uncovered.Keys | Where-Object { (Get-NameScope $_) -eq '内部' } | Sort-Object)
    $rows += [pscustomobject]@{
        轨道 = $p.Track; 产物 = $p.Product; 名字 = @($p.Names | Sort-Object Name -Unique).Count
        自动探针 = @($probed | Sort-Object -Unique).Count; 用例覆盖 = @($byTest | Sort-Object -Unique).Count
        未覆盖 = $uncovered.Count; 公开未覆盖 = $pubUn.Count; 内部未覆盖 = $intUn.Count
        编译 = $compiled; 运行 = $ran
        未覆盖名单 = ((($(if ($pubUn.Count) { '[公] ' + ($pubUn -join ' ') } else { '' })) + ' ' + ($(if ($intUn.Count) { '[内] ' + ($intUn -join ' ') } else { '' }))).Trim())
    }
}

#  §17.38 子进程：把这一片的账原样交给父进程 —— **不写台账、不打印总结**。
if ($isChild) {
    [pscustomobject]@{ Rows = @($rows); Uncovered = @($uncoveredAll); Fail = @($failAll) } |
        Export-Clixml -Path $PartialOut -Depth 8
    exit 0
}

$totNames = ($rows | Measure-Object -Property 名字 -Sum).Sum
if (-not $totNames) { throw "实例化守卫：一个名字都没提出来（表解析坏了，§15.3）" }
$totProbe = ($rows | Measure-Object -Property 自动探针 -Sum).Sum
$totTest = ($rows | Measure-Object -Property 用例覆盖 -Sum).Sum
$totUncov = ($rows | Measure-Object -Property 未覆盖 -Sum).Sum
#  §17.43 两栏口径：公开名未覆盖（**必须为 0** 才算目标完成）/ 内部名未覆盖（允许非 0，但每条带原因+消除路径）
$totPubUncov = ($rows | Measure-Object -Property 公开未覆盖 -Sum).Sum
$totIntUncov = ($rows | Measure-Object -Property 内部未覆盖 -Sum).Sum
$failProducts = @($rows | Where-Object { $_.编译 -ne 0 -or $_.运行 -ne 0 })

# ---------------------------------------------------------------------------
#  台账
# ---------------------------------------------------------------------------
$lines = @(
    '# 实例化台账（§17.20）——「每个中文名都要能被真正用起来」',
    '',
    '> 本文件由 `tools\check_zhinst.ps1` 生成，`tools\regen_zhstdlib.ps1` 用 `-Check` 守。',
    '> 名字来自**三张生成器表**（深度 / 别名 / C），不是手写清单；新增名字自动进账。',
    '> 三列口径：**自动探针** = 类型声明指针（模板按表里的 `tparam`/模板头合成实参）+ 常量读取 +',
    '> 非模板函数取地址 + §17.21 **模板函数按形参合成见证真调一次**（A 级推导调用，',
    '> A 编不过再试 B 级显式模板实参；调用写在永不被调用的 lambda 里，证明"能实例化调用"）',
    '> （每个产物编成 exe 并真跑）；**用例覆盖** = 名字出现在该条目自带用例里',
    '> （那里的用例真编译 + 真运行，见 §17.19.58）；**未覆盖** = 模板函数/概念等无法自动生成实参的名字，',
    '> 末列写明原因 —— 账要诚实显示"还缺"。**§17.22 起每个未覆盖名字都在文末逐名登记原因与消除路径**',
    '',
    ("**汇总**：名字 {0} 个；自动探针 {1}；用例覆盖 {2}；未覆盖 {3}（**公开名 {4}** / 内部名 {5}）；探针失败产物 {6} 个" -f $totNames, $totProbe, $totTest, $totUncov, $totPubUncov, $totIntUncov, $failProducts.Count),
    '',
    '> **两栏口径（§17.43，用户 2026-10-02 拍板）**：**公开名** = 用户能从 `标准::` 直接命名（`标准::X` / `标准::X<…>` /',
    '> `标准::X<…>::名` / 库公开的 `标准::名`）；**内部名** = 只能经 `标准::细节::…` 或私有成员命名 —— 单列一栏、',
    '> **不计入公开覆盖率**，但同样要有真实例化证据（不许当遮羞布）。完成判据：**公开名未覆盖 = 0**；',
    '> 内部名允许非 0，但每条必须带原因 + 消除路径。判据的由来见方案 §17.43 的四象限（原生公开而我们写不出来 = 真 bug，必须修）。',
    '',
    '| 轨道 | 产物 | 名字 | 自动探针 | 用例覆盖 | 未覆盖 | 公开未覆盖 | 内部未覆盖 | 编译 | 运行 | 未覆盖名单（原因与消除路径见下一节） |',
    '|---|---|---|---|---|---|---|---|---|---|---|'
)
foreach ($r in ($rows | Sort-Object 轨道, 产物)) {
    $lines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |" -f $r.轨道, $r.产物, $r.名字, $r.自动探针, $r.用例覆盖, $r.未覆盖, $r.公开未覆盖, $r.内部未覆盖, $r.编译, $r.运行, $r.未覆盖名单)
}

# ---------------------------------------------------------------------------
#  §17.22 未覆盖逐名台账（判据②：剩余项都带理由 + 消除路径）
# ---------------------------------------------------------------------------
$hist = @($uncoveredAll | Group-Object 分类 | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })   # 排序要全序，否则台账不可复算
$lines += ''
$lines += ('## 未覆盖逐名台账（{0} 个名字 —— 每个都有**原因**和**消除路径**）' -f $uncoveredAll.Count)
$lines += ''
$lines += '> 判据②（§17.22）：未覆盖**不是失败**，是还欠的账；但只写"未覆盖"三个字**不算登记** ——'
$lines += '> 每个名字都要写清**为什么没覆盖**与**下一步怎么销**。这一节就是下一批工作的清单。'
$lines += ''
$lines += ('**原因分布**：' + (($hist | ForEach-Object { '{0} × {1}' -f $_.Name, $_.Count }) -join '；'))
$lines += ''
$lines += '| 产物 | 名字 | 归属 | 类别 | 原因 | 消除路径 |'
$lines += '|---|---|---|---|---|---|'
foreach ($u in ($uncoveredAll | Sort-Object 归属, 分类, 产物, 名字)) {
    $rn = ([string]$u.原因) -replace '\|', '\|' -replace "`r?`n", ' '
    $fx = ([string]$u.消除路径) -replace '\|', '\|'
    $lines += ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $u.产物, $u.名字, $u.归属, $u.类别, $rn, $fx)
}
$text = ($lines -join "`r`n") + "`r`n"

if ($Check) {
    if (-not (Test-Path $ledger)) { Write-Host '❌ 实例化台账不存在：先跑 tools\check_zhinst.ps1（不带 -Check）' -ForegroundColor Red; exit 1 }
    if ([System.IO.File]::ReadAllText($ledger) -ne $text) {
        if ($env:ZHINST_DIFF) { [System.IO.File]::WriteAllText((Join-Path $work 'ledger_new.md'), $text, $utf8) }
        Write-Host '❌ 实例化台账【已过期】（产物或名字变了，但台账没重生成）' -ForegroundColor Red
        Write-Host '   修法：pwsh -NoProfile -File tools\check_zhinst.ps1  然后一起提交。' -ForegroundColor Yellow
        exit 1
    }
    if ($failProducts.Count) {
        Write-Host ("❌ 实例化探针失败 {0} 个产物：" -f $failProducts.Count) -ForegroundColor Red
        $failAll | Select-Object -First 12 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
    Write-Host ("  实例化守卫：通过（名字 {0}：自动探针 {1} / 用例覆盖 {2} / 未覆盖 {3}＝公开名 {4} + 内部名 {5}；{6} 个产物全部编过并跑过）" -f $totNames, $totProbe, $totTest, $totUncov, $totPubUncov, $totIntUncov, $rows.Count) -ForegroundColor Green
    #  §17.43 两栏口径的**醒目**提示：公开名必须为 0（绿），否则黄 —— 一眼就能看出还剩多少欠账。
    Write-Host ("    §17.43 两栏口径：公开名未覆盖 {0}（完成判据：必须为 0）／内部名未覆盖 {1}（允许非 0，须带原因与消除路径）" -f $totPubUncov, $totIntUncov) -ForegroundColor $(if ($totPubUncov -eq 0) { 'Green' } else { 'Yellow' })
    exit 0
}

if ($Only.Count -and -not $Check) {
    Write-Host '  （-Only 调试跑：不写台账，免得把全量台账覆盖成局部的）' -ForegroundColor Yellow
} else {
    [System.IO.File]::WriteAllText($ledger, $text, $utf8)
    Write-Host "  台账已写入 docs\标准库汉化\实例化台账.md"
}
Write-Host ("=== 实例化守卫（§17.20/§17.21/§17.22/§17.43）：名字 {0} 个：自动探针 {1} / 用例覆盖 {2} / 未覆盖 {3}（公开名 {4} / 内部名 {5}）===" -f $totNames, $totProbe, $totTest, $totUncov, $totPubUncov, $totIntUncov) -ForegroundColor Cyan
if ($hist.Count) {
    Write-Host '  未覆盖原因分布（下一批的清单；逐名原因 + 消除路径见台账 §未覆盖逐名台账）：'
    foreach ($h in $hist) { Write-Host ("    {0,-36} {1}" -f $h.Name, $h.Count) }
}
if ($failProducts.Count) {
    Write-Host ("❌ 探针失败 {0} 个产物：" -f $failProducts.Count) -ForegroundColor Red
    $failAll | Select-Object -First 20 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
} else {
    Write-Host ("  全部 {0} 个产物的探针都编过并跑过（返回 0）" -f $rows.Count) -ForegroundColor Green
}
exit $(if ($failProducts.Count) { 1 } else { 0 })
