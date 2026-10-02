# ============================================================================
#  audit_hanhua.ps1 -- 汉语化【欠账台账】：机器算出"到底还欠多少"
#
#  为什么必须有一个：
#    §六开头记着用户定的准绳 ——「我们最终的目的是完全翻译，现在只完成了很少，
#    是必须的妥协」，而且「每一处'暂时保留英文'都要标明它是妥协，而不是设计目标」。
#    可是"还欠多少"如果靠人记，就一定会漂移（本项目已经栽过好几次）。
#    所以把它变成一条【可复跑的机器判据】。
#
#  关键前提：产品里有两层，性质完全相反 ——
#    · 抄来那层（标准::细节）出现英文标识符 = 【欠账】
#    · 派生层（标准::）的英文标识符 = 【有意的英文兼容层】（铁律 3），必须存在
#    分不清这两层，数字就是错的（例：<互斥量> 的 `lock_guard` 是派生层有意补回的
#    英文名，不是欠账；`_Unlock_one_guard` 才是欠账）。
#    所以本脚本按生成器打下的标记行 `[ZH-DERIVE-LAYER]` 切分，
#    【只统计标记行以上】的部分 —— 那才是"抄来那层的英文残留"。
#
#  划界说明（不是遗漏，是边界）：
#    · 借用边界：`false_type` / `true_type` / `uintptr_t` 这类【真 std / CRT 的名字】，
#      出现在抄来那层是【借来用】，不是我们的名字没翻。要消灭它们，
#      必须先把提供它们的头也抄下来（步骤 1 的全部 34 个头）。
#    · 模板参数名（`_Ty` / `_Tr` / `_Outer`）与 C++ 关键字（`final`）不是"类型名"，
#      本脚本用位置判据（行首 struct/class/using 声明）已经把它们滤掉了；
#      若仍出现，说明是 `using X = ...` 形态的类内声明，需人工看一眼。
#
#  用法：powershell -File tools\audit_hanhua.ps1
#        powershell -File tools\audit_hanhua.ps1 -Verbose_   # 逐头打印残留名单
# ============================================================================
param([switch] $Detail, [switch] $Check, [switch] $Quiet, [string[]] $Chain)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$inc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$mark = '[ZH-DERIVE-LAYER]'

# --- 从生成器里扫表项（不手写清单：手写的清单一定会漂移，见 regen_zhstdlib.ps1）---
# ⚠ 键名允许带 '.'（内部件的键是文件名形态：'xcall_once.h' / 'xsmf_control.h'）。
#   与 regen_zhstdlib.ps1 用同一个形态 —— 两处不一致就会出现"regen 覆盖了、台账没覆盖"
#   这种最难查的偏差（§16.31）。
function Get-Entries([string] $file) {
    $out = New-Object System.Collections.ArrayList
    $cur = $null
    foreach ($line in [System.IO.File]::ReadAllLines($file)) {
        if ($line -match "^\s+'([a-z_][a-z0-9_.]*)'\s*=\s*@\{") {
            $cur = $Matches[1]
            [void]$out.Add([pscustomobject]@{ H = $cur; Zh = $null })
        } elseif ($cur -and $null -eq $out[$out.Count - 1].Zh -and $line -match "^\s*zh\s*=\s*'([^']+)'") {
            $out[$out.Count - 1].Zh = $Matches[1]
        }
    }
    return , $out
}

# 顶层声明名：行首的 struct/class/union/enum class/enum/using，
# 取"声明符本身的名字"。⚠ 不能写成"`{`/`:` 之前的最后一个标识符"——实测那样会取错：
#     struct uses_allocator<stack<_Ty, _Container>, _Alloc> : uses_allocator<...>::type {};
# 基类子句的末段 `type` 会被当成声明名（假残留）。所以按下面四步剥：
#     ① 去掉括号里的属性/说明符（__declspec(novtable) 之类）
#     ② 去掉行首的 template <...>
#     ③ 切掉第一个"顶层"的基类子句 ':'（不切 :: ，也不切 <> 里面的）
#     ④ 去掉尾部的模板实参表 <...> 与 final
function Get-DeclaredNames([string] $text) {
    $names = @{}
    foreach ($m in [regex]::Matches($text, '(?m)^(?:struct|class|union|enum\s+class|enum|using)\s+([^;{\r\n=]*)')) {
        $g = $m.Groups[1].Value
        $g = [regex]::Replace($g, '\([^()]*\)', ' ')          # ①
        $g = [regex]::Replace($g, '^\s*template\s*<.*?>\s*', ' ')  # ②
        $depth = 0; $cut = -1                                  # ③
        for ($i = 0; $i -lt $g.Length; $i++) {
            $c = $g[$i]
            if ($c -eq '<') { $depth++ }
            elseif ($c -eq '>') { if ($depth -gt 0) { $depth-- } }
            elseif ($c -eq ':' -and $depth -eq 0) {
                if (($i + 1 -lt $g.Length -and $g[$i + 1] -eq ':') -or ($i -gt 0 -and $g[$i - 1] -eq ':')) { $i++; continue }
                $cut = $i; break
            }
        }
        if ($cut -ge 0) { $g = $g.Substring(0, $cut) }
        $g = $g -replace '\bfinal\b', ' '
        while ($true) {                                        # ④
            $t = $g.TrimEnd()
            if (-not $t.EndsWith('>')) { break }
            $d = 0; $st = -1
            for ($i = $t.Length - 1; $i -ge 0; $i--) {
                if ($t[$i] -eq '>') { $d++ }
                elseif ($t[$i] -eq '<') { $d--; if ($d -eq 0) { $st = $i; break } }
            }
            if ($st -lt 0) { break }
            $g = $t.Substring(0, $st)
        }
        $mm = [regex]::Match($g, '([\w~]+)\s*$')
        if (-not $mm.Success) { continue }
        $n = $mm.Groups[1].Value
        if ($n -in @('class', 'struct', 'enum', 'union', 'using', 'template', 'namespace')) { continue }
        $names[$n] = $true
    }
    return $names
}

