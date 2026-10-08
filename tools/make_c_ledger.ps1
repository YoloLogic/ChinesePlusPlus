# ============================================================================
#  make_c_ledger.ps1 —— 生成《C 库汉化台账》（C 线覆盖盘点）
#
#  用户 2026-10-07 裁定：不做纯 C（不新增宏别名层），只把 Chinese++
#  现有的 C 库汉化（zhstdlib 里的「C 包装头」别名层）做扎实；
#  并要求先有一份盘点：「我们做了什么、还缺什么」。
#
#  本脚本就是那份盘点的**唯一真相**：它从盘上的真文件算，不抄任何手写清单。
#
#  两侧数据来源：
#    我们    zhstdlib\C运行库\*（25 个）+ zhstdlib\标准库\错误号（cerrno，共 26 个头）
#    参考    发行包 lib\stl\cXXX 里的 `using _CSTD <名字>;` 名单
#            —— 那是 MSVC STL 把 C 名字搬进 std 的全集，也就是**可以起中文名**的全集
#
#  【两种口径，别混】（第一版判据在这里踩过坑）
#    · 符号口径：acos / acosf / acosl 各算一个（STL 就是按符号暴露的）
#    · 逻辑口径：把 f/l 变体合并成一个逻辑函数
#      我们的机制是**变参模板转发**，一个中文名覆盖整族重载 ⇒ 逻辑口径才是真实工作量
#
#  【另一处已修正的判据错误】
#    所有 C 包装头共用同一段说明注释，里面有 `使用 中文名 = std::原名;`、
#    `内联 常量 承载它的值` 这类**示例行**。第一版没剥注释，把这些示例也数成了真名字
#    （每个头虚高 1–2 个，总计虚高到 196）。现在一律**先剥注释再数**。
#
#  【第三处已修正的判据错误（§18.58 修正，最隐蔽的一个）】
#    f/l 变体合并的第一版规则是"去掉末尾一个字母、基名也在集合里就合并"，
#    它把 `strtoll`/`atoll`/`wcstoull`（long long 版，**另一个函数**）当成 `l` 变体，
#    还把 `nanf`/`nanl` 当成 `nan` 的重载 ⇒ **缺口少算 7 个**（211 而非 218），
#    而且表面上一切正常。修正规则与自测见下面的 Merge-Variants / Test-MergeVariants。
#
#  用法：
#    pwsh -File tools\make_c_ledger.ps1            # 重新生成台账
#    pwsh -File tools\make_c_ledger.ps1 -Check     # 只核对盘上台账是否与文件一致（闸门用）
#
#  退出码：0 正常；1 核对不一致；2 参考基准（lib\stl）不在盘上 —— **如实跳过，不算失败**
#          （与 tools\verify_linux.ps1 对"前置件不全"的口径一致）
# ============================================================================
param(
    [string]$StlDir,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$zhDir = Join-Path $root 'zhstdlib\C运行库'
$stdDir = Join-Path $root 'zhstdlib\标准库'
$outPath = Join-Path $root 'docs\标准库汉化\C库汉化台账.md'

# ---------------------------------------------------------------- 参考基准定位
function Find-StlDir {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
    $cands = @(
        (Join-Path $root 'vendor\stl'),
        (Join-Path $root 'build\include')
    )
    foreach ($c in $cands) { if (Test-Path (Join-Path $c 'cstdio')) { return $c } }
    # 发行包里的 lib\stl（dist 是构建产物、不入库，所以这里可能找不到）
    $dist = Join-Path $root 'dist'
    if (Test-Path $dist) {
        foreach ($d in (Get-ChildItem $dist -Directory -Filter 'Chinese++-*' -ErrorAction SilentlyContinue)) {
            $p = Join-Path $d.FullName 'lib\stl'
            if (Test-Path (Join-Path $p 'cstdio')) { return $p }
        }
    }
    return $null
}

# ---------------------------------------------------------------- 工具
# 剥掉 // 与 /* */ 注释（**必须先剥再数**，见文件头说明）
function Remove-Comments([string]$s) {
    $s = [regex]::Replace($s, '/\*[\s\S]*?\*/', ' ')
    return [regex]::Replace($s, '//[^\r\n]*', ' ')
}

# 从一个中文 C 包装头里抽出它起了哪些中文名（返回 英文原名 -> 类别）
function Get-ZhNames([string]$path) {
    $raw = [System.IO.File]::ReadAllText($path)
    $code = Remove-Comments $raw
    $map = @{}
    foreach ($m in [regex]::Matches($code, '使用\s+(?<zh>[^\s=;]+)\s*=\s*std::(?<en>[A-Za-z_]\w*)\s*;')) {
        $map[$m.Groups['en'].Value] = [pscustomobject]@{ 中文 = $m.Groups['zh'].Value; 类 = '类型' }
    }
    # §18.60：`模板 <...> 约束 (...) 声明类型(自动) 名(...)` 是**加了算术约束的形态** ——
    #   正则必须容忍中间的 `约束 (...)`，否则那 17 个名字会被**静默漏数**
    #   （实测：漏数时台账报 232 个名字 / 缺 132，真值应是 249 / 115）。
    #   这正是本仓记过的坑：扫描器"只认它见过的那种条目形态"，漏扫的名字**不会变成未覆盖**，
    #   它只是**不存在** —— 所以改生成器形态时必须回头核对守卫打印的数字有没有跟着变。
    foreach ($m in [regex]::Matches($code, '模板\s*<[^>]*>\s*(?:约束\s*\([^)]*\)\s*)?声明类型\(自动\)\s*(?<zh>[^\s(]+)\s*\([^)]*\)\s*\{\s*返回\s+std::(?<en>[A-Za-z_]\w*)\s*\(')) {
        $map[$m.Groups['en'].Value] = [pscustomobject]@{ 中文 = $m.Groups['zh'].Value; 类 = '函数' }
    }
    foreach ($m in [regex]::Matches($code, '内联\s+常量\s+\S+\s+(?<zh>[^\s=;]+)\s*=\s*(?<en>[A-Za-z_]\w*)\s*;')) {
        $map[$m.Groups['en'].Value] = [pscustomobject]@{ 中文 = $m.Groups['zh'].Value; 类 = '值宏' }
    }
    return $map
}

# 参考侧：某个 cXXX 暴露到 std 的 C 名字集合
function Get-RefNames([string]$stlDir, [string]$cHeader) {
    if (-not $cHeader) { return @() }
    $p = Join-Path $stlDir $cHeader
    if (-not (Test-Path $p)) { return @() }
    $code = Remove-Comments ([System.IO.File]::ReadAllText($p))
    return @([regex]::Matches($code, 'using\s+_CSTD\s+(?<en>[A-Za-z_]\w*)\s*;') |
        ForEach-Object { $_.Groups['en'].Value } | Sort-Object -Unique)
}

# ---------------------------------------------------------------- f/l 变体合并
#
#  合并的意义：我们的机制是**变参模板转发** —— 一个中文名转发到 `std::acos`，
#  由 C++ 的 <cmath> 重载一次性覆盖 float / double / long double 三个符号
#  ⇒ 这三个符号只算**一份工作量**。
#
#  ⚠ §18.58 修正（本判据第一版是错的，错的数字一度是 357 / 缺 211）：
#    第一版规则是"去掉末尾一个字母，若基名也在参考集里就合并"。它会误合并三类名字：
#      ① `strtoll` / `atoll` / `wcstoull` —— 去掉末尾 l 得到 `strtol` / `atol` / `wcstoul`，
#         它们确实在集合里，但那是**另一个函数**（long long 版），不是重载；
#      ② `nanf` / `nanl` —— 标准里 `nan` / `nanf` / `nanl` 是**三个独立名字**，不是重载；
#      ③ 剩下的才是真重载族（`acosf`/`acosl` → `acos`）。
#    修正后的规则：**整族存在**才算重载族 —— `X`、`Xf`、`Xl` 都在参考集里才合并
#    （`ceill` 的族是 ceil/ceilf/ceill ⇒ 合；`strtoll` 的族要 strtol/strtolf/strtoll，
#    而 `strtolf` 根本不存在 ⇒ 不合）。再加一条**写死的例外** `nan`
#    （`nan`/`nanf`/`nanl` 三个名字齐、看起来像重载族，但标准里是三个独立名字；
#    它从名字上推不出来，所以下面有自测盯着）。
#    ⚠ 这条修正把数字改成：参考逻辑 357 → **364**、缺口 211 → **218**。
#
#  为什么必须自测：这条判据的错法是"少算 7 个缺口"，**看起来一切正常**。
#  自测里每一条都配了"该合的合、不该合的不合"，判据被改坏会当场抛错。
$不合并基名 = @('nan')

function Merge-Variants($names) {
    $set = @{}
    foreach ($n in $names) { $set[$n] = $true }
    $out = @{}
    foreach ($n in $names) {
        $s = $n
        if ($n.Length -gt 1 -and ($n.EndsWith('f') -or $n.EndsWith('l'))) {
            $b = $n.Substring(0, $n.Length - 1)
            # 判据：**整族存在**才算重载族 —— X、Xf、Xl 三个名字都在参考集里。
            #   · `ceill`：ceil / ceilf / ceill 都在 ⇒ 合（基名以 l 结尾也照合）
            #   · `strtoll`：需要 strtol / strtolf / strtoll，而 `strtolf` 不存在 ⇒ 不合
            #     （`strtoll` 是 long long 版的**另一个函数**，不是 `strtol` 的重载）
            $是重载族 = $set.ContainsKey($b) -and $set.ContainsKey($b + 'f') -and $set.ContainsKey($b + 'l')
            if ($是重载族 -and ($不合并基名 -notcontains $b)) { $s = $b }
        }
        $out[$s] = $true
    }
    return @($out.Keys | Sort-Object)
}

# 判据自测：每组写"输入集合 / 合并后应有的个数"，不一致就抛错（**判据要能失败**）
function Test-MergeVariants {
    $cases = @(
        [pscustomobject]@{ 说 = 'acosf/acosl 合并到 acos（真重载族）'; 集 = @('acos', 'acosf', 'acosl'); 期 = 1 }
        [pscustomobject]@{ 说 = 'ceill 仍与 ceil 合并（基名以 l 结尾也要合）'; 集 = @('ceil', 'ceilf', 'ceill'); 期 = 1 }
        [pscustomobject]@{ 说 = 'modff 仍与 modf 合并（基名以 f 结尾也要合）'; 集 = @('modf', 'modff', 'modfl'); 期 = 1 }
        [pscustomobject]@{ 说 = 'llrintf/llrintl 合并到 llrint（ll 在【基名】里，不是后缀）'; 集 = @('llrint', 'llrintf', 'llrintl'); 期 = 1 }
        [pscustomobject]@{ 说 = 'strtoll 不与 strtol 合并（ll 是另一个函数）'; 集 = @('strtol', 'strtoll'); 期 = 2 }
        [pscustomobject]@{ 说 = 'atoll 不与 atol 合并'; 集 = @('atol', 'atoll'); 期 = 2 }
        [pscustomobject]@{ 说 = 'wcstoull 不与 wcstoul 合并'; 集 = @('wcstoul', 'wcstoull'); 期 = 2 }
        [pscustomobject]@{ 说 = 'nanf/nanl 不与 nan 合并（标准里是三个独立名字）'; 集 = @('nan', 'nanf', 'nanl'); 期 = 3 }
    )
    $bad = @()
    foreach ($c in $cases) {
        $n = @(Merge-Variants $c.集).Count
        if ($n -ne $c.期) { $bad += ("{0}：期望 {1} 个逻辑名，实得 {2} 个（{3}）" -f $c.说, $c.期, $n, (@(Merge-Variants $c.集) -join '/')) }
    }
    if ($bad.Count) {
        throw ("f/l 合并判据自测失败（见 §18.58）：`n  " + ($bad -join "`n  "))
    }
}

# ---------------------------------------------------------------- 硬边界（已确认，写死在生成器里）
# 为什么写死：这些是**结论**，不是从文件里能算出来的。每一条都附理由，
# 且都已在本仓台账里有据（方案 §3.4.1 / §3.11 / 关键字大检查报告 / 大检查问题台账）。
$boundaries = @(
    [pscustomobject]@{ 类别 = '同一个类型的内部拼写'; 例子 = '_Mbstatet（cwchar / cstdio 的缺口里各出现一次）'; 为什么 = '它就是 mbstate_t 本体（MSVC 的内部拼写）—— C 语言里是 `typedef _Mbstatet mbstate_t;` ⇒ 只给这一个类型起一个中文名（`多字节状态`），_Mbstatet 不再另起（§18.59）' }
    [pscustomobject]@{ 类别 = '宏：无法起别名'; 例子 = 'errno、EINVAL 等 E* 一族'; 为什么 = 'C 头里是宏，别名层只能给"名字"起别名，宏没有别名机制' }
    [pscustomobject]@{ 类别 = '宏：无法起别名'; 例子 = 'assert（cassert）'; 为什么 = '同上；且它在 NDEBUG 下会被整体抹掉' }
    [pscustomobject]@{ 类别 = '函数式宏：无法转发'; 例子 = 'va_start、va_arg、va_end、va_copy、setjmp'; 为什么 = '函数式宏不是函数，变参模板转发够不着（方案 §3.4.1 已登记）' }
    [pscustomobject]@{ 类别 = '宏：无法起别名'; 例子 = 'isfinite、isnan、isinf、signbit、fpclassify、isgreater 一族'; 为什么 = '在标准 C 里是宏；MSVC STL 虽以函数形式暴露，但换平台/换头就散架，不起中文名' }
    [pscustomobject]@{ 类别 = '标准已删除'; 例子 = 'gets'; 为什么 = 'C11 已删除，这套 STL 里 std::gets 根本不存在（实测编译报错）' }
    [pscustomobject]@{ 类别 = '别人的符号'; 例子 = '微软 UCRT / Windows DLL 里的导出符号'; 为什么 = '只能"加名字"不能"改名字"；中文名是新增层，原件一个字节不动' }
    [pscustomobject]@{ 类别 = '不做纯 C ⇒ 保持英文'; 例子 = '<threads.h>、<stdatomic.h>、<stdbit.h>、<stdnoreturn.h>、<stdckdint.h>'; 为什么 = '用户 2026-10-07 裁定不做纯 C（不加宏别名层）；这些是 C-only 头，别名层机制也够不着' }
)

# ---------------------------------------------------------------- 收集两侧数据
Test-MergeVariants   # 判据自测（**先跑它**：判据坏了就别出数字）
$stl = Find-StlDir $StlDir
$refAvailable = $null -ne $stl

$zhFiles = @(Get-ChildItem $zhDir -File | Sort-Object Name)
$cerrno = Join-Path $stdDir '错误号'
if (Test-Path $cerrno) { $zhFiles += Get-Item $cerrno }

$rows = @()
$sumSymRef = 0; $sumSymOurs = 0; $sumLogRef = 0; $sumLogOurs = 0
$sumType = 0; $sumFunc = 0; $sumMacro = 0
#  §18.65 口径修正：合计缺口**必须等于逐头缺口之和**（$sumMissing），
#  不能再用 `Σ参考 - Σ我们` —— 那个差会把"我们有、但参考集里根本没有的名字"
#  （宏 FLT_MAX/Eof、编译器内建 nullptr_t/max_align_t/byte、变量 va_list、C 函数 jmp_buf/longjmp …）
#  当成"销账"减掉。实测：Σ参考 364 - Σ我们 310 = 54，而逐头缺口之和是 **66**，差 12 就是这批名字。
$sumMissing = 0; $sumOursExtra = 0
$oursExtraNames = @()
$gaps = @()
$zeroNameHeaders = @()

foreach ($f in $zhFiles) {
    $raw = [System.IO.File]::ReadAllText($f.FullName)
    $code = Remove-Comments $raw
    $inc = ([regex]::Matches($code, '#include\s*<(?<h>c[a-z0-9_]+)>') | ForEach-Object { $_.Groups['h'].Value } | Select-Object -First 1)
    $zh = Get-ZhNames $f.FullName

    $typeN = @($zh.Values | Where-Object { $_.类 -eq '类型' }).Count
    $funcN = @($zh.Values | Where-Object { $_.类 -eq '函数' }).Count
    $macroN = @($zh.Values | Where-Object { $_.类 -eq '值宏' }).Count
    $sumType += $typeN; $sumFunc += $funcN; $sumMacro += $macroN

    $refNames = if ($refAvailable) { Get-RefNames $stl $inc } else { @() }
    $logRef = Merge-Variants $refNames
    $logOurs = Merge-Variants @($zh.Keys)
    $missing = @($logRef | Where-Object { $zh.Keys -notcontains $_ })

    $sumSymRef += $refNames.Count
    $sumSymOurs += $zh.Count
    $sumLogRef += $logRef.Count
    $sumLogOurs += $logOurs.Count
    #  逐头累计：缺口 + "我们的名字里参考集没有的"
    $sumMissing += $missing.Count
    $extra = @($zh.Keys | Where-Object { $logRef -notcontains $_ })
    $sumOursExtra += $extra.Count
    if ($extra.Count -gt 0) { $oursExtraNames += [pscustomobject]@{ 头 = $f.Name; 名字 = $extra } }

    if ($zh.Count -eq 0) { $zeroNameHeaders += $f.Name }
    if ($missing.Count -gt 0) { $gaps += [pscustomobject]@{ 头 = $f.Name; 英文 = $inc; 缺 = $missing } }

    $rows += [pscustomobject]@{
        头 = $f.Name; 英文 = $inc
        类型 = $typeN; 函数 = $funcN; 值宏 = $macroN; 合计 = $zh.Count
        参考符号 = $refNames.Count; 参考逻辑 = $logRef.Count; 缺逻辑 = $missing.Count
    }
}

# ---------------------------------------------------------------- 口径自检（判据要能失败）
#  §18.65：合计缺口必须同时满足两条 ——
#    ① 逐头缺口之和（这是"还缺多少对(头,名字)"的定义）；
#    ② 恒等式 Σ参考 = Σ我们 + Σ缺口 − Σ(我们多出来的)。
#  两条对不上就抛错：说明某处把"我们有但参考没有的名字"算进了销账（§18.65 修掉的正是这个）。
if ($refAvailable) {
    $lhs = $sumMissing
    $rhs = $sumLogRef - $sumLogOurs + $sumOursExtra
    if ($lhs -ne $rhs) {
        throw ("C 库台账口径自检失败（§18.65）：逐头缺口之和 {0} ≠ Σ参考 {1} − Σ我们 {2} + 我们多出来的 {3} = {4}" -f `
            $lhs, $sumLogRef, $sumLogOurs, $sumOursExtra, $rhs)
    }
}

# ---------------------------------------------------------------- 渲染
$L = New-Object System.Collections.Generic.List[string]
function W([string]$s) { $L.Add($s) }

W '# C 库汉化台账（C 线覆盖盘点）'
W ''
W '> **本文件是自动生成的，不要手改。**'
W '> 由 `tools\make_c_ledger.ps1` 从盘上的真文件算出来（单一真相），'
W '> 并由闸门里的守卫用 `-Check` 核对 —— **手改或不重新生成都会被抓出来**。'
W ''
W '用户 2026-10-07 裁定：**不做纯 C**（不新增宏别名层），只把 Chinese++ 现有的'
W '「C 包装头」别名层（`zhstdlib\C运行库\`）做扎实，并要求先有一份盘点。'
W ''
W '## 一、两侧数据来源'
W ''
W '| 侧 | 来源 |'
W '|---|---|'
W '| 我们 | `zhstdlib\C运行库\` 的 25 个中文 C 包装头 + `zhstdlib\标准库\错误号`（cerrno），共 **26** 个头 |'
if ($refAvailable) {
    W ('| 参考 | `' + $stl.Replace($root + '\', '') + '` 里各 `cXXX` 的 `using _CSTD <名字>;` 名单 —— 那是 MSVC STL 把 C 名字搬进 `std` 的**全集**，也就是"可以起中文名"的全集 |')
} else {
    W '| 参考 | ❌ **参考基准（`lib\stl`）不在盘上** —— 本次只出台账的"我们做了什么"那一半，缺口列留空（打包产物的目录不入库，属正常） |'
}
W ''
W '## 二、两种口径（别混，混了会把缺口放大近一倍）'
W ''
W '| 口径 | 含义 | 为什么需要它 |'
W '|---|---|---|'
W '| **符号口径** | `acos` / `acosf` / `acosl` 各算一个 | 这是 STL 暴露符号的方式，用来对拍参考集的**规模** |'
W '| **逻辑口径** | 把 `f`/`l` 变体合并成一个逻辑函数 | 我们的机制是**变参模板转发**：**一个中文名覆盖整族重载** ⇒ 逻辑口径才是**真实工作量** |'
W ''
W '合并的边界（`tools\make_c_ledger.ps1` 的 `Merge-Variants`，自带自测）：'
W ''
W '* **合**：`acosf`/`acosl` → `acos`（`<cmath>` 里是**同一个重载名**，一个中文名转发过去就全覆盖）；'
W '  基名以 `l`/`f` 结尾也照合（`ceill` → `ceil`、`modff` → `modf`）。'
W '* **判据**：**整族存在**才算重载族 —— `X`、`Xf`、`Xl` 三个名字都在参考集里才合并。'
W '* **不合**：`strtoll` / `atoll` / `wcstoull`（要 `strtol`+`strtolf`+`strtoll` 三个都在才算族，'
W '  而 `strtolf` 这类名字**根本不存在** ⇒ 它们是 **long long 版的另一个函数**，不是重载）；'
W '  以及 `nanf`/`nanl`（三个名字齐、看着像族，但标准里 `nan`/`nanf`/`nanl` 是**三个独立名字** ⇒ 显式例外）。'
W ''
W '> ⚠ 这两条例外是**修正后**的（§18.58）：第一版判据把 `ll` 当成了 `l` 变体、把 `nanf` 当成 `nan` 的重载，'
W '> **缺口少算 7 个**且表面完全正常。现在判据自带 `Test-MergeVariants` 自测，改坏就当场抛错。'
W ''
W '## 三、逐头明细（我们做了什么）'
W ''
W '| 中文头 | 英文头 | 类型 | 函数 | 值宏 | 我们合计 | 参考符号 | 参考逻辑 | 缺（逻辑） |'
W '|---|---|---|---|---|---|---|---|---|'
foreach ($r in ($rows | Sort-Object -Property @{Expression = '缺逻辑'; Descending = $true }, 头)) {
    W ("| `{0}` | `{1}` | {2} | {3} | {4} | **{5}** | {6} | {7} | {8} |" -f `
        $r.头, $r.英文, $r.类型, $r.函数, $r.值宏, $r.合计, $r.参考符号, $r.参考逻辑, $r.缺逻辑)
}
W ("| **合计** |  | **{0}** | **{1}** | **{2}** | **{3}** | **{4}** | **{5}** | **{6}** |" -f `
    $sumType, $sumFunc, $sumMacro, ($sumType + $sumFunc + $sumMacro), $sumSymRef, $sumLogRef, $sumMissing)
W ''
W ('**一句话**：头覆盖 **{0}/26**；我们起了 **{1}** 个中文名（类型 {2} / 函数 {3} / 值宏 {4}）；' -f `
    $zhFiles.Count, ($sumType + $sumFunc + $sumMacro), $sumType, $sumFunc, $sumMacro)
if ($refAvailable) {
    W ('按逻辑口径，参考全集 **{0}**、已覆盖 **{1}**、**还缺 {2}**；按符号口径参考 **{3}**（含 f/l 变体，会把缺口放大，别拿它对工作量）。' -f `
        $sumLogRef, ($sumLogRef - $sumMissing), $sumMissing, $sumSymRef)
    W ''
    W ('> ⚠ **口径**：`还缺 {0}` = **逐头缺口之和**（{1} 个头的缺相加），**不是** `Σ参考 − Σ我们`。' -f $sumMissing, @($rows | Where-Object { $_.缺逻辑 -gt 0 }).Count)
    W ('> 两者差 **{0}**，因为我们的名字里有 {0} 个**参考集里根本没有**（宏 `FLT_MAX`/`Eof`、' -f $sumOursExtra)
    W '> 编译器内建 `nullptr_t`/`max_align_t`/`byte`、变量 `va_list`、C 函数 `jmp_buf`/`longjmp`…）——'
    W '> 它们**既不是缺口、也不该被当成销账**。（§18.65 修正；此前的 218/159/115/86/70/54 都少了这 12。）'
}
W ''
if ($zeroNameHeaders.Count -gt 0) {
    W ('**零名字的头**（{0} 个）：{1}' -f $zeroNameHeaders.Count, (($zeroNameHeaders | ForEach-Object { '`' + $_ + '`' }) -join '、'))
    W ''
    W '其中绝大多数**本来就转不了**：内容全是宏（`errno`/`assert`）、或已是关键字（`bool`/`alignas`/`and`）、'
    W '或该头在 C++ 里是空的（`ctgmath`/`ccomplex`，名字在别处）。**例外是真欠账**，逐条见第五节。'
    W ''
}
W '## 四、缺口清单（还缺什么，按头分组）'
W ''
if (-not $refAvailable) {
    W '（参考基准不在盘上，本次不出缺口清单。跑 `pwsh -File tools\make_c_ledger.ps1` 前先有发行包，或传 `-StlDir`。）'
} elseif ($gaps.Count -eq 0) {
    W '**没有缺口** —— 参考集里的名字全部有中文名。'
} else {
    W '口径：逻辑名（已合并 `f`/`l` 变体）。**其中有些是宏**（转不了，见第五节），'
    W '这里一律列出以便逐条判断，不作自动过滤。'
    W ''
    foreach ($g in ($gaps | Sort-Object -Property @{Expression = { $_.缺.Count }; Descending = $true })) {
        W ('* **`{0}`**（`{1}`，缺 {2}）：{3}' -f $g.头, $g.英文, $g.缺.Count, (($g.缺 | ForEach-Object { '`' + $_ + '`' }) -join ' '))
    }
}
W ''
W '## 五、硬边界（做不了的，别当欠账）'
W ''
W '| 类别 | 例子 | 为什么 |'
W '|---|---|---|'
foreach ($b in $boundaries) { W ("| {0} | {1} | {2} |" -f $b.类别, $b.例子, $b.为什么) }
W ''
W '## 六、怎么复现'
W ''
W '```powershell'
W 'pwsh -File tools\make_c_ledger.ps1            # 重新生成本台账'
W 'pwsh -File tools\make_c_ledger.ps1 -Check     # 只核对（闸门守卫调它）'
W '```'
W ''
W '参考基准的定位顺序：`vendor\stl` → `build\include` → `dist\Chinese++-*\lib\stl`，'
W '也可用 `-StlDir` 显式指定。**找不到就如实跳过**（退出码 2），不算失败。'
W ''

$text = ($L -join "`n") + "`n"

# ---------------------------------------------------------------- 写盘 / 核对
if ($Check) {
    if (-not (Test-Path $outPath)) { throw "缺少 $outPath，请先运行 tools\make_c_ledger.ps1" }
    $cur = [System.IO.File]::ReadAllText($outPath)
    if ($cur -ne $text) {
        throw ("C 库汉化台账与盘上的文件不一致：$outPath`n" +
               "  请运行 pwsh -File tools\make_c_ledger.ps1 并提交结果。")
    }
    Write-Host ("C 库汉化台账与文件一致（{0} 行；头 {1} 个、中文名 {2} 个）" -f `
        ($text -split "`n").Count, $zhFiles.Count, ($sumType + $sumFunc + $sumMacro))
    exit 0
}

[System.IO.File]::WriteAllText($outPath, $text)
Write-Host ("已生成 {0}（{1} 行；头 {2} 个、中文名 {3} 个、缺（逻辑）{4} 个 = 逐头缺口之和；另有 {5} 个名字参考集里没有）" -f `
    $outPath, ($text -split "`n").Count, $zhFiles.Count, ($sumType + $sumFunc + $sumMacro), $sumMissing, $sumOursExtra)
