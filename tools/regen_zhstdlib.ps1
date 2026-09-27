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
    @{ Script = 'make_zhalias.ps1';    Entries = (Get-Entries (Join-Path $root 'tools\make_zhalias.ps1'))    },
    @{ Script = 'make_zhstdlib2.ps1';  Entries = (Get-Entries (Join-Path $root 'tools\make_zhstdlib2.ps1'))  }
)

$fail = 0
foreach ($j in $jobs) {
    $list = @($j.Entries | Where-Object { $Exclude -notcontains $_ } | Sort-Object)
    Write-Host ("=== {0}  ({1} 个表项) ===" -f $j.Script, $list.Count) -ForegroundColor Cyan
    foreach ($h in $list) {
        $o = & pwsh -NoProfile -File (Join-Path $root "tools\$($j.Script)") -Header $h 2>&1
        $last = ([string]($o | Select-Object -Last 1)).Trim()
        # 生成器里的"跨头译名一致性检查"（方案 §3.11）输出会被这里捕获而看不见，
        # 隐形规矩等于没有规矩 —— 所以对每个脚本的第一个头把它显式打出来一行。
        if ($h -eq $list[0]) {
            $ck = @($o | Where-Object { $_ -match '跨头译名检查|跨头译名不一致' }) | Select-Object -First 1
            if ($ck) { Write-Host ("  {0}" -f ([string]$ck).Trim()) }
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
if ($fail -eq 0 -and $v -eq 0) { Write-Host "重新生成 + 全量验证：全部通过" -ForegroundColor Green; exit 0 }
Write-Host ("重新生成失败 {0} 个；全量验证退出码 {1}" -f $fail, $v) -ForegroundColor Red
exit 1