# ---------------------------------------------------------------------------
#  嵌套名字（类体内的类型别名 / 嵌套类）—— 第二把尺（§16.35）
#
#  为什么要有第二把尺：第一把尺只量"行首声明的顶层类型名"。
#  而 §9/§9.1 要求**嵌套类型名也要汉化**（用户明确要求："基类::value_type，
#  value_type 你就没汉化，这些都得汉化的"），并且方向要反过来：
#      抄来那层 `using 值类型 = _Ty;`（中文）×  派生层 `使用 value_type = 基类::值类型;`（补英文）
#  目前只有 <可选> 一个头是这个方向，其余仍是旧的（§9.3）。
#  **没有数字，这件事就会退化成"我记得翻过"** —— 所以先把它量出来。
#
#  提取判据（要精确，不能靠猜 —— 第一把尺就因为取名算法错而误报过两次）：
#    · 有缩进的 `using NAME =`   -> 类体内的类型别名
#    · 有缩进的 `typedef ... NAME;`
#    · 有缩进的 `class/struct/enum class NAME`（嵌套类声明）
#    （行首 = 顶层，已由第一把尺量过，这里靠"必须缩进"把它们排除掉。）
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
#  成员名（第三把尺，§16.65）
#
#  提取判据：**有缩进、且标识符后面紧跟 `(`** 的行 —— 在微软原头里这几乎总是成员函数
#  （行首的 `#define`/`template <...>` 都被"必须缩进"排除）。
#  再排掉语言关键字与几个常见的非成员名（`if`/`for`/`sizeof`/`static_cast`/…）。
#  ⚠ 这把尺的**已知偏差**（写在这里，免得后来人相信它比实际精确）：
#    · 它会数到少量"函数式宏 / 局部 lambda / 自由函数"，不是严格意义的成员；
#    · 它数的是"这个词还在不在抄来那层里"，同名两主人（借来的 char_traits /
#      basic_string_view）已用 $memBoundary 排除 —— 那份名单是**欠账**不是边界，
#      消除路径 = 把那些借来的邻居也抄成我们自己的内部件。
# ---------------------------------------------------------------------------
function Get-MemberNames([string] $text) {
    $names = @{}
    $kw = @('if', 'for', 'while', 'switch', 'return', 'sizeof', 'static_cast', 'reinterpret_cast',
            'const_cast', 'dynamic_cast', 'decltype', 'noexcept', 'operator', 'static_assert',
            'alignof', 'typeid', 'catch', 'throw', 'new', 'delete', 'and', 'or', 'not',
            'constexpr', 'consteval', 'requires', '__declspec', '__cdecl', '__stdcall',
            'bool', 'explicit', 'virtual', 'friend', 'mutable', 'typename', 'class',
            'enable_if', 'is_same', 'conjunction', 'disjunction', 'declval', 'conditional',
            'move', 'forward', 'exchange', 'max', 'min', 'begin', 'end', 'size', 'data', 'empty')
    foreach ($m in [regex]::Matches($text, '(?m)^[ \t]{4,10}(?:\[\[[^\]]*\]\]\s*)?(?:constexpr\s+|inline\s+|static\s+|virtual\s+|friend\s+|explicit\s+)*[A-Za-z_][\w:<>,\s\*&]*?\b([a-z_]\w*)\s*\(')) {
        $n = $m.Groups[1].Value
        if ($kw -contains $n) { continue }
        $names[$n] = $true
    }
    return $names
}
# 同名两主人（借来的 std 类型读的成员名）—— 见 §16.61.9：这些是边界，
# 但**不是永久边界**：消除路径 = 把 char_traits / basic_string_view 也抄成我们的内部件。
$memBoundary = @('length', 'assign', 'copy', 'compare', 'find', 'max_size', 'swap',
                 'starts_with', 'ends_with', 'contains', 'remove_prefix', 'remove_suffix',
                 'to_char_type', 'to_int_type', 'eq', 'lt', 'not_eof', 'eof',
                 # ---- 借用的 C / std 名字（不是我们的成员，翻不了）----
                 'abort', 'invoke', 'strcmp', 'memcpy', 'memmove', 'memset', 'strlen',
                 # ---- 类型名噪声（构造函数调用、形参类型被本尺子误当成成员）----
                 'ptrdiff_t', 'size_t', 'intptr_t', 'uintptr_t', 'barrier', 'latch',
                 'semaphore', 'thread', 'mutex', 'shared_mutex', 'condition_variable',
                 'stop_token', 'atomic', 'string', 'wstring', 'vector', 'unique_ptr',
                 'shared_ptr', 'function', 'optional', 'variant', 'tuple', 'pair',
                 'duration', 'time_point', 'error_code', 'exception', 'type_info',
                 # ---- MSVC 自己带 `__` 前缀的内部件（借用的）----
                 '__std_atomic_wait_get_deadline', '__std_atomic_wait', '__std_atomic_wait_direct',
                 '_Completion', '_Wait', '_Hash', '_Node', '_List_node',
                 # ---- §16.68 借用的自由函数（定义在 <xutility>/<xmemory> 之外，我们没抄）----
                 '_Adl_verify_range', '_Seek_wrapped', 'address', 'addressof', 'apply',
                 'construct_at', 'destroy_at', 'make_tuple', 'forward_as_tuple',
                 'pointer_to', 'elements_of', 'from_range_t',
                 # ---- §17.19.50 尺子维护第二波（第 117 轮实测）：借来的 traits 成员名 / 流缓冲虚函数 /
                 #      std 公开 API。它们在我们拷贝层里【只有引用、没有定义】（定义在 std 的
                 #      iterator_traits / allocator_traits / char_traits / basic_streambuf / charconv 里），
                 #      按词替换会误伤 —— 消除路径同 §16.61.9：把那些 traits 也抄成我们的内部件。
                 'value_type', 'difference_type', 'pointer', 'reference', 'const_pointer', 'const_reference',
                 'size_type', 'iterator_category', 'iterator_concept', 'element_type', 'char_type', 'int_type',
                 'off_type', 'pos_type', 'state_type', 'traits_type', 'comparison_category', 'type',
                 'const_reverse_iterator', 'reverse_iterator', 'allocator_type',
                 'overflow', 'pbackfail', 'seekoff', 'seekpos', 'setg', 'setp', 'underflow', 'gbump', 'sync',
                 'uflow', 'xsgetn', 'xsputn', 'showmanyc', 'imbue',
                 'format', 'parse', 'flip', 'rotate', 'atomic_store_explicit',
                 # ---- §16.68 allocator 契约名（`allocator_traits<我们的分配器>` 会读它们，
                 #      第 ③ 类；消除路径 = 连 allocator_traits 也一起抄成我们自己的）----
                 'allocate', 'allocate_at_least', 'deallocate', 'construct', 'destroy',
                 'select_on_container_copy_construction',
                 # ---- §16.69 借来的虚函数覆盖 + 类型名噪声 ----
                 #   `what`：`bad_any_cast` 对借来的 `std::exception::what()` 的**虚函数覆盖**
                 #   —— 改名就不再覆盖（静默错误，编译照样过）。属边界。
                 #   `_Construct_in_place` / `_Destroy_in_place` / `_Cast`：定义在 xmemory/xutility。
                 #   `_Ty`：模板形参名（本尺子把它当成成员是已知偏差）。
                 'what', '_Construct_in_place', '_Destroy_in_place', '_Cast', '_Ty',
                 # ---- §16.71 "同一个词两个主人"（本头成员名 × 借用对象上的调用）----
                 #   `wait`：<门闩> 的 `latch::wait` 是我们自己的成员，但正文里
                 #     `_My_cond.wait(...)` 调的是**借来的** std::condition_variable::wait
                 #     —— 按词替换必然误伤（§16.30.3 已实测）。中文名由 deriveExtra 手写给出，
                 #     所以**用户能写 `甲.等待()`**，只是抄来那层留着英文。
                 #   `lexicographical_compare*`：std 算法（借来的）。
                 'wait', 'lexicographical_compare', 'lexicographical_compare_three_way',
                 # ---- §17.23 字符串视图 那边的**借用 C/std 名**（不是欠账）----
                 #   实测这些只有调用、定义在 C 运行库或我们没抄的 std 头里：
                 #   memcmp / wcslen / wmemcmp / to_address / eq_int_type /
                 #   __std_find_first_of_trivial_pos_* / __std_find_last_of_trivial_pos_*
                 'memcmp', 'wcslen', 'wmemcmp', 'to_address', 'eq_int_type',
                 '__std_find_first_of_trivial_pos_1', '__std_find_first_of_trivial_pos_2',
                 '__std_find_first_of_trivial_pos_4', '__std_find_first_of_trivial_pos_8',
                 '__std_find_last_of_trivial_pos_1', '__std_find_last_of_trivial_pos_2',
                 # ---- §16.72 借用的线程核心件 + 模板形参噪声 ----
                 #   `_Mycnd`：<condition_variable> 正文里只有 `_Mycnd()` 这种**调用**，
                 #     定义在借来的线程核心头（goals 里 xthreads.h 那一类，属"判定的边界"）。
                 #   `_Pred`：模板形参名（本尺子的已知偏差，同 `_Ty`）。
                 '_Mycnd', '_Pred',
                 # ---- §16.76 形参名噪声（本尺子的已知偏差：它会把模板形参当成成员）----
                 #   `_Fn`（<scoped_allocator> 的模板形参）、`_Rep`、`_Ty`、`_Pred` 同类。
                 '_Fn', '_Rep',
                 # ---- §16.78 "本头成员名 × 借用对象上的同名调用"（第四类边界）再两例 ----
                 #   `hash_code` / `name`：<类型索引>（std::type_index）里，正文是
                 #     `_Target->hash_code()` / `_Target->name()` —— 调的是**借来的**
                 #     std::type_info 的成员（§16.30.3 实测："type_info 中没有名为 '哈希值' 的成员"）。
                 #   中文名由 deriveExtra 手写转发补出（所以**用户能写 `甲.哈希值()`**），
                 #   抄来那层留英文是边界，不是欠账。
                 'hash_code', 'name',
                 # ---- §16.81 借来的 C 线程核心 API（只有调用，定义在 xthreads.h）----
                 #   实测 <shared_mutex> 里只有 `_Smtx_try_lock_exclusive(&_Myhandle)`
                 #   这种**调用**；定义在借来的 xthreads.h：
                 #       int __cdecl _Smtx_try_lock_exclusive(_Smtx_t*) noexcept;
                 #   与 §16.72 的 `_Mycnd` 同一类（目标文档把 xthreads.h 判为边界）。
                 '_Smtx_try_lock_exclusive', '_Smtx_try_lock_shared',
                 '_Smtx_lock_exclusive', '_Smtx_lock_shared',
                 '_Smtx_unlock_exclusive', '_Smtx_unlock_shared',
                 # ---- §17.7 逐行看出来的**借用的 std 自由函数** ----
                 #   `<集合>`/`<映射>` 正文里只有 `_STD _Erase_nodes_if(_Cont, ...)` 这种调用
                 #   （std 的自由函数，定义在我们没抄的 <xutility> 一侧）——不是我们的名字。
                 #   ⚠ 也正因为它是 `_STD X(...)` 这种**限定调用**，"谁定义它"的粗筛正则
                 #     会把 `return _STD ` 当成返回类型而误判成"本头定义"（§17.6.1 的另一面）。
                 '_Erase_nodes_if')
