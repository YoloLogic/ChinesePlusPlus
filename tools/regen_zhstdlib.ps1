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
        if ($line -match "^\s+'([a-z_][a-z0-9_.]*)'\s*=\s*@\{") { $out += $Matches[1] }
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
        if ($h -eq $list[0]) {
            $ck = @($o | Where-Object { $_ -match '跨头译名检查|跨头译名不一致|关键词表检查|撞上关键词' }) | Select-Object -First 2
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

if ($fail -eq 0 -and $v -eq 0 -and $ud -eq 0 -and $og -eq 0) {
    Write-Host "重新生成 + 全量验证 + 用法对照表 + 铁律①：全部通过" -ForegroundColor Green
    exit 0
}
Write-Host ("重新生成失败 {0} 个；全量验证退出码 {1}；用法对照表守卫退出码 {2}；铁律①守卫退出码 {3}" -f $fail, $v, $ud, $og) -ForegroundColor Red
exit 1
