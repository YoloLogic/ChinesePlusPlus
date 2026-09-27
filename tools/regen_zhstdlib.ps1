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
function Get-Entries([string]$file) {
    $out = @()
    foreach ($line in [System.IO.File]::ReadAllLines($file)) {
        if ($line -match "^\s+'([a-z_][a-z0-9_]*)'\s*=\s*@\{") { $out += $Matches[1] }
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
# 「改回英文」的台账（见循环里的说明：这是本脚本原先吞掉的东西）
$revTotal = 0
$revRows = @()
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
        #  ⚠ 【守卫必须在 regen 输出里显式可见】—— 这条本脚本自己违反了。
        #
        #  原来这里只取 `Select-Object -Last 1`，于是生成器打到中间的
        #  「⚠ 改回英文: X（第 N 行）」全被吞掉。后果是实测到的：
        #    · 生成器里明明报了 12 处回退，regen 显示全绿；
        #    · 我据此说"全库 0 回退"，而实际 <向量> 里 `_Ilist.begin()` /
        #      `_Ilist.end()` 一直是英文（借来的 std::initializer_list 的成员）
        #      —— 这就是"隐形规矩等于没有规矩"。
        #  现在把每个头的回退逐条收上来，集中在末尾打一张表。
        # -------------------------------------------------------------------
        $revs = @($o | Where-Object { $_ -match '⚠ 改回英文' } | ForEach-Object { ([string]$_).Trim() })
        if ($revs.Count) {
            $script:revTotal += $revs.Count
            $script:revRows += ("  {0,-22} {1}" -f $h, (($revs | ForEach-Object { $_ -replace '^⚠ 改回英文:\s*', '' }) -join '  |  '))
        }
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

Write-Host ''
# ---------------------------------------------------------------------------
#  「改回英文」台账 —— 必须显式可见。
#  每一条都是"抄来那层里还剩一个英文标识符"，也就是【欠账】：
#  它没被算进 fail（产品本身编得过、测试也过），但**必须看得见**，
#  否则就会重演"我说全库 0 回退、实际 <向量> 里 _Ilist.begin() 一直是英文"。
#  典型成因（已查清两类）：
#    · 成员名被改到了【借来的类型】上（std::initializer_list 的 begin/end、
#      std::ranges 的 data/size）—— §15.8 / §15.9 那一类；
#    · 拷贝缺了自己的前向声明（xmemory 的 _Iterator_base12）—— §16.23.1。
#  消除路径：把提供那个名字的头也抄成汉语件（步骤 1），或从源头挡住（§16.27.1）。
# ---------------------------------------------------------------------------
if ($revTotal -gt 0) {
    Write-Host ("=== 「改回英文」台账：{0} 处（= 抄来那层还剩的英文名，属【欠账】）===" -f $revTotal) -ForegroundColor Yellow
    foreach ($r in $revRows) { Write-Host $r -ForegroundColor Yellow }
    Write-Host '  说明：这些位置编译与测试都通过，所以不计入失败；但它们必须被看见。' -ForegroundColor Yellow
    Write-Host '        消除路径见方案 §16.23.1 / §16.27.1 / §16.30。' -ForegroundColor Yellow
    Write-Host ''
}

if ($fail -eq 0 -and $v -eq 0) { Write-Host "重新生成 + 全量验证：全部通过" -ForegroundColor Green; exit 0 }
Write-Host ("重新生成失败 {0} 个；全量验证退出码 {1}" -f $fail, $v) -ForegroundColor Red
exit 1