function Get-NestedNames([string] $text) {    $names = @{}
    foreach ($m in [regex]::Matches($text, '(?m)^[ \t]+using\s+([A-Za-z_]\w*)\s*=')) { $names[$m.Groups[1].Value] = $true }
    foreach ($m in [regex]::Matches($text, '(?m)^[ \t]+typedef\s+[^;\r\n]*?\b([A-Za-z_]\w*)\s*;')) { $names[$m.Groups[1].Value] = $true }
    #  ⚠ 嵌套类/枚举的名字不能写成"最后一个标识符"——实测假残留：
    #        enum class _Deque_types : bool { ... }
    #    取最后一个标识符会取到【底层类型】bool。必须先把基类/底层类型子句切掉
    #    （与第一把尺 Get-DeclaredNames 用同一套剥法：去括号、切顶层 ':'、
    #      去尾部模板实参表、去 final，再取最后一个标识符）。
    #  ⚠ 第三个假残留（§16.37）：**多行 template 参数表**也会被当成嵌套类声明。
    #        template <class _Kty, class _Ty,
    #            class _Alloc, // actual allocator type      <- 缩进、以 class 开头
    #            class _Keyeq = equal_to<_Kty>>
    #        class map { ... }
    #    `class _Alloc,` 是模板参数，不是嵌套类。判据：**真正的类声明同一行里必有 `{` 或 `;`**
    #    （模板参数行以 `,` 或 `>` 结尾）。所以先取整行再要求含 `[;{]`。
    foreach ($m in [regex]::Matches($text, '(?m)^[ \t]+(?:class|struct|union|enum\s+class|enum)\s+([^\r\n]*)')) {
        if ($m.Value -notmatch '[;{]') { continue }
        $g = [regex]::Replace($m.Groups[1].Value, '\([^()]*\)', ' ')
        $g = ($g -split '[;{]')[0]
        $depth = 0; $cut = -1
        for ($i = 0; $i -lt $g.Length; $i++) {
            $c = $g[$i]
            if ($c -eq '<') { $depth++ }
            elseif ($c -eq '>') { if ($depth -gt 0) { $depth-- } }
            elseif ($c -eq ':' -and $depth -eq 0) {
                if (($i + 1 -lt $g.Length -and $g[$i + 1] -eq ':') -or ($i -gt 0 -and $g[$i - 1] -eq ':')) { $i++; continue }
                $cut = $i; break
            }
        }
        if ($cut -ge 0) { $g = $g.Substring(0, $cut) }
        $g = $g -replace '\bfinal\b', ' '
        while ($true) {
            $t = $g.TrimEnd()
            if (-not $t.EndsWith('>')) { break }
            $d = 0; $st = -1
            for ($i = $t.Length - 1; $i -ge 0; $i--) {
                if ($t[$i] -eq '>') { $d++ }
                elseif ($t[$i] -eq '<') { $d--; if ($d -eq 0) { $st = $i; break } }
            }
            if ($st -lt 0) { break }
            $g = $t.Substring(0, $st)
        }
        $mm = [regex]::Match($g, '([\w~]+)\s*$')
        if (-not $mm.Success) { continue }
        $n = $mm.Groups[1].Value
        if ($n -in @('class', 'struct', 'enum', 'union', 'final', 'bool', 'int', 'unsigned', 'char', 'short', 'long', 'size_t')) { continue }
        $names[$n] = $true
    }
    return $names
}

