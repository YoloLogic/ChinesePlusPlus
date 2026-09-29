# ============================================================================
#  regen_zhstdlib.ps1 -- 重新生成【全部】中文头，然后全量验证
#
#  为什么必须有一个（这是第 17 轮暴露的过程缺陷，比当时那个 bug 更值钱）：
#    全量验证验证的是【产物】，不是【生成器】。生成器改过之后，旧产物还躺在
#    zhstdlib 里，验证照样全绿 —— 而"重新生成"会得到坏文件。
#    实测那次：步 4c 的判据修正之前，verify 仍报 42/42，但重新生成 stack 就坏。
#
#  => 规矩：**改过任何生成器之后，先跑本脚本，再谈别的。**
#
#  表项是从两个生成器里【扫出来的】，不是手写的清单 —— 手写的清单一定会漂移。
#  用法：
#      powershell -File tools\regen_zhstdlib.ps1
#      powershell -File tools\regen_zhstdlib.ps1 -Exclude condition_variable
#
#  历史：`condition_variable` 曾长期挂在默认 -Exclude 里 —— 因为 <condition_variable>
#  里 `condition_variable_any` 与 <mutex> 里的 `friend condition_variable_any;` 是
#  跨头的一对名字，<mutex> 没抄下来之前，friend 指不到东西（见方案 §3.6）。
#  <mutex> 完成后（commit c25e03b），两者同处 `标准::细节`，friend 自动对上，故解封。
# ============================================================================
param([string[]] $Exclude = @())

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
# §16.56：真实用例守卫要用编译器（其余守卫都由各自的脚本自带）。
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 从生成器里扫表项：形如   'header' = @{   或   'header' = @{ zh = ...（单行/多行两种写法）
# 不能用"zh 必须同行"的正则 —— make_zhstdlib2.ps1 的条目是多行的，会一个都扫不到。
# ⚠ 键名允许带 '.' —— 内部件的键就是文件名形态（'xcall_once.h' / 'xsmf_control.h'）。
#   原来这里写成 [a-z0-9_]* ，于是这两个条目【从来没被重生成过】：
#   regen 报"25 个表项"，而表里实际有 27 个。这正是本脚本开头自己警告的那种故障
#   （"改了生成器但没人重生成它们"），只不过那次漏的是 26 个 C 包装头，这次漏的是 2 个内部件。
#   判据：**扫描用的正则必须能匹配表里所有合法的键形态**，否则"全量"就是假的。
function Get-Entries([string]$file) {
    $out = @()
    foreach ($line in [System.IO.File]::ReadAllLines($file)) {
        # ⚠ §17.19.1：键名【可以是中文】（薄壳条目就叫 '字符串'）。原来这里是
        #   [a-z_][a-z0-9_.]*，于是中文条目一个都扫不到 —— 又一次"全量是假的"。
        #   判据同上：扫描用的正则必须能匹配表里所有合法的键形态。
        # ⚠ 判据：**顶层条目恰好缩进两空格**，条目【内部嵌套表】是四空格（如
        #   `'_标记' = @{ names = @('_Tag', '_Mark') }`）。第一版放宽成任意缩进后，
        #   6 个嵌套键被当成表项 -> regen 里出现 6 个"表里没有 _标记"的假失败。
        if ($line -match "^  '([^']+)'\s*=\s*@\{") { $out += $Matches[1] }
    }
    return $out
}

$jobs = @(
    # make_zhc.ps1 一次生成【全部 26 个 C 包装头】，没有 -Header 参数 —— 单独一次。
    # ⚠ 它是 2026-09-27 才补进来的：在此之前 26 个甲类头【不在】本脚本名单里，
    #   也就是"改了生成器但没人重生成它们"（正是本脚本存在的理由，却漏了一半）。
    @{ Script = 'make_zhc.ps1';        Once    = $true },
    @{ Script = 'make_zhalias.ps1';    Entries = (Get-Entries (Join-Path $root 'tools\make_zhalias.ps1'))    },
    @{ Script = 'make_zhstdlib2.ps1';  Entries = (Get-Entries (Join-Path $root 'tools\make_zhstdlib2.ps1'))  }
)

$fail = 0
# 生成器告警台账 + 「乙」探针计数（见循环里的说明：这两样原先都被本脚本吞掉）
# ---------------------------------------------------------------------------
#  §17.27.72 **两遍法**：第一遍只把全部产品刷到最新（不计失败），第二遍才逐条目测试并判定。
#
#  为什么（round 18 实测，直接证据）：逐条目生成+测试是【顺序敏感】的 ——
#  排序在前的条目（unordered_map/unordered_set）会拿**旧的**依赖产品（哈希内部件）去测，
#  于是同一个改动"全量跑是红、单独跑（依赖已刷新）是绿"，甚至能提交出"下一遍自己会拒绝"的状态。
#  判据：**生成与判定必须分成两遍** —— 先让全部产品落盘，再谈通过与否。
#  代价：regen 时间约翻倍（可接受：宁可慢，也不能让判定依赖磁盘旧状态）。
# ---------------------------------------------------------------------------
$preCount = 0
foreach ($j in $jobs) {
    if ($j.Once) { continue }
    foreach ($h in @($j.Entries | Where-Object { $Exclude -notcontains $_ } | Sort-Object)) {
                $env:ZH_NO_TEST = '1'
& pwsh -NoProfile -File (Join-Path $root "tools\$($j.Script)") -Header $h *> $null
        Remove-Item Env:\ZH_NO_TEST -ErrorAction SilentlyContinue
        $preCount++
    }
}
Write-Host ("=== 预热第一遍（只落盘、不判定）：{0} 个表项 ===" -f $preCount) -ForegroundColor DarkGray
$warnTotal = 0
$warnRows = @()
$riOk = 0
foreach ($j in $jobs) {
    if ($j.Once) {
        Write-Host ("=== {0}  (一次生成全部) ===" -f $j.Script) -ForegroundColor Cyan
        $o = & pwsh -NoProfile -File (Join-Path $root "tools\$($j.Script)") 2>&1
        $last = ([string]($o | Select-Object -Last 1)).Trim()
        # make_zhc.ps1 的收尾行是「  通过 25 / 25」，带前缀 —— 所以取行尾的 N / M
        $ok = ($last -match '(\d+)\s*/\s*(\d+)\s*$') -and ($Matches[1] -eq $Matches[2])
        if (-not $ok) { $fail++ }
        Write-Host ("  {0,-22} {1}   {2}" -f $j.Script, $(if ($ok) { 'ok  ' } else { 'FAIL' }), $last) `
            -ForegroundColor $(if ($ok) { 'Gray' } else { 'Yellow' })
        Write-Host ''
        continue
    }
    $list = @($j.Entries | Where-Object { $Exclude -notcontains $_ } | Sort-Object)
    Write-Host ("=== {0}  ({1} 个表项) ===" -f $j.Script, $list.Count) -ForegroundColor Cyan
    foreach ($h in $list) {
        $o = & pwsh -NoProfile -File (Join-Path $root "tools\$($j.Script)") -Header $h 2>&1
        $last = ([string]($o | Select-Object -Last 1)).Trim()
        # -------------------------------------------------------------------
        #  ⚠ 【守卫必须在 regen 输出里显式可见】—— 这条本脚本自己违反了两次。
        #
        #  第一次（§16.30）：只取 `Select-Object -Last 1`，于是生成器打到中间的
        #  「⚠ 改回英文: X（第 N 行）」全被吞掉 —— 我据此说"全库 0 回退"，
        #  而实际 <向量> 里 `_Ilist.begin()` / `_Ilist.end()` 一直是英文。
        #  当时我只按"改回英文"这一种消息去补。
        #
        #  第二次（§16.32）：接着加了「顺带引真头探针: 通过…」，**它又被吞了** ——
        #  同一个病，我又只治了一个症状。
        #
        #  所以这里改成【按类别收】而不是按消息逐条补：
        #    · 凡是生成器输出的 ⚠ / ❌ 行，一律收进"生成器告警台账"；
        #    · 凡是通过型的守卫行（顺带引真头探针 …），计数并汇总。
        #  判据：**新加的守卫不需要再改 regen，就能自动出现在这里。**
        # -------------------------------------------------------------------
        $warns = @($o | Where-Object { $_ -match '⚠|❌' } | ForEach-Object { ([string]$_).Trim() })
        if ($warns.Count) {
            $script:warnTotal += $warns.Count
            foreach ($w in $warns) { $script:warnRows += ("  {0,-22} {1}" -f $h, $w) }
        }
        if (@($o | Where-Object { $_ -match '顺带引真头探针: 通过' }).Count) { $script:riOk++ }
        # 生成器里的"跨头译名一致性检查"（方案 §3.11）输出会被这里捕获而看不见，
        # 隐形规矩等于没有规矩 —— 所以对每个脚本的第一个头把它显式打出来一行。
        #  §17.27.54：加"译名唯一性检查"（同一个译名不许对应两个英文名）。
        #  这是 §16.30/§16.32 那条判据的第三次自查：**新守卫必须自己进这个名单**，
        #  否则就是"新加的守卫在 regen 里看不见"。
        if ($h -eq $list[0]) {
            $ck = @($o | Where-Object { $_ -match '跨头译名检查|跨头译名不一致|关键词表检查|撞上关键词|译名唯一性检查|译名撞车' }) | Select-Object -First 3
            foreach ($c in $ck) { Write-Host ("  {0}" -f ([string]$c).Trim()) }
        }
        $ok = ($last -match '^(\d+) / \1$') -or ($last -match '全部通过') -or ($last -match '^([0-9]+) / ([0-9]+)$' -and $Matches[1] -eq $Matches[2])
        if (-not $ok) { $fail++ }
        Write-Host ("  {0,-22} {1}   {2}" -f $h, $(if ($ok) { 'ok  ' } else { 'FAIL' }), $last) `
            -ForegroundColor $(if ($ok) { 'Gray' } else { 'Yellow' })
    }
    Write-Host ''
}

Write-Host "=== 全量验证 ===" -ForegroundColor Cyan
& pwsh -NoProfile -File (Join-Path $root 'tools\verify_zhstdlib.ps1')
$v = $LASTEXITCODE

# ---------------------------------------------------------------------------
#  用法对照表守卫（§16.40）—— **文档也必须由机器守**。
#
#  为什么加它：用户 2026-09-28 问"这些库的用法的记录是否同步更新？"，
#  一查就发现 docs\使用说明.md 还写着「`#包含 <向量>` **现在会找不到文件**」，
#  并教读者手写一个别名头 —— 而那时 zhstdlib 里已经有 67 个产品、
#  `#包含 <向量>` 早就能用了。
#  **手写的用法记录一定会漂移**，而且漂移方向是"让读者相信一件已经过时的事"，
#  比没有文档更坏（同 §16.34.2）。
#
#  现在用法对照表由 tools\make_zh_usage.ps1 从三张表【自动生成】，
#  这里只核对它是否最新 —— 于是"文档忘了同步"变成一条守卫，而不是靠我记得。
# ---------------------------------------------------------------------------
Write-Host "=== 用法对照表守卫 ===" -ForegroundColor Cyan
& pwsh -NoProfile -File (Join-Path $root 'tools\make_zh_usage.ps1') -Check
$ud = $LASTEXITCODE

# ---------------------------------------------------------------------------
#  铁律① 守卫（§16.42）——**微软原库一个字节都没动**。
#
#  为什么加它：用户 2026-09-28 问"原本的英语库都没动吧"。查下来确实没动
#  （361 个文件的修改时间全部早于项目起点 2026-09-23，脚本里对原头目录只有读操作），
#  但那条铁律一直是靠"我们只读它"这个【约定】维持的 —— **约定不是守卫**。
#  本项目反复吃过"靠我记得"的亏（§15.1 / §16.30 / §16.31），所以最要紧的这条铁律
#  也必须由机器来守：逐文件比对 SHA256（**用内容而不是时间戳** —— 时间戳可以恢复，内容不会）。
# ---------------------------------------------------------------------------
Write-Host "=== 铁律① 守卫（微软原库未动）===" -ForegroundColor Cyan
& pwsh -NoProfile -File (Join-Path $root 'tools\verify_originals.ps1')
$og = $LASTEXITCODE

# ---------------------------------------------------------------------------
#  真实用例守卫（§16.56）—— 目标里的【总判据第一条】必须由机器守。
#
#  目标的判据原文：「`examples\汉语库示例.cpp` 这个**真实用例整体编过**」。
#  但它一直只是我在提交前**手敲一次** —— 项目反复吃过"靠我记得"的亏
#  （§15.1 / §16.30 / §16.31 / §16.42），最要紧的这一条更不能例外。
#
#  为什么它比"单头测试"更强：单头测试是【每个头各写一段小程序】，
#  而真实用例是**一个文件里把多个头一起用**（向量/字符串/链表/映射/可选/线程/位集…），
#  照出来的是"头与头之间的组合"问题 —— 组合探针只做【语法】检查（`-fsyntax-only`），
#  这一条做的是**真正生成代码**（`-c` 出目标文件），模板实例化全部走完。
#
#  ⚠ 用 `-c` 不用 `-fsyntax-only`：后者不实例化所有模板成员函数。
#    实测签名：编过 = 0 错误（允许 -Wmicrosoft-template 这类警告），并打印对象字节数
#    —— 字节数是"真的生成了代码"的凭据，写进台账，防止哪天退化成空编译。
# ---------------------------------------------------------------------------
Write-Host "=== 真实用例守卫（examples\汉语库示例.cpp）===" -ForegroundColor Cyan
$exSrc = Join-Path $root 'examples\汉语库示例.cpp'
$exObj = Join-Path $root 'build\zh_example_guard.o'
$ex = 1
if (-not (Test-Path $exSrc)) {
    Write-Host "❌ 找不到真实用例：$exSrc" -ForegroundColor Red
} else {
    $exOut = & cmd /c "`"$cxx`" -std=c++20 -I `"$(Join-Path $root 'zhstdlib')`" -c `"$exSrc`" -o `"$exObj`" 2>&1"
    $ex = $LASTEXITCODE
    if ($ex -eq 0) {
        $exSize = if (Test-Path $exObj) { (Get-Item $exObj).Length } else { 0 }
        Write-Host ("真实用例：编译通过（对象 {0} 字节）；警告 {1} 条（不计入失败）" -f $exSize, (@($exOut | Where-Object { $_ -match 'warning:' }).Count)) -ForegroundColor Green
        if ($exSize -eq 0) {
            Write-Host '❌ 对象文件是 0 字节 —— 这不是"编过了"' -ForegroundColor Red
            $ex = 1
        }
    } else {
        Write-Host '❌ 真实用例编译失败（这是目标的总判据第一条）:' -ForegroundColor Red
        @($exOut | Where-Object { $_ -match 'error:' }) | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
}

Write-Host ''
# ---------------------------------------------------------------------------
#  生成器告警台账 —— 必须显式可见。
#  它按【类别】收集（凡 ⚠ / ❌ 行），不是按消息逐条补，所以**以后新加的守卫
#  不需要再改本脚本就能出现在这里**（判据就写在这）。
#
#  为什么这么在意（两次同样的错）：
#    · §16.30：「⚠ 改回英文」被吞 -> 我报告"全库 0 回退"，而 <向量> 里
#      `_Ilist.begin()`/`_Ilist.end()` 一直是英文；
#    · §16.32：「顺带引真头探针: 通过」又被吞 -> 「乙」的覆盖率成了"我记得"。
#  典型告警的成因与消除路径：
#    · 改回英文（借来的类型上的成员名）—— §15.8/§15.9，消除见 §16.23.1/§16.27.1；
#    · 拷贝缺自己的前向声明 —— §16.23.1；
#    · 步0b 的 std 模板特化警告、dropTypes 没找到类定义、没找到守卫 #endif —— 各自见 §3.26/§3.18/§3.9。
# ---------------------------------------------------------------------------
if ($warnTotal -gt 0) {
    Write-Host ("=== 生成器告警台账：{0} 条（抄来那层欠账 + 生成器警告，都不计入失败，但必须被看见）===" -f $warnTotal) -ForegroundColor Yellow
    foreach ($r in $warnRows) { Write-Host $r -ForegroundColor Yellow }
    Write-Host '  说明：这些位置编译与测试都通过，所以不计入失败。' -ForegroundColor Yellow
    Write-Host ''
}
Write-Host ("=== 顺带引真头探针（§16.29「乙」）：{0} 个头通过（只写中文头，真英文头已在）===" -f $riOk) -ForegroundColor Cyan
Write-Host '    这条是「乙」的机器保证：条目加了 realInclude 的都会进来，缺一个就说明那条挂了。' -ForegroundColor Gray
Write-Host ''

# ---------------------------------------------------------------------------
#  §17.27.61 残余边界台账：`_RANGES <英文 _ 名>(`
#
#  为什么单列一类：`_STD X` 那一路有"步 4c 去限定"兜（§17.27.52 前后），
#  但 `_RANGES X`（= `std::ranges::X`）**没有** —— 这些位置永远留在英文，
#  而且**不会报错**（限定名照样能在借来的 std::ranges 里找到）。
#  实测（§17.27.60）：给 `双端队列` 登记 `_Get_final_iterator_unwrapped` 后，
#  拷贝层 0 命中（"编译器校对"把它改回英文了），是**登记≠落地**守卫把它照出来的。
#
#  它是**边界**，不是欠账：消除路径 = 把 `_RANGES X` 也纳入改名/去限定
#  （像 `_STD X` 那样），但那是生成器的结构性改动。
#  在那之前，至少让它【看得见】—— 判据（§17.27.3）：新发现必须有机器可见的落点。
#  本台账只报告，不作门禁（口径同 `tools\check_multiowner.ps1`）。
# ---------------------------------------------------------------------------
$rngNames = @{}; $rngCount = 0
foreach ($f in (Get-ChildItem (Join-Path $root 'zhstdlib') -File)) {
    $ft = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($m in [regex]::Matches($ft, '(?m)_RANGES\s+(_[A-Za-z]\w*)\s*\(')) {
        $rngNames[$m.Groups[1].Value] = 1; $rngCount++
    }
}
Write-Host ("=== 残余边界台账（§17.27.61）：`_RANGES <英文 _ 名>(` 共 {0} 处 / {1} 个名字 ===" -f $rngCount, $rngNames.Count) -ForegroundColor Cyan
if ($rngNames.Count) {
    Write-Host ("    {0}" -f (($rngNames.Keys | Sort-Object) -join ', ')) -ForegroundColor Gray
    Write-Host '    （边界，不是欠账；消除路径 = 把 `_RANGES X` 纳入改名/去限定，见方案 §17.27.61）' -ForegroundColor Gray
}
Write-Host ''

# ---------------------------------------------------------------------------
#  §17.27.60.1 跨条目未同步译名台账（可见化 + 工作表；**暂不作门禁**）
#
#  发现（本轮机器量出来的）：译名登记是【逐条目】的 —— 同一个英文名可能
#  在 A 条目翻了、在 B 条目还是英文。实测 28 个产品 / 84 个名字
#  （例 `_Alloc` `_Allocate` `_Construct` `_Comp` `_First`）。
#  它不是"没译名"，而是"译名没跨条目同步"，所以修法很机械：
#  **按已有译名补登记**（不许另造新译名）。
#
#  ⚠ 为什么暂不作门禁：改名要求**定义方在本条目可见** —— 借来的定义方改了会编不过，
#    所以它是"按条目 + 按可见性"的批量作业（配方见方案 §17.27.60.1）。
#    判据（§17.27.3）：新发现必须有机器可见的落点 —— 这里落在
#    【每次 regen 都打印的计数】+【可 diff 的工作表】上。
# ---------------------------------------------------------------------------
$genText = [System.IO.File]::ReadAllText((Join-Path $root 'tools\make_zhstdlib2.ps1'))
$zhMap = @{}
foreach ($m in [regex]::Matches($genText, "'(?<en>[A-Za-z_][A-Za-z0-9_]*)'\s*=\s*'(?<zh>[^']+)'")) {
    $en = $m.Groups['en'].Value; $zh = $m.Groups['zh'].Value
    if (-not $zhMap.ContainsKey($en) -and $zh -ne $en) { $zhMap[$en] = $zh }
}
$crossProd = 0; $crossNames = @{}; $ws = New-Object System.Collections.ArrayList
[void]$ws.Add('# 跨条目未同步译名（§17.27.60.1）—— 判据：同一个英文名在 A 条目翻了、B 条目还是英文')
[void]$ws.Add('# 生成的：tools\regen_zhstdlib.ps1；修法：按已有译名补登记进该条目的 members 表（不另造新译名）')
foreach ($pf in (Get-ChildItem (Join-Path $root 'zhstdlib') -File)) {
    $ft = [System.IO.File]::ReadAllText($pf.FullName)
    $mi = $ft.IndexOf('// [ZH-DERIVE-LAYER]')
    $cp = if ($mi -ge 0) { $ft.Substring(0, $mi) } else { $ft }
    $seen = @{}
    foreach ($m in [regex]::Matches($cp, '\b_[A-Za-z][A-Za-z0-9_]*\b')) {
        $n = $m.Value
        if ($zhMap.ContainsKey($n)) { $seen[$n] = $true; $crossNames[$n] = $true }
    }
    if ($seen.Count) { $crossProd++; [void]$ws.Add(("  {0}: {1} 个 —— {2}" -f $pf.Name, $seen.Count, (($seen.Keys | Sort-Object) -join ' '))) }
}
$wsDir = Join-Path $root 'build'
if (-not (Test-Path $wsDir)) { New-Item -ItemType Directory -Force $wsDir | Out-Null }
[System.IO.File]::WriteAllLines((Join-Path $wsDir 'cross_entry_names.txt'), $ws, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("=== 跨条目未同步译名台账（§17.27.60.1）：{0} 个产品 / {1} 个名字（工作表 build\cross_entry_names.txt）===" -f $crossProd, $crossNames.Count) -ForegroundColor Cyan
Write-Host '    （不是"没译名"，而是"译名没跨条目同步"；修法=按已有译名补登记，配方见方案 §17.27.60.1）' -ForegroundColor Gray
Write-Host ''

# ---------------------------------------------------------------------------
#  §17.27.63 边界台账守卫（B/D 桶）—— **欠账的登记表也必须由机器核对**。
#
#  为什么加它：§17.27.42 判出四类桶之后，B/D（= 边界）一直只打在屏幕上，
#  而屏幕上的东西**滚过去就没了** —— 台账是"欠账的登记表"，它必须可 diff、
#  可核对数量、可被门禁检查，否则"记了"只是"我以为记了"。
#  判据同 §16.40（用法对照表）：手写的登记表一定会漂移，所以
#  台账由 tools\check_multiowner.ps1 **生成**，这里只核对它是否最新。
#  可见化：下面这行会打印 `边界台账：最新（B x / D y）`。
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
#  §17.27.63.2 孤儿产物守卫 —— 回退条目时必须同时删掉它的产物。
#
#  实测（第 74 轮）：<字符转换> 试做失败、生成器条目已回退，但产物文件 `zhstdlib\字符转换` 还留在盘上；
#  而「全量验证」会扫 `zhstdlib\` 下的【所有】产物 -> 那个坏产物把门禁顶红，
#  现象极像"环境残留"，害得我在三个方向上白跑了三轮门禁才找到真凶是孤儿文件。
#
#  判据（§17.27.3：新发现必须有机器落点）：**产物目录里每个文件都必须能在某个生成器里找到出处**，
#  否则直接报红并指名文件 —— 修法只有一句话：把孤儿删掉，或把条目补回来。
#  ⚠ 判据写成"文件名字面量出现在三个生成器里"，而不是"与 zh 表精确比对"：
#    make_zhc.ps1 的产品名不在 `zh = ` 字段里，精确比对会造出 26 个假孤儿。
# ---------------------------------------------------------------------------
$genText = ''
foreach ($j in $jobs) {
    $gp = Join-Path $root "tools\$($j.Script)"
    if (Test-Path $gp) { $genText += [System.IO.File]::ReadAllText($gp) }
}
$genText += [System.IO.File]::ReadAllText((Join-Path $root 'tools\make_zhc.ps1'))
$orphans = @()
foreach ($pf in (Get-ChildItem (Join-Path $root 'zhstdlib') -File)) {
    if ($genText.IndexOf("'" + $pf.Name + "'") -lt 0) { $orphans += $pf.Name }
}
Write-Host ("=== 孤儿产物守卫（§17.27.63.2）：{0} 个产物，孤儿 {1} 个 ===" -f (Get-ChildItem (Join-Path $root 'zhstdlib') -File).Count, $orphans.Count) -ForegroundColor Cyan
if ($orphans.Count) {
    Write-Host ("    ❌ 没有出处的产物：{0}" -f ($orphans -join ', ')) -ForegroundColor Red
    Write-Host '    修法：删掉孤儿（回退条目时必须同时删产物），或把条目补回来。' -ForegroundColor Yellow
}
$orph = 0; if ($orphans.Count) { $orph = 1 }
# ---------------------------------------------------------------------------
#  §17.19.16.2 公开层转发守卫 —— 让"默认不用可变参模板转发"这条配方**可见**。
#
#  为什么加它（第 82 轮）：<复数> 单头 5/5 全绿，门禁却在「全量验证」报红 ——
#  <C数学> 与 <复数> 都写了逐字相同的可变参模板（同处 `标准`），编译器判【重定义】。
#  组合探针能抓，但那是编译时的、只报第一条。本守卫是它的**静态前哨**：
#  清点命名空间作用域的转发声明与"可变参转发"风险集，并把重定义风险直接判成红。
#  可见化：下面会打印 `命名空间作用域转发 N 条 / ... / 重定义风险 0 对`。
# ---------------------------------------------------------------------------
Write-Host "=== 公开层转发守卫（§17.19.16.2）===" -ForegroundColor Cyan
& pwsh -NoProfile -File (Join-Path $root 'tools\check_zhforward.ps1')
$fw = $LASTEXITCODE

# ---------------------------------------------------------------------------
#  §17.19.17.1 中文类型名定义守卫 —— "半成品改名"的静态前哨。
#
#  为什么加它（第 83 轮的欠账）：<变体> 曾经是半成品改名 —— 活代码 `monostate`、
#  `#else` 死分支里 `单态`，而 `单态` 全库没有定义。它照样编过（死分支永不编译），
#  中文 API 却是缺的。发现它靠人肉 grep"两种写法一半一半"，本守卫把"用了但没定义"
#  变成机器判据（不需要编译器）。
#  可见化：下面会打印 `类型位置的中文限定名 N 处 / …，全部有定义`。
#  ⚠ 它的判据边界写在 §17.19.17.1：它只查【带限定】的类型位置用法；
#    修复前那一例是**不带限定**的（死分支里），所以真正的兜底是"撤回必须文件级一致"
#    （生成器里那段 §17.19.17.1 的扫尾），这条守卫是另一道（互补的）防线。
# ---------------------------------------------------------------------------
Write-Host "=== 中文类型名定义守卫（§17.19.17.1）===" -ForegroundColor Cyan
& pwsh -NoProfile -File (Join-Path $root 'tools\check_zhdef.ps1')
$zd = $LASTEXITCODE
Write-Host "=== 边界台账守卫（B/D 桶）===" -ForegroundColor Cyan
& pwsh -NoProfile -File (Join-Path $root 'tools\check_multiowner.ps1') -Quiet -Check
$bd = $LASTEXITCODE

if ($fail -eq 0 -and $v -eq 0 -and $ud -eq 0 -and $og -eq 0 -and $ex -eq 0 -and $bd -eq 0 -and $orph -eq 0 -and $fw -eq 0 -and $zd -eq 0) {
    Write-Host "重新生成 + 全量验证 + 真实用例 + 用法对照表 + 边界台账 + 孤儿产物 + 公开层转发 + 中文类型名定义 + 铁律①：全部通过" -ForegroundColor Green
    exit 0
}
Write-Host ("重新生成失败 {0} 个；全量验证退出码 {1}；真实用例退出码 {2}；用法对照表守卫退出码 {3}；边界台账守卫退出码 {5}；孤儿产物守卫退出码 {6}；铁律①守卫退出码 {4}；公开层转发守卫退出码 {7}；中文类型名定义守卫退出码 {8}" -f $fail, $v, $ex, $ud, $og, $bd, $orph, $fw, $zd) -ForegroundColor Red
exit 1
