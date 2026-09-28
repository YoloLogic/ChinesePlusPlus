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
param([switch] $Detail)

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
$rows = @()
$rows2 = @()
$rows3 = @()
$totAll = 0; $totDone = 0
$totAll2 = 0; $totDone2 = 0
$totAll3 = 0; $totDone3 = 0
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
                     'is_error_code_enum', 'is_error_condition_enum', 'default_delete', 'allocator_traits')
    $res = @()
    foreach ($n in $names.Keys) {
        if ($stdSpecials -contains $n) { continue }
        if ([regex]::IsMatch($copy, "\b$([regex]::Escape($n))\b")) { $res += $n }
    }
    $res = @($res | Sort-Object)
    $effTotal = $names.Count - @($names.Keys | Where-Object { $stdSpecials -contains $_ }).Count
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
        if ($stdSpecials -contains $n) { continue }
        if ([regex]::IsMatch($copy, "\b$([regex]::Escape($n))\b")) { $res2 += $n }
    }
    $res2 = @($res2 | Sort-Object)
    $effTotal2 = $names2.Count - @($names2.Keys | Where-Object { $stdSpecials -contains $_ }).Count
    if ($effTotal2 -gt 0) {
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
        if ($stdSpecials -contains $n) { continue }
        # ⚠ 边界（与前两把尺同源）：这些成员名被**借来的** std 类型读（char_traits /
        #   basic_string_view / allocator_traits），按词替换会误伤，属第 ③ 类。
        if ($memBoundary -contains $n) { continue }
        if ([regex]::IsMatch($copy, "\b$([regex]::Escape($n))\b")) { $res3 += $n }
    }
    $res3 = @($res3 | Sort-Object)
    $effTotal3 = @($names3.Keys | Where-Object { $stdSpecials -notcontains $_ -and $memBoundary -notcontains $_ }).Count
    if ($effTotal3 -gt 0) {
        $totAll3 += $effTotal3
        $totDone3 += ($effTotal3 - $res3.Count)
        $rows3 += [pscustomobject]@{
            中文头 = $e.Zh; 源 = $e.H; 成员名 = $effTotal3; 残留 = $res3.Count; 名单 = ($res3 -join ' ')
        }
    }
}

$rows = @($rows | Sort-Object -Property @{ Expression = { $_.残留 } } -Descending)
$rows | Format-Table -Property 中文头, 源, 顶层类型, 残留 -AutoSize

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
    $rows2 | Format-Table -Property 中文头, 源, 嵌套名, 残留 -AutoSize
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
    $rows3 | Format-Table -Property 中文头, 源, 成员名, 残留 -AutoSize
    if ($Detail) {
        Write-Host "--- 成员名残留名单（= 欠账 + 已登记的边界）---"
        foreach ($r in $rows3) { if ($r.残留) { Write-Host ("  {0,-14} {1}" -f $r.中文头, $r.名单) } }
    }
    $clean3 = @($rows3 | Where-Object { $_.残留 -eq 0 }).Count
    Write-Host ("=== 成员名汉化率: {0} / {1} = {2:N1}% ===" -f `
        $totDone3, $totAll3, (100 * $totDone3 / [Math]::Max($totAll3, 1))) -ForegroundColor Cyan
    Write-Host ("    完全无残留的头: {0} / {1}" -f $clean3, $rows3.Count) -ForegroundColor Cyan
    Write-Host "    这一栏量的是「成员函数名」—— 目标说「完全是汉语书写」，成员名也算。"
    Write-Host "    已排除的边界（见 \$memBoundary）：char_traits / basic_string_view /"
    Write-Host "      allocator_traits 这些**借来的** std 类型读的成员名（length/assign/copy/…）——"
    Write-Host "      消除路径 = 把它们也抄成我们自己的内部件，然后两边一起翻。"
}