$entries = Get-Entries (Join-Path $root 'tools\make_zhstdlib2.ps1')
$totBound = 0; $totBound2 = 0; $totBound3 = 0
$rows = @()
$rows2 = @()
$rows3 = @()
$totAll = 0; $totDone = 0
$totAll2 = 0; $totDone2 = 0
$totAll3 = 0; $totDone3 = 0
# ---------------------------------------------------------------------------
#  §17.56 边界【机器来源】（A/B/C）—— 判据不许手写清单
#
#  为什么：这三类名字**确实改不了**（外部约束），但标尺原先不认识它们 ⇒ 被算成欠账 ✗。
#    A `dropTypes`      <- 生成器自带 `-ExportJson`（它在该开关下、写任何文件【之前】就 exit 0）
#    B C++ 语言基本类型 <- clang `Basic\TokenKinds.def` 的 `*KEYWORD(...)`
#    C 编译器内建       <- 前缀 `__std_` / `__builtin_` / `_Interlocked`
#  ⚠ 本段**不改**三条尺的分子分母（口径写死"分子只能升"，一个数都不动）——
#     它只多算一栏"已登记边界"，并给出可机器核对的恒等式：
#         **未汉化（残留） = 真欠账 + 已登记边界**      完成判据① = **真欠账 == 0**
# ---------------------------------------------------------------------------
$script:BdDropTypes = @{}
$script:BdKeywords  = @{}
$tkDef = Join-Path $root 'LLVM-main\clang\include\clang\Basic\TokenKinds.def'
if (Test-Path $tkDef) {
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($tkDef), '(?m)^\s*(?:CXX\d*_)?KEYWORD\s*\(\s*([A-Za-z_]\w*)')) {
        $script:BdKeywords[$m.Groups[1].Value] = $true
    }
}
# ---------------------------------------------------------------------------
#  §17.60 再加两条机器边界类（都从**真头**量，健全性已验：与"已登记译名"的交集只有 1 个，
#  而且是常年译好的 `log10`，不是任何产物的残留 ⇒ 不会掩盖真欠账）：
#    F-进口声明：`using std::X;` —— 本头只是把 X 从 std **引进**来（X 定义在别处 ✗，§17.52 实测过）
#    G-C库调用：`_CSTD X` —— `_CSTD` 展开成 `::` ⇒ `::X` 是 **C 库**的名字（不是名域限定 ✗）
#  消除路径（判据① 要求逐条写明）：把 **C 数学 / C 库那一层**也抄成我们自己的内部件，两边一起翻
#   —— 与 `_Cpo` 要抄 `<compare>` 是同一族"要抄更多外部层"。
# ---------------------------------------------------------------------------
$script:BdImport = @{}
$script:BdCLib   = @{}
foreach ($e2 in $entries) {
    if (-not $e2.H) { continue }
    $p2 = Join-Path $inc $e2.H
    if (-not (Test-Path $p2)) { continue }
    $t2 = [System.IO.File]::ReadAllText($p2)
    foreach ($m2 in [regex]::Matches($t2, '(?m)^\s*using\s+std::([A-Za-z_]\w*)\s*;')) { $script:BdImport[$m2.Groups[1].Value] = $true }
    foreach ($m2 in [regex]::Matches($t2, '_CSTD\s+([A-Za-z_]\w*)'))                   { $script:BdCLib[$m2.Groups[1].Value]   = $true }
}
Write-Host ("  边界来源F using std:: 进口名 {0} 个 / G _CSTD C 库名 {1} 个" -f $script:BdImport.Count, $script:BdCLib.Count)
$tblJson = ''
try { $tblJson = & pwsh -NoProfile -File (Join-Path $root 'tools\make_zhstdlib2.ps1') -ExportJson 2>$null | Out-String } catch { }if ($tblJson) {
    try {
        $tbl = $tblJson | ConvertFrom-Json
        foreach ($k in $tbl.PSObject.Properties.Name) {
            $v = $tbl.$k
            if ($v.PSObject.Properties.Name -contains 'dropTypes' -and $v.dropTypes) { $script:BdDropTypes[$k] = @($v.dropTypes) }
        }
    } catch { }
}
# ---------------------------------------------------------------------------
#  §17.59 两条**实测证伪**的边界类（编译器直接拒绝，实证见生成器里的同款注释）：
#    · E-显式特化：`incrementable_traits` —— 本头里是 `struct incrementable_traits<…>`，
#      主模板不在本头 ⇒ 铁律③，改了就不再是 std 模板的特化
#      （编译实证：`error: 显式特化，针对未声明的模板（名字）结构 '可递增特征'`）。
#    · D-借来接收者：`allocator_traits` 的 4 个成员 —— 别处是经【借来的真 `std::allocator_traits<…>`】
#      访问的（源码写的是**非限定**，所以纯正则判不出来，只能靠实证）
#      （编译实证：`error: 'std::allocator_traits<std::allocator<int>>' 中没有名为（名字）'常量空指针' 的类型`）。
#  ⚠ 登记在**本栏**（不动三条尺的分子分母 ✓），与既有 `$stdSpecials`/`$memBoundary` 同一性质。
# ---------------------------------------------------------------------------
$script:BdRefuted = @{
    'incrementable_traits'                   = 'E-显式特化'
    'const_void_pointer'                     = 'D-借来接收者'
    'propagate_on_container_copy_assignment' = 'D-借来接收者'
    'propagate_on_container_move_assignment' = 'D-借来接收者'
    'propagate_on_container_swap'            = 'D-借来接收者'
}
function Get-BoundaryClass([string] $n, [string] $entryKey) {
    if ($script:BdRefuted.ContainsKey($n)) { return $script:BdRefuted[$n] }
    if ($script:BdImport.ContainsKey($n)) { return 'F-进口声明' }
    if ($script:BdCLib.ContainsKey($n))   { return 'G-C库调用' }
    if ($script:BdDropTypes.ContainsKey($entryKey) -and ($script:BdDropTypes[$entryKey] -contains $n)) { return 'A-CRT契约名' }
    if ($script:BdKeywords.ContainsKey($n)) { return 'B-C++语言类型' }
    foreach ($p in @('__std_', '__builtin_', '_Interlocked', '_BitScan')) { if ($n.StartsWith($p)) { return 'C-编译器内建' } }
    return ''
}
foreach ($e in $entries) {
    if (-not $e.Zh) { continue }
    $prod = Join-Path $root "zhstdlib\$($e.Zh)"
    $orig = Join-Path $inc $e.H
    if (-not (Test-Path $prod) -or -not (Test-Path $orig)) { continue }

    $src = [System.IO.File]::ReadAllText($orig)
    $txt = [System.IO.File]::ReadAllText($prod)

    # 只看标记行【以上】= 抄来那层
    $cut = $txt.IndexOf($mark)
    $copy = if ($cut -ge 0) { $txt.Substring(0, $cut) } else { $txt }
    # ⚠ 必须去掉 `#include <...>` 行再判在不在：
    #   条目的 realInclude 会往抄来那层插 `#include <optional>`，
    #   于是 `\boptional\b` 命中 —— 那不是"名字没翻"，是包含语句（实测的假残留）。
    $copy = [regex]::Replace($copy, '(?m)^[ \t]*#\s*include[^\r\n]*', '')

    $names = Get-DeclaredNames $src
    # -----------------------------------------------------------------------
    #  排除【std 模板特化】的名字 —— 它们是【边界】，不是欠账。
    #
    #  抄来那层里的 `struct hash<thread::id>` / `struct formatter<...>` /
    #  `struct uses_allocator<...>` / `pointer_traits<...>` 都是【特化 std 的模板】：
    #  铁律 4 说"类型身份本身参与语义"的必须保持原样（捕获/特化按类型匹配），
    #  改了名就不再是 std 的特化，用户写 std::hash<T> 也找不着。
    #  所以这些名字**必须**留英文，不能算欠账。
    #  这份清单与生成器里 `$stdSpecs` 用同一组名字（见 make_zhstdlib2.ps1 步 0b 的检查）。
    # -----------------------------------------------------------------------
    $stdSpecials = @('hash', 'formatter', 'uses_allocator', 'tuple_size', 'tuple_element',
                     'pointer_traits', 'numeric_limits', 'iterator_traits', 'char_traits',
                     'is_error_code_enum', 'is_error_condition_enum', 'default_delete', 'allocator_traits',
                     # ---- §17.19.47 尺子维护（第 114 轮实测）：下面这些**永远改不掉**，必须从分母剔除 ----
                     #  ① std 公开名 / CPO：铁律③④要求它们留 std 的（advance/equal/fill/get/iter_move…）
                     'advance', 'base', 'basic_const_iterator', 'cbegin', 'cend', 'copy_n', 'dangling',
                     'equal', 'fill', 'fill_n', 'get', 'iter_move', 'iter_swap', 'lower_bound', 'upper_bound',
                     'const_iterator', 'iterator', 'reverse_iterator', 'common_iterator', 'counted_iterator',
                     'move_iterator', 'insert_iterator', 'back_insert_iterator', 'front_insert_iterator',
                     'istream_iterator', 'ostream_iterator', 'istreambuf_iterator', 'ostreambuf_iterator',
                     'size', 'data', 'empty', 'begin', 'end', 'swap', 'move', 'forward', 'exchange', 'max', 'min',
                     #  ② SAL 注解宏（`#define` 在 <sal.h>，本头没有定义）
                     '_In_reads_', '_Pre_satisfies_')
#  ③ 前缀类边界：编译器内建（`__builtin_*`）—— 不是库里的名字，改不了。
$boundaryPrefix = @('__builtin_')
#  判据统一入口：三把尺都用它（此前只有第三把尺用 $memBoundary，前两把尺里这些名字还在污染分母）。
function Test-ZhBoundary([string] $n) {
    if ($stdSpecials -contains $n) { return $true }
    if ($memBoundary -contains $n) { return $true }
    foreach ($p in $boundaryPrefix) { if ($n.StartsWith($p)) { return $true } }
    return $false
}
    $res = @()
    foreach ($n in $names.Keys) {
        if (Test-ZhBoundary $n) { continue }
        if ([regex]::IsMatch($copy, "\b$([regex]::Escape($n))\b")) { $res += $n }
    }
    $res = @($res | Sort-Object)
    $effTotal = $names.Count - @($names.Keys | Where-Object { Test-ZhBoundary $_ }).Count
    $totBound += ($names.Count - $effTotal)
    $totAll += $effTotal
    $totDone += ($effTotal - $res.Count)
    $rows += [pscustomobject]@{
        中文头 = $e.Zh; 源 = $e.H; 顶层类型 = $effTotal; 残留 = $res.Count; 名单 = ($res -join ' ')
    }

    # ---- 第二把尺：嵌套名字 ----
    $names2 = Get-NestedNames $src
    $res2 = @()
    foreach ($n in $names2.Keys) {
        # 同样的边界排除：std 模板特化的名字必须留英文（铁律 4）
        if (Test-ZhBoundary $n) { continue }
        if ([regex]::IsMatch($copy, "\b$([regex]::Escape($n))\b")) { $res2 += $n }
    }
    $res2 = @($res2 | Sort-Object)
    $effTotal2 = $names2.Count - @($names2.Keys | Where-Object { Test-ZhBoundary $_ }).Count
    if ($effTotal2 -gt 0) {
        $totBound2 += ($names2.Count - $effTotal2)
        $totAll2 += $effTotal2
        $totDone2 += ($effTotal2 - $res2.Count)
        $rows2 += [pscustomobject]@{
            中文头 = $e.Zh; 源 = $e.H; 嵌套名 = $effTotal2; 残留 = $res2.Count; 名单 = ($res2 -join ' ')
        }
    }

    # ---- 第三把尺：成员名（§16.65）----
    #  前两把尺量的都是【类型名】。"完全是汉语书写的标准库"还包括**成员函数名**，
    #  而这一块一直只存在于"我记得翻过"里 —— 所以量出来。
    #  方法与前两把尺**完全一致**：从原头提候选名，再看它在【抄来那层】里还在不在。
    $names3 = Get-MemberNames $src
    $res3 = @()
    foreach ($n in $names3.Keys) {
        if (Test-ZhBoundary $n) { continue }
        # ⚠ 边界（与前两把尺同源）：这些成员名被**借来的** std 类型读（char_traits /
        #   basic_string_view / allocator_traits），按词替换会误伤，属第 ③ 类。
        if ($memBoundary -contains $n) { continue }
        if ([regex]::IsMatch($copy, "\b$([regex]::Escape($n))\b")) { $res3 += $n }
    }
    $res3 = @($res3 | Sort-Object)
    $effTotal3 = @($names3.Keys | Where-Object { -not (Test-ZhBoundary $_) }).Count
    if ($effTotal3 -gt 0) {
        $totBound3 += ($names3.Count - $effTotal3)
        $totAll3 += $effTotal3
        $totDone3 += ($effTotal3 - $res3.Count)
        $rows3 += [pscustomobject]@{
            中文头 = $e.Zh; 源 = $e.H; 成员名 = $effTotal3; 残留 = $res3.Count; 名单 = ($res3 -join ' ')
        }
    }
}

