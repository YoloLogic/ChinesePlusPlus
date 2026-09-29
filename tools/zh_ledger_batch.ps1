# §17.27.60.1 台账批处理（第 91 轮固化，第 92 轮加 -Exclude）—— 用法：
#   pwsh -NoProfile -File tools\zh_ledger_batch.ps1 -Products 线程,栈,映射
#   pwsh -NoProfile -File tools\zh_ledger_batch.ps1 -Products 双端队列 -Exclude _Tidy,_Tidy_guard
# 判据链（§17.27.60.1.6/.7）：
#   插入全部 -> 重生 -> 从错误/守卫消息回读问题名字 -> 【删掉那一行】-> 再重生（最多 4 轮）
# 三类可回读消息：`members 表 _X`（守卫，英文名直读）、`（成员名）'_中文名'`、
#   `未声明的标识符（名字）'_中文名'`（后两类用译名->英文反查表换回）。
# -Exclude 用于"通用接口成员"这类**已知要留英文**的名字（例：`_Tidy` —— xmemory 的
#   `_Tidy_guard` 调 `_Target->_Tidy()`，改名要所有参与者一起改，属协调改名，不在这条链里）。
param([string[]] $Products, [string[]] $Exclude)
$ErrorActionPreference = 'Stop'
# ⚠ 用 pwsh -File 调用时，逗号表会被当成【一个字符串】传进来 -> 这里自己拆开。
$Products = @($Products | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Exclude  = @($Exclude  | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$gen = 'E:\Chinese++\tools\make_zhstdlib2.ps1'

function Get-ZhMap([string]$path) {
  $t = [System.IO.File]::ReadAllText($path); $m = @{}
  foreach ($x in [regex]::Matches($t, "'(?<en>[A-Za-z_][A-Za-z0-9_]*)'\s*=\s*'(?<zh>[^']+)'")) {
    $en = $x.Groups['en'].Value; $zh = $x.Groups['zh'].Value
    if (-not $m.ContainsKey($en) -and $zh -ne $en) { $m[$en] = $zh }
  }
  return $m
}
function Get-EntryRange([string]$keyZh) {
  $lines = [System.IO.File]::ReadAllLines($gen)
  $starts = @(); for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^  '[^']+'\s*=\s*@\{") { $starts += $i } }
  for ($k = 0; $k -lt $starts.Count; $k++) {
    $a = $starts[$k]; $b = if ($k + 1 -lt $starts.Count) { $starts[$k + 1] - 1 } else { $lines.Count - 1 }
    $zh = ''; for ($j = $a; $j -le [Math]::Min($b, $a + 200); $j++) { if ($lines[$j] -match "zh\s*=\s*'([^']+)'") { $zh = $Matches[1]; break } }
    if ($zh -eq $keyZh) { return [pscustomobject]@{ Key = ($lines[$a] -replace "^  '([^']+)'.*", '$1'); A = $a; B = $b; Lines = $lines } }
  }
  return $null
}
function Insert-Into([string]$prod, $pairs) {
  $r = Get-EntryRange $prod
  $mi = -1; for ($j = $r.A; $j -le $r.B; $j++) { if ($r.Lines[$j] -match "^\s*members\s*=\s*\[ordered\]@\{") { $mi = $j; break } }
  $new = @(); for ($j = 0; $j -lt $r.Lines.Count; $j++) { $new += $r.Lines[$j]; if ($j -eq $mi) { foreach ($p in $pairs) { $new += "      '$($p[0])' = '$($p[1])';" } } }
  [System.IO.File]::WriteAllLines($gen, $new, (New-Object System.Text.UTF8Encoding($false)))
}
function Remove-Line([string]$prod, [string]$en, [string]$zh) {
  $r = Get-EntryRange $prod
  $target = "      '$en' = '$zh';"; $n = 0
  for ($j = $r.A; $j -le $r.B; $j++) { if ($r.Lines[$j] -eq $target -and $n -eq 0) { $r.Lines[$j] = $null; $n++ } }
  if ($n) { [System.IO.File]::WriteAllLines($gen, @($r.Lines | Where-Object { $_ -ne $null }), (New-Object System.Text.UTF8Encoding($false))) }
  return $n
}

foreach ($prod in $Products) {
  $zhMap = Get-ZhMap $gen
  $inv = @{}; foreach ($k in $zhMap.Keys) { if (-not $inv.ContainsKey($zhMap[$k])) { $inv[$zhMap[$k]] = $k } }
  $pat = '^\s+' + [regex]::Escape($prod) + ': '
  $row = Get-Content 'E:\Chinese++\build\cross_entry_names.txt' | Where-Object { $_ -match $pat } | Select-Object -First 1
  if (-not $row) { "$prod : 不在台账里（跳过）"; continue }
  $todo = @(($row -split '——')[1].Trim() -split '\s+')
  $dropped = @($Exclude)   # 已知要留英文的名字（通用接口成员等，见文件头）
  for ($it = 1; $it -le 4; $it++) {
    $r = Get-EntryRange $prod
    if (-not $r) { "$prod : 找不到条目"; break }
    $ins = @()
    foreach ($n in $todo) {
      if ($dropped -contains $n -or -not $zhMap.ContainsKey($n)) { continue }
      $has = $false; for ($j = $r.A; $j -le $r.B; $j++) { if ($r.Lines[$j] -match ("'" + [regex]::Escape($n) + "'\s*=")) { $has = $true; break } }
      if (-not $has) { $ins += , @($n, $zhMap[$n]) }
    }
    if ($ins.Count) { Insert-Into $prod $ins }
    $o = & pwsh -NoProfile -File 'E:\Chinese++\tools\make_zhstdlib2.ps1' -Header $r.Key 2>&1
    $txt = ($o | ForEach-Object { $_.ToString() }) -join "`n"
    $fails = @($o | Select-String '\[FAIL\]').Count
    if ($LASTEXITCODE -eq 0 -and $fails -eq 0) { "$prod : 通过（ok=" + @($o | Select-String '\[ok\]').Count + " / 第 $it 轮 / 边界 $($dropped.Count)）"; break }
    $culprits = @()
    foreach ($m in [regex]::Matches($txt, "members 表\s+(_[A-Za-z0-9_]+)")) { $culprits += $m.Groups[1].Value }
    # §17.27.60.1.10：`改回英文: _X` 是第四类可回读消息 —— 它说明**这个名字在本产物里落不了地**
    #   （定义侧不可达/借用类成员），必须【删掉登记】而不是留着：留着会同时坑两件事 ——
    #   被改写的调用点和没改的定义侧对不上（编译期），以及 `登记≠落地·第三层` 把它算成失败。
    foreach ($m in [regex]::Matches($txt, "改回英文:\s*(_[A-Za-z0-9_]+)")) { $culprits += $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($txt, "（成员名）\s*'([^']+)'")) { $v = $m.Groups[1].Value; if ($todo -contains $v) { $culprits += $v } elseif ($inv.ContainsKey($v)) { $culprits += $inv[$v] } }
    foreach ($m in [regex]::Matches($txt, "未声明的标识符（名字）\s*'([^']+)'")) { $v = $m.Groups[1].Value; if ($todo -contains $v) { $culprits += $v } elseif ($inv.ContainsKey($v)) { $culprits += $inv[$v] } }
    $culprits = @($culprits | Sort-Object -Unique | Where-Object { ($todo -contains $_) -and ($dropped -notcontains $_) })
    if (-not $culprits.Count) {
      "$prod : 失败且无回读名字 -> 停"
      $o | Select-String -Pattern 'error:|登记≠落地|宏泄漏|\[FAIL\]' | Select-Object -First 3 | ForEach-Object { '    ' + $_.ToString().Trim().Substring(0, [Math]::Min(150, $_.ToString().Trim().Length)) }
      break
    }
    foreach ($c in $culprits) { $rm = Remove-Line $prod $c $zhMap[$c]; "$prod : 撤下 $c（删行 $rm）"; $dropped += $c }
  }
  if ($dropped.Count) { "$prod 边界: " + ($dropped -join ' ') }
}
$e1 = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($gen, [ref]$null, [ref]$e1)
"语法错误数: " + @($e1).Count
