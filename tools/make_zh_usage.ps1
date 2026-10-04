# ============================================================================
#  make_zh_usage.ps1 -- 生成【汉语标准库 · 用法对照表】
#
#  为什么必须【生成】而不是手写（用户 2026-09-28 问："这些库的用法的记录是否同步更新？"）：
#    实测当时 docs\使用说明.md 还写着「`#包含 <向量>` **现在会找不到文件**」，
#    并教用户手写一个别名头 —— 而那时 zhstdlib 里已经有 67 个产品、
#    `#包含 <向量>` 早就能用了。**手写的用法记录一定会漂移**，
#    而且漂移的方向是"让读者相信一件已经过时的事"，比没有文档更坏。
#    （同 §16.34.2：注释里写理由必须能被查证。）
#
#  单一事实来源：三个生成器的【表】。本脚本通过它们的 -ExportJson 开关拿表
#  （PowerShell 自己解析出来的同一张表），**不靠正则扫描** —— 扫描正则会漂移
#  （§16.31 的键名漏 `.`、§16.36 的假残留，都是扫描正则出的问题）。
#
#  用法：
#      powershell -File tools\make_zh_usage.ps1          # 生成/更新文档
#      powershell -File tools\make_zh_usage.ps1 -Check   # 只核对（陈旧则退出码 1）
#  regen_zhstdlib.ps1 里跑的是 -Check —— 这样"文档忘了同步"会变成一条【守卫】，
#  而不是靠我记得。
# ============================================================================
param([switch] $Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$utf8 = New-Object System.Text.UTF8Encoding($false)
$outPath = Join-Path $root 'docs\标准库汉化\汉语标准库-用法.md'

function Get-Table([string] $script) {
    $json = & pwsh -NoProfile -File (Join-Path $root "tools\$script") -ExportJson 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$script -ExportJson 失败" }
    return (($json -join "`n") | ConvertFrom-Json)
}

$main  = Get-Table 'make_zhstdlib2.ps1'
$alias = Get-Table 'make_zhalias.ps1'
$cwrap = Get-Table 'make_zhc.ps1'

$out = New-Object System.Collections.Generic.List[string]
function W([string] $s) { $out.Add($s) }

# 把一个 hashtable 的 键->值 渲染成 `中文`←`英文`
function RenderPairs($h) {
    if ($null -eq $h) { return '' }
    $parts = @()
    foreach ($p in $h.PSObject.Properties) { $parts += ('`{0}`←`{1}`' -f $p.Value, $p.Name) }
    return ($parts -join '、')
}
function RenderList($arr) {
    if ($null -eq $arr) { return '' }
    return (@($arr) -join '、')
}

W '# 汉语标准库 · 用法对照表'
W ''
W '> ⚠ **本文件是自动生成的，不要手改。**'
W '> 它由 `tools\make_zh_usage.ps1` 从三个生成器的表里生成（单一事实来源 = 那三张表）；'
W '> `tools\regen_zhstdlib.ps1` 每次全量重生成都会用 `-Check` 核对它 ——'
W '> **手改或不重新生成，都会被抓出来**（方案 §16.40）。'
W '> 本文件刻意**不写生成时间**：写了就每次都"变"，守卫就没法用了。'
W ''
W '## 一、三句话学会用'
W ''
W '1. **头名用汉语**：`#包含 <向量>`。只写它，`标准::向量<整数>` 与 `std::vector<int>` 同时可用'
W '   —— 后者是微软原件，一个字节没动（铁律 ①）。'
W '2. **中文在前、英文在后**：`标准::向量<整数>::值类型` 与 `::value_type` 都对。'
W '3. **两个类型不互通**：`标准::向量` 与 `std::vector` 布局相同但是**两种类型**，不能直接互相传参'
W '   —— 这是"实现本身是汉语的"必须付的代价，详见方案 §16.29.3。'
W ''
W '另有可编译的完整示例：`examples\汉语库示例.cpp`（它是总判据的一部分，必须整体编过）。'
W ''

# ---------------------------------------------------------------------------
# 二、抄+派生轨道
# ---------------------------------------------------------------------------
$mainEntries = @($main.PSObject.Properties)
$pubEntries = @($mainEntries | Where-Object { $_.Value.pub -or $_.Value.tests })
W ('## 二、抄+派生轨道（{0} 个：{1} 个公开头 + 内部件）' -f $mainEntries.Count, $pubEntries.Count)
W ''
W '这一轨道的做法：整段抄一份微软的实现 → 搬进 `标准::细节` → 名字全部改成汉语 →'
W '再在 `标准::` 下派生一层，把英文原名补回来。'
W ''
W '| 中文头 | 源头 | 对外中文类型 | 该条登记的类型名 | 成员名 |'
W '|---|---|---|---|---|'
foreach ($p in ($mainEntries | Sort-Object Name)) {
    $e = $p.Value
    $cls = if ($e.pub) { $e.pub } else { $e.zh }
    $types = RenderPairs $e.types
    $members = RenderPairs $e.members
    if ($types.Length -gt 160) { $types = $types.Substring(0, 160) + ' …' }
    if ($members.Length -gt 220) { $members = $members.Substring(0, 220) + ' …' }
    W ('| `#包含 <{0}>` | `{1}` | `标准::{2}` | {3} | {4} |' -f $e.zh, $p.Name, $cls, $types, $members)
}
W ''
W '> 表里"该条登记的类型名 / 成员名"只列了**生成器表里登记的**那些；'
W '> 派生层还额外补回了一批英文原名（`使用 <英文> = 基类::<中文>;`），'
W '> 所以**同一个对象的两种名字都能用**。'
W '> 各头自己的真测试（`tools\make_zhstdlib2.ps1 -Header <源头>` 的最后一行 `N / N`）'
W '> 就是"两种名字都可用"的机器保证。'
W ''

# ---------------------------------------------------------------------------
# 三、别名轨道
# ---------------------------------------------------------------------------
$aliasEntries = @($alias.PSObject.Properties)
W ('## 三、别名轨道（{0} 个：类型身份参与语义，只能用别名）' -f $aliasEntries.Count)
W ''
W '这些头的类型**不能抄也不能派生**（铁律 ③）：异常捕获、RTTI、结构化绑定、'
W '编译器转写都要求"就是 `std` 里那一个类型"。所以这里只加中文别名，指向 `std` 的原类型。'
W ''
foreach ($p in ($aliasEntries | Sort-Object Name)) {
    $e = $p.Value
    W ('### `#包含 <{0}>`  ← 源头 `{1}`' -f $e.zh, $p.Name)
    $lines = @()
    foreach ($item in @($e.a)) {
        $k = [string]$item[0]
        switch ($k) {
            '类型' { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
            '常量' { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
            '函数' { $lines += ('`{0}()`←`{1}()`' -f $item[1], $item[2]) }
            '原样' { $lines += ('（原样发出）`{0}`' -f $item[1]) }
            default { $lines += ('`{0}`' -f ($item -join ' ')) }
        }
    }
    W ('- {0}' -f ($lines -join '、'))
    W ''
}

# ---------------------------------------------------------------------------
# 四、C 包装头（不含系统头 —— §18.21 起这张表里还有 windows.h，它单列第五节）
# ---------------------------------------------------------------------------
$cEntries   = @($cwrap.PSObject.Properties | Where-Object { $_.Value.kind -ne '系统头' })
$sysEntries = @($cwrap.PSObject.Properties | Where-Object { $_.Value.kind -eq '系统头' })
W ('## 四、C 包装头（{0} 个：把 C 库名字搬进 `std` 的那些头）' -f $cEntries.Count)
W ''
W '这些头自己没有实现，只是把 C 库名字搬进 `std`；`size_t` / `FILE` 这类**必须与全局同一个类型**。'
W ''
foreach ($p in ($cEntries | Sort-Object Name)) {
    $e = $p.Value
    W ('### `#包含 <{0}>`  ← 源头 `{1}`' -f $e.zh, $p.Name)
    $lines = @()
    foreach ($item in @($e.a)) {
        $k = [string]$item[0]
        switch ($k) {
            '类型' { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
            '函数' { $lines += ('`{0}()`←`{1}()`' -f $item[1], $item[2]) }
            '宏'   { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
            '值宏' { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
            # §18.20：函数式宏（va_start 一家）只能 #定义，名字**不在** `标准` 名域里 ——
            #   这里的「（宏，不加 标准::）」是给读者的用法提示，不是装饰。
            '函数式宏' { $lines += ('`{0}`（宏，不加 `标准::`）←`{1}`' -f $item[1], $item[2]) }
            default { $lines += ('`{0}`' -f ($item -join ' ')) }
        }
    }
    W ('- {0}' -f ($lines -join '、'))
    W ''
}

# ---------------------------------------------------------------------------
# 五、系统头（Windows 系统 API）—— §18.21
#
#  为什么单列：它不是"把 C 库名字搬进 std"，而是"给 Win32 名字加一层中文名"；
#  别名没有 std:: 前缀、函数直接转发全局原名，混进第四节会让读者以为 windows.h
#  是标准库的一部分。分节的判据是生成器表里的 kind 字段（不是手写清单）。
# ---------------------------------------------------------------------------
if ($sysEntries.Count) {
    W ('## 五、Windows 系统 API（{0} 个：给 Win32 名字加一层中文名）' -f $sysEntries.Count)
    W ''
    W '这一节的头**不是标准库头**：源头是系统 SDK（`windows.h`），那些名字住在**全局名域**，'
    W '所以别名没有 `std::` 前缀，函数用同一条转发模板直接调 Win32 原名。'
    W ''
    W '三条注意（每条都有实测判据，见方案 §3.4.2）：'
    W ''
    W '1. **一律指向显式的 `…W` 真函数**：Win32 里 `CreateFile` / `WriteConsole` / `GetModuleHandle`'
    W '   这类"函数"其实是宏，宏会被展开、不能转发。'
    W '2. **产品头自己兜住 `NOMINMAX` 与 `WIN32_LEAN_AND_MEAN`**：不给它们，`windef.h` 的 `min/max`'
    W '   宏与 `rpcndr.h` 的 `byte` 会拆坏标准库头（组合探针实测各 20 条错）。'
    W '3. **只加名字，不改行为**：值宏直接引 SDK 自己的宏（`STD_OUTPUT_HANDLE` 等），不重写定义。'
    W ''
    foreach ($p in ($sysEntries | Sort-Object Name)) {
        $e = $p.Value
        W ('### `#包含 <{0}>`  ← 源头 `{1}`' -f $e.zh, $p.Name)
        $lines = @()
        foreach ($item in @($e.a)) {
            $k = [string]$item[0]
            switch ($k) {
                '类型' { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
                '函数' { $lines += ('`{0}()`←`{1}()`' -f $item[1], $item[2]) }
                '宏'   { $lines += ('`{0}`←`{1}`' -f $item[1], $item[2]) }
                '函数式宏' { $lines += ('`{0}`（宏，不加 `标准::`）←`{1}`' -f $item[1], $item[2]) }
                default { $lines += ('`{0}`' -f ($item -join ' ')) }
            }
        }
        W ('- {0}' -f ($lines -join '、'))
        W ''
    }
}

W '---'
W ''
W ('**覆盖**：抄+派生 {0} 个、别名 {1} 个、C 包装 {2} 个、Windows 系统 {3} 个，共 {4} 个中文头。' -f `
    $mainEntries.Count, $aliasEntries.Count, $cEntries.Count, $sysEntries.Count, ($mainEntries.Count + $aliasEntries.Count + $cEntries.Count + $sysEntries.Count))
W ''
W '**还缺什么**（不要说"做完了"）：'
W ''
W '- **Windows 系统 API 已做三批 69 个名字**：第一批 32 个（句柄 / 控制台 / 文件 / 进程线程 / 错误码）、'
W '  第二批 19 个（同步对象：事件 / 互斥量 / 信号量 / 临界区）、第三批 18 个（内存：虚拟内存 / 堆）；'
W '  注册表与环境变量、动态库、时间与性能计数**还没做** ——'
W '  这一项记在 `docs\汉字第一公民-路线图.md` 第 4 项（C 运行库那一半已完成，§18.19/§18.20）。'
W '- 步骤 1 的内部件：34 个里做完 3 个（`调用一次` / `特殊成员控制` / `内存内部件`），'
W '  2 个判为边界（`xthreads.h` / `xpolymorphic_allocator.h`），其余未开始；'
W '- 进度数字由 `tools\audit_hanhua.ps1` 给出（顶层类型名汉化率 / 嵌套名汉化率），'
W '  不写死在这里 —— 写死了就会漂移。'
W '- **每一处的"还没做"都记在 `docs\标准库汉化\标准库汉化方案.md` 里，附消除路径。**'

$text = ($out -join "`n") + "`n"

if ($Check) {
    if (-not (Test-Path $outPath)) {
        Write-Host "❌ 用法对照表不存在：$outPath（跑 tools\make_zh_usage.ps1 生成）" -ForegroundColor Red
        exit 1
    }
    $old = [System.IO.File]::ReadAllText($outPath)
    if ($old -ne $text) {
        Write-Host "❌ 用法对照表【已过期】：$outPath" -ForegroundColor Red
        Write-Host "   它与三个生成器的表已经不一致（有人改了表但没重新生成文档，或者手改了文档）。" -ForegroundColor Yellow
        Write-Host "   修法：pwsh -File tools\make_zh_usage.ps1  然后一起提交。" -ForegroundColor Yellow
        exit 1
    }
    Write-Host ("用法对照表：最新（{0} 行）" -f $out.Count) -ForegroundColor Green
    exit 0
}

[System.IO.File]::WriteAllText($outPath, $text, $utf8)
Write-Host ("写入 {0}（{1} 行）" -f $outPath, $out.Count) -ForegroundColor Green