# ---------------------------------------------------------------------------
#  §17.19.45 `-Chain <名>`：链名工作表 —— 一个英文名到底出现在哪些产物里。
#  为什么加它（第 112 轮实测）：`_Release` 的定义在 <内存内部件>，而【用户】散在 12 个产物里；
#    审计的三把尺只看得见"声明"与"名字紧跟 ( 的调用"，`_Release` 只在 4 个头里被它数到 ——
#    照着审计表登记就会只改 4 处，其余 8 个产物编译不过（链表/映射/双端队列 实测报
#    「没有名为 _Release 的成员」）。链名的用户集必须【直接 grep 产物】，不能只看审计表。
#  用法：pwsh -File tools\audit_hanhua.ps1 -Chain _Release,_Seek_to
# ---------------------------------------------------------------------------
if ($Chain -and $Chain.Count) {
    # ⚠ pwsh -File 把逗号列表当【一个字符串】传进来 —— 必须自己拆（老坑，§17.19.45）
    $Chain = @($Chain | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    foreach ($cn in $Chain) {
        $hitP = @()
        foreach ($pf in (Get-ChildItem (Join-Path $root 'zhstdlib') -File | Sort-Object Name)) {
            $pt = [System.IO.File]::ReadAllText($pf.FullName)
            $n = ([regex]::Matches($pt, ('(?<![\w])' + [regex]::Escape($cn) + '(?![\w])'))).Count
            if ($n -gt 0) { $hitP += ("{0}({1})" -f $pf.Name, $n) }
        }
        Write-Host ("=== 链名工作表 {0}：出现在 {1} 个产物里 ===" -f $cn, $hitP.Count) -ForegroundColor Cyan
        Write-Host ("  " + ($hitP -join ' '))
    }
    exit 0
}
$rows = @($rows | Sort-Object -Property @{ Expression = { $_.残留 } } -Descending)
if (-not $Quiet) { $rows | Format-Table -Property 中文头, 源, 顶层类型, 残留 -AutoSize }

if ($Detail) {
    Write-Host "--- 抄来那层的残留名单（= 欠账）---"
    foreach ($r in $rows) { if ($r.残留) { Write-Host ("  {0,-14} {1}" -f $r.中文头, $r.名单) } }
}

$clean = @($rows | Where-Object { $_.残留 -eq 0 }).Count
Write-Host ""
Write-Host ("=== 抄+派生轨道 顶层类型名汉化率: {0} / {1} = {2:N1}% ===" -f `
    $totDone, $totAll, (100 * $totDone / [Math]::Max($totAll, 1))) -ForegroundColor Cyan
Write-Host ("    完全无残留的头: {0} / {1}" -f $clean, $rows.Count) -ForegroundColor Cyan
Write-Host "    注意：残留 = 欠账【加上】借用边界（false_type / uintptr_t 这类真 std 名）。"
Write-Host "          前者要消灭，后者要等步骤 1 的 34 个内部头全部抄完才会自然消失。"

# ---------------------------------------------------------------------------
#  第二把尺：嵌套名字（§16.35）
# ---------------------------------------------------------------------------
$rows2 = @($rows2 | Sort-Object -Property @{ Expression = { $_.残留 } } -Descending)
if ($rows2.Count) {
    Write-Host ""
    Write-Host "=== 嵌套名字（类体内 using/typedef/嵌套类）===" -ForegroundColor Cyan
    if (-not $Quiet) { $rows2 | Format-Table -Property 中文头, 源, 嵌套名, 残留 -AutoSize }
    if ($Detail) {
        Write-Host "--- 嵌套名残留名单 ---"
        foreach ($r in $rows2) { if ($r.残留) { Write-Host ("  {0,-14} {1}" -f $r.中文头, $r.名单) } }
    }
    $clean2 = @($rows2 | Where-Object { $_.残留 -eq 0 }).Count
    Write-Host ("=== 嵌套名汉化率: {0} / {1} = {2:N1}% ===" -f `
        $totDone2, $totAll2, (100 * $totDone2 / [Math]::Max($totAll2, 1))) -ForegroundColor Cyan
    Write-Host ("    完全无残留的头: {0} / {1}" -f $clean2, $rows2.Count) -ForegroundColor Cyan
    Write-Host "    注意：这一栏【天然偏高】—— 旧方向（抄来那层留英文、派生层补中文，§9.1）下，"
    Write-Host "          中文名其实【用户已经能写】，只是抄来那层还不是汉语。"
    Write-Host "          所以这一栏量的是「§9.3 要翻转的方向」，不是「用户写不出来」。"
    Write-Host "          另有真边界：reference / value_type 这类会出现在【借用路径】上"
    Write-Host "          （allocator_traits<_Alloc>::value_type），改错必须能回退（§15.5）。"

    # ---- 第三把尺：成员名（§16.65）----
    $rows3 = @($rows3 | Sort-Object -Property @{ Expression = { $_.残留 } } -Descending)
    Write-Host ""
    Write-Host "=== 成员名字（抄来那层里「标识符紧跟 (」的行，含自由函数/局部函数的少量偏差）===" -ForegroundColor Cyan
    if (-not $Quiet) { $rows3 | Format-Table -Property 中文头, 源, 成员名, 残留 -AutoSize }
    if ($Detail) {
        Write-Host "--- 成员名残留名单（= 欠账 + 已登记的边界）---"
        foreach ($r in $rows3) { if ($r.残留) { Write-Host ("  {0,-14} {1}" -f $r.中文头, $r.名单) } }
    }
    Write-Host ("    已从分母剔除的真边界候选（§17.19.47：编译器内建 / 关键字类型名 / std 公开名 / SAL 宏）：顶层 {0} / 嵌套 {1} / 成员 {2}" -f $totBound, $totBound2, $totBound3) -ForegroundColor DarkGray
$clean3 = @($rows3 | Where-Object { $_.残留 -eq 0 }).Count
    Write-Host ("=== 成员名汉化率: {0} / {1} = {2:N1}% ===" -f `
        $totDone3, $totAll3, (100 * $totDone3 / [Math]::Max($totAll3, 1))) -ForegroundColor Cyan
    Write-Host ("    完全无残留的头: {0} / {1}" -f $clean3, $rows3.Count) -ForegroundColor Cyan
    Write-Host "    这一栏量的是「成员函数名」—— 目标说「完全是汉语书写」，成员名也算。"
    Write-Host "    已排除的边界（见 \$memBoundary）：char_traits / basic_string_view /"
    Write-Host "      allocator_traits 这些**借来的** std 类型读的成员名（length/assign/copy/…）——"
    Write-Host "      消除路径 = 把它们也抄成我们自己的内部件，然后两边一起翻。"
}

# ---------------------------------------------------------------------------
#  §17.56 已登记边界（机器来源 A/B/C）：把"未汉化"拆成【真欠账 + 已登记边界】
#  完成判据①（目标原文）：「三条尺分子 = 分母，**或所有未汉化项都在边界台账里有理由与消除路径**」
#  ⇒ 本段给出可机器核对的形式：**未汉化 = 真欠账 + 已登记边界**，判据①成立即 **真欠账 == 0**。
#  ⚠ 三条尺的分子/分母**一个数都不动**（口径"分子只能升"，一个数都不许降）。
# ---------------------------------------------------------------------------
$bdRows = @()
foreach ($set in @(@{ N = '顶层类型名'; R = $rows }, @{ N = '嵌套名'; R = $rows2 }, @{ N = '成员名'; R = $rows3 })) {
    foreach ($r in $set.R) {
        if (-not $r.残留) { continue }
        foreach ($n in @($r.名单 -split '\s+' | Where-Object { $_ })) {
            $cls = Get-BoundaryClass $n $r.源
            if ($cls) { $bdRows += [pscustomobject]@{ 尺 = $set.N; 产物 = $r.中文头; 名字 = $n; 类 = $cls } }
        }
    }
}
$bdRows = @($bdRows | Sort-Object 尺, 类, 名字)
function Get-ResidSum($rs) { return [int](@($rs | Measure-Object -Property 残留 -Sum).Sum) }
$resid1 = Get-ResidSum $rows;  $resid2 = Get-ResidSum $rows2;  $resid3 = Get-ResidSum $rows3
$bd1 = @($bdRows | Where-Object { $_.尺 -eq '顶层类型名' }).Count
$bd2 = @($bdRows | Where-Object { $_.尺 -eq '嵌套名' }).Count
$bd3 = @($bdRows | Where-Object { $_.尺 -eq '成员名' }).Count
$bdGroups = @($bdRows | Group-Object 类 | Sort-Object Name)
Write-Host ""
Write-Host "=== 已登记边界（机器来源 §17.56；三条尺的分子分母未动）===" -ForegroundColor Cyan
Write-Host ("  顶层: 未汉化 {0} = 真欠账 {1} + 已登记边界 {2}" -f $resid1, ($resid1 - $bd1), $bd1)
Write-Host ("  嵌套: 未汉化 {0} = 真欠账 {1} + 已登记边界 {2}" -f $resid2, ($resid2 - $bd2), $bd2)
Write-Host ("  成员: 未汉化 {0} = 真欠账 {1} + 已登记边界 {2}" -f $resid3, ($resid3 - $bd3), $bd3)
foreach ($g in $bdGroups) { Write-Host ("    {0}: {1} 个" -f $g.Name, $g.Count) }
Write-Host "  边界逐条理由与消除路径见 汉化标尺台账.md 的「已登记边界」一节。"

# ---------------------------------------------------------------------------
#  §17.19.40 标尺台账 + 守卫：把"还剩多少"变成机器守得住的数字。
#  两条判据：
#    ① 台账必须与本次实测一致（手写的台账一定会漂移 —— 同 §16.40 / §17.19.21）；
#    ② 三条尺的【分子】不许倒退（率可以因分母变大而下降，分子下降才是真倒退）。
#  为什么加它（第 108 轮）：<算法>/<范围> 等一批头落地后，"还剩多少"不能只靠方案里的一段话，
#    必须每轮机器算一遍；用户反复问的那个数，得有一个不会说谎的答案。
#  用法：不带开关 = 重写台账；-Check = 只校验（闸门用 -Check -Quiet）；-Detail = 打残留名单。
# ---------------------------------------------------------------------------
if ($null -eq $clean)  { $clean = 0 }
if ($null -eq $clean2) { $clean2 = 0 }
if ($null -eq $clean3) { $clean3 = 0 }
if ($null -eq $rows2)  { $rows2 = @() }
if ($null -eq $rows3)  { $rows3 = @() }
$ledgerPath = Join-Path $root 'docs\标准库汉化\汉化标尺台账.md'
$ledger = @(
    '# 汉化标尺台账（§17.19.40）',
    '',
    '> 本文件由 `tools\audit_hanhua.ps1` 生成，`tools\regen_zhstdlib.ps1` 用 `-Check` 守。',
    '> 三条尺只量【抄+派生轨道】（别名/转发轨道不产生"抄来那层"）。',
    '> 口径：率 = 分子 / 分母。**分母随新头增加而变大 —— 率下降不等于倒退，只有分子下降才是倒退。**',
    '',
    '| 尺 | 分子（已汉化） | 分母（应有） | 率 | 无残留头 |',
    '|---|---|---|---|---|',
    ("| 顶层类型名 | {0} | {1} | {2:N1}% | {3} / {4} |" -f $totDone,  $totAll,  (100 * $totDone  / [Math]::Max($totAll, 1)),  $clean,  $rows.Count),
    ("| 嵌套名 | {0} | {1} | {2:N1}% | {3} / {4} |" -f $totDone2, $totAll2, (100 * $totDone2 / [Math]::Max($totAll2, 1)), $clean2, $rows2.Count),
    ("| 成员名 | {0} | {1} | {2:N1}% | {3} / {4} |" -f $totDone3, $totAll3, (100 * $totDone3 / [Math]::Max($totAll3, 1)), $clean3, $rows3.Count),
    '',
    '## 已登记边界（机器来源，§17.56）',
    '',
    '> 这些名字**确实改不了**（外部约束）。它们在三条尺的分子/分母里**照旧计入** ——',
    '> 口径「分子只能升」不许动（一个数都不降 ✗）。本栏只是把它们**显式登记**，',
    '> 好让完成判据① 可机器核对：**未汉化 = 真欠账 + 已登记边界**，判据①成立 ⇔ **真欠账 == 0**。',
    '',
    '| 尺 | 未汉化 | 真欠账 | 已登记边界 |',
    '|---|---|---|---|',
    ("| 顶层类型名 | {0} | {1} | {2} |" -f $resid1, ($resid1 - $bd1), $bd1),
    ("| 嵌套名 | {0} | {1} | {2} |" -f $resid2, ($resid2 - $bd2), $bd2),
    ("| 成员名 | {0} | {1} | {2} |" -f $resid3, ($resid3 - $bd3), $bd3),
    '',
    '| 类 | 判据来源（机器可读，不是手写清单） | 个数 | 名单 |',
    '|---|---|---|---|',
    (($bdGroups | ForEach-Object {
        $src = switch ($_.Name) {
            'A-CRT契约名'   { '生成器 `dropTypes`（`-ExportJson`）' }
            'B-C++语言类型' { 'clang `TokenKinds.def` 的 `*KEYWORD`' }
            default          { '前缀 `__std_`/`__builtin_`/`_Interlocked`' }
        }
        "| {0} | {1} | {2} | {3} |" -f $_.Name, $src, $_.Count, ((@($_.Group | Select-Object -ExpandProperty 名字 | Sort-Object -Unique)) -join ' ')
    }) -join "`n"),
    '',
    '**理由与消除路径**（每一条都要写清，判据① 要求）：',
    '- `A-CRT契约名`：生成器 `dropTypes` 明列的 CRT 契约名（msvcp 的 `operator<<`/`>>` 按这些**类型**匹配，改了链不上）⇒ **无消除路径**。',
    '- `B-C++语言类型`：C++ **语言关键字**（clang `TokenKinds.def`）⇒ **无消除路径**。',
    '- `C-编译器内建`：`__std_*` / `_BitScan*` 等编译器内建例程 ⇒ **无消除路径**。',
    '- `D-借来接收者`：别处经**借来的真 std 模板**访问（如 `std::allocator_traits<…>::成员`）⇒ 消除路径 = 把那层也抄成我们的内部件。',
    '- `E-显式特化`：本头里是 **std 模板的显式特化**（主模板不在本头）⇒ 铁律③ ⇒ 消除路径 = 抄主模板所在的那层。',
    '- `F-进口声明`：真头里 `using std::X;` ⇒ X 定义在别处（本头只是引进）⇒ 消除路径 = 抄那一层。',
    '- `G-C库调用`：真头里 `_CSTD X`（`_CSTD` = `::`）⇒ X 是 **C 库**的名字 ⇒ 消除路径 = 把 C 数学/C 库那层抄进来。',
    '⇒ A/B/C 三类都是外部约束，**无消除路径**；D/E/F/G 有"抄更多外部层"的消除路径（与 `_Cpo` 要抄 `<compare>` 同族）。',
    '⇒ 把它们从分子分母**同时**剔除会令分子下降 —— 与「分子只能升」冲突 ⇒ **留给大检查统一决定**（见 `build\_review_own\口径修订提案.md`）。'
)
$ledgerText = ($ledger -join "`n") + "`n"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$line = "汉化标尺：最新（顶层 {0}/{1}、嵌套 {2}/{3}、成员 {4}/{5}）" -f $totDone, $totAll, $totDone2, $totAll2, $totDone3, $totAll3
if ($Check) {
    if (-not (Test-Path $ledgerPath)) {
        Write-Host '❌ 汉化标尺台账不存在：先跑 tools\audit_hanhua.ps1（不带 -Check）再一起提交。' -ForegroundColor Red
        exit 1
    }
    $old = [System.IO.File]::ReadAllText($ledgerPath)
    if ($old -ne $ledgerText) {
        $oldNum = @{}
        foreach ($m in [regex]::Matches($old, '(?m)^\| (顶层类型名|嵌套名|成员名) \| (\d+) \|')) { $oldNum[$m.Groups[1].Value] = [int]$m.Groups[2].Value }
        $nowNum = @{ '顶层类型名' = $totDone; '嵌套名' = $totDone2; '成员名' = $totDone3 }
        $back = @()
        foreach ($k in @('顶层类型名', '嵌套名', '成员名')) {
            if ($oldNum.ContainsKey($k) -and $nowNum[$k] -lt $oldNum[$k]) { $back += ("{0} 分子 {1} -> {2}" -f $k, $oldNum[$k], $nowNum[$k]) }
        }
        if ($back.Count) {
            Write-Host ('❌ 汉化标尺【分子倒退】：' + ($back -join '；')) -ForegroundColor Red
            Write-Host '   率下降可以（分母变大），分子下降不行 —— 这是真倒退，必须查清是哪个头被改回去了。' -ForegroundColor Red
        } else {
            Write-Host '❌ 汉化标尺台账【已过期】（产物变了但台账没重生成，或有人手改了台账）' -ForegroundColor Red
            Write-Host '   修法：pwsh -File tools\audit_hanhua.ps1  然后一起提交。' -ForegroundColor Yellow
        }
        exit 1
    }
    Write-Host ($line + '（台账最新）') -ForegroundColor Green
    exit 0
}
[System.IO.File]::WriteAllText($ledgerPath, $ledgerText, $utf8)
Write-Host ($line + "`n台账已写入 docs\标准库汉化\汉化标尺台账.md") -ForegroundColor Green
