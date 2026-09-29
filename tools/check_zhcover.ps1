# ============================================================================
#  check_zhcover.ps1 -- §17.19.21 标准头覆盖守卫
#
#  为什么必须有（第 98 轮实测）：`#包含 <迭代器>` 竟然报「找不到文件 '迭代器'」——
#  **`<iterator>` 这个核心头我们根本没有**（既没深抄、也没别名）。
#  它能一直躺着，是因为"缺哪个头"从来没有机器在问：用法对照表只列【已有什么】，
#  不列【世界应该有什么而我们还缺什么】。本守卫把这句话变成数字：
#
#      标准头覆盖：已覆盖 X / 标准头 Y（缺 Z，见台账）
#
#  判据（同 §16.40 / §17.27.63）：**"缺什么"也必须可 diff、可核对** ——
#  台账由本脚本生成，`-Check` 只核对它是否最新；补掉一个头就让台账少一行。
#  标准头清单是【标准自己的清单】（不是 MSVC include 目录），因为"该有什么"是标准说了算；
#  MSVC 的 `x*.h`/`yvals*` 之类内部头不在其中。
#
#  用法：pwsh -NoProfile -File tools\check_zhcover.ps1 [-Quiet] [-Check]
# ============================================================================
param([switch] $Quiet, [switch] $Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
#  标准 C++ 头清单（C++20/23；按字母序，便于 diff）
# ---------------------------------------------------------------------------
$stdCpp = @(
  'algorithm','any','array','atomic','barrier','bit','bitset','cassert','cctype','cerrno',
  'cfenv','cfloat','charconv','chrono','cinttypes','climits','clocale','cmath','codecvt','compare',
  'complex','concepts','condition_variable','coroutine','csetjmp','csignal','cstdarg','cstddef','cstdint','cstdio',
  'cstdlib','cstring','ctime','cuchar','cwchar','cwctype','deque','exception','execution','expected',
  'filesystem','format','forward_list','fstream','functional','future','initializer_list','iomanip','ios','iosfwd',
  'iostream','istream','iterator','latch','limits','list','locale','map','mdspan','memory',
  'memory_resource','mutex','new','numbers','numeric','optional','ostream','print','queue','random',
  'ranges','ratio','regex','scoped_allocator','semaphore','set','shared_mutex','source_location','span','spanstream',
  'sstream','stack','stacktrace','stdexcept','stop_token','streambuf','string','string_view','strstream','syncstream',
  'system_error','thread','tuple','type_traits','typeindex','typeinfo','unordered_map','unordered_set','utility','valarray',
  'variant','vector','version'
)

# ---------------------------------------------------------------------------
#  已覆盖：三个生成器表的键（英文头名）
# ---------------------------------------------------------------------------
#  ⚠ 判据要"精确"，既不能只看键、也不能"提到就算"：
#    · 只看键 -> <string>/<memory> 被误报缺（它们的键是 xstring/xmemory，真头靠 realInclude 带进来）
#    · 提到就算 -> <iterator> 被误判已覆盖（某条目的字符串里出现过 iterator 这个词），
#      而 `#包含 <迭代器>` 实测是"找不到文件"。
#    所以判据 = 【键】 或 【精确等于头名的字符串值（realInclude 等）】。
$covered = @{}
foreach ($s in @('make_zhstdlib2.ps1', 'make_zhalias.ps1', 'make_zhc.ps1')) {
  $gp = Join-Path $root "tools\$s"
  if (-not (Test-Path $gp)) { continue }
  $txt = (& pwsh -NoProfile -File $gp -ExportJson 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "$s -ExportJson 失败" }
  $obj = $txt | ConvertFrom-Json
  foreach ($pr in $obj.PSObject.Properties) {
    if ($stdCpp -contains $pr.Name) { $covered[$pr.Name] = $s }        # 条目键 = 英文头名
    $ri = $pr.Value.PSObject.Properties['realInclude']                  # realInclude = 顺带引的真头
    if ($ri) { foreach ($v in @($ri.Value)) { if ($stdCpp -contains $v) { $covered[$v] = $s } } }
  }
}
$missing = @($stdCpp | Where-Object { -not $covered.ContainsKey($_) })

# ---------------------------------------------------------------------------
#  台账（生成物）：缺的标准头一行一个，带"下一步做什么"的提示
# ---------------------------------------------------------------------------
$ledger = New-Object System.Collections.ArrayList
[void]$ledger.Add('# 标准头覆盖台账（§17.19.21）—— 判据：标准 C++ 头里有哪个我们还没有中文版')
[void]$ledger.Add('# 生成的：tools\check_zhcover.ps1；修法：照 §17.19.18/.19/.20 的配方落一个（抄+派生 或 别名）')
[void]$ledger.Add(('# 已覆盖 {0} / 标准头 {1}；缺 {2}' -f ($stdCpp.Count - $missing.Count), $stdCpp.Count, $missing.Count))
[void]$ledger.Add('')
if ($missing.Count) {
  [void]$ledger.Add('## 缺的（按字母序）')
  foreach ($m in $missing) { [void]$ledger.Add("  - <$m>") }
} else {
  [void]$ledger.Add('（无：标准头全部有中文版）')
}
$ledgerPath = Join-Path $root 'docs\标准库汉化\头文件覆盖台账.md'

if ($Check) {
  $old = if (Test-Path $ledgerPath) { [System.IO.File]::ReadAllText($ledgerPath) } else { '' }
  $new = ($ledger -join "`r`n") + "`r`n"
  if ($old -ne $new) {
    Write-Host '❌ 标准头覆盖台账【已过期】' -ForegroundColor Red
    Write-Host '   修法：pwsh -File tools\check_zhcover.ps1（不带 -Check）然后一起提交。' -ForegroundColor Yellow
    exit 1
  }
  Write-Host ('标准头覆盖台账：最新（已覆盖 {0} / {1}，缺 {2}）' -f ($stdCpp.Count - $missing.Count), $stdCpp.Count, $missing.Count) -ForegroundColor Green
  exit 0
}

[System.IO.File]::WriteAllLines($ledgerPath, $ledger, $utf8)
Write-Host ('=== 标准头覆盖守卫（§17.19.21）：已覆盖 {0} / 标准头 {1}（缺 {2}）===' -f `
    ($stdCpp.Count - $missing.Count), $stdCpp.Count, $missing.Count) -ForegroundColor Cyan
if ($missing.Count) {
  $show = @($missing | Select-Object -First 12)
  Write-Host ('    缺：{0}{1}' -f ($show -join ', '), $(if ($missing.Count -gt 12) { (' …（共 {0} 个，见台账）' -f $missing.Count) } else { '' })) -ForegroundColor Yellow
  Write-Host '    说明：这些头用户写了 `#包含 <中文名>` 会报"找不到文件"；台账 docs\标准库汉化\头文件覆盖台账.md' -ForegroundColor Gray
} else {
  Write-Host '    标准头全部有中文版' -ForegroundColor Green
}
