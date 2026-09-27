# ============================================================================
#  make_zhstdlib2.ps1 -- 步骤 2：乙类（自含实现）头 -> 中文版
#
#  每个头两层（方案 §〇）：
#    第一层  标准::细节::<中文名>实现   —— 抄自微软，成员名全中文
#    第二层  标准::<中文名>             —— 在中文的基础上派生，补回英文原名
#
#  六步配方（方案 §3.1）+ 编译器当改名校对（§3.2 坑②）：
#    1 换守卫  2 搬名域 标准::细节 + 使用 名域 std;   3 类型名   4 成员名
#    5 手工理嵌套名域   6 追加派生层
#
#  ⚠ 三条已经踩过的坑（都写进方案）：
#    · 不能整文件全局字符串替换（会把 #include <xpolymorphic_allocator.h> 改坏）
#    · 成员名会撞借用类型的同名成员 -> 让编译器报行列号，按【字节】偏移改回
#    · 中文标识符不能以数字开头（后置构词：字符16位）
#
#  用法：powershell -File tools\make_zhstdlib2.ps1 -Header typeindex
# ============================================================================
param([string] $Header = 'typeindex')

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx   = Join-Path $root 'build\Release\bin\chinese++.exe'
$vsInc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$out   = Join-Path $root 'zhstdlib'
$utf8  = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
#  表：每个头一条。加新头 = 加一条。
# ---------------------------------------------------------------------------
$H = @{
  'typeindex' = @{
    zh      = '类型索引'
    types   = [ordered]@{ 'type_index' = '类型索引实现' }
    members = [ordered]@{ 'hash_code' = '哈希值'; 'name' = '名称' }
    data    = [ordered]@{ '_Tptr' = '_类型指针' }
    # 派生层要补回的英文名（英文 = 中文），用一模板转发，不需要签名
    derive  = @( @('hash_code','哈希值'), @('name','名称') )
    # 额外要在 std 里补的特化（派生类型也需要 std::hash）
    stdHash = $true
  }
}

$spec = $H[$Header]
if (-not $spec) { throw "表里没有 $Header —— 先在 make_zhstdlib2.ps1 的表里加一条" }

$srcPath = Join-Path $vsInc $Header
$text = [System.IO.File]::ReadAllText($srcPath)
$origLines = ([System.IO.File]::ReadAllLines($srcPath)).Count
Write-Host "=== 步骤 2：<$($spec.zh)>（源 <$Header>, $origLines 行）===" -ForegroundColor Cyan

# 步 1：换守卫
$gm = [regex]::Match($text, '(?m)^#ifndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\r?\n#define\s+\1\b')
if ($gm.Success) {
    $g = $gm.Groups[1].Value
    $ng = '_ZH_' + ($spec.zh)
    $ng = '_ZH_' + ($Header.ToUpper() -replace '[^A-Z0-9]', '_') + '_'
    $text = $text.Replace("#ifndef $g", "#ifndef $ng").Replace("#define $g", "#define $ng")
    Write-Host "  步1 守卫 $g -> $ng"
}

# 步 2：搬名域
$text = $text.Replace('_STD_BEGIN', "名域 标准 { 名域 细节 {`n使用 名域 std;")
$text = $text.Replace('_STD_END', '} }')
Write-Host "  步2 名域 -> 标准::细节 + 使用 名域 std;"

# 步 3/4：类型名、成员名、数据成员名（按 \b 边界，逐条替换）
$nT = 0; $nM = 0; $nD = 0
foreach ($k in $spec.types.Keys)   { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.types[$k]); $nT += $c } }
foreach ($k in $spec.members.Keys) { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.members[$k]); $nM += $c } }
foreach ($k in $spec.data.Keys)    { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.data[$k]); $nD += $c } }
Write-Host "  步3/4 类型 $nT 处 / 成员 $nM 处 / 数据 $nD 处"

# 步 6：派生层（在中文的基础上派生，补回英文原名）
$cls = ($spec.types.Values | Select-Object -First 1)   # 实现类名
$origType = ($spec.types.Keys | Select-Object -First 1) # 原本的类型名（供测试用）
$pub = $spec.zh
$fwd = @()
foreach ($p in $spec.derive) {
    # 发两个转发：非 const 一个、const 一个。
    # 为什么两个都要：只发非 const 的话，const 对象上调用不到（实测
    # std::hash 特化里 _键.hash_code() 就是 const 引用，直接报"没有匹配的成员函数"）。
    # 两个并存不会歧义：非 const 对象上非 const 版更匹配；const 对象上只有 const 版可用。
    # 转发是模板，惰性实例化 —— 所以给非 const 成员也发一个 const 版是安全的。
    $fwd += ("    模板 <类型名... 参数> 自动 {0}(参数&&... 值) {{ 返回 基类::{1}(static_cast<参数&&>(值)...); }}" -f $p[0], $p[1])
    $fwd += ("    模板 <类型名... 参数> 自动 {0}(参数&&... 值) 常量 {{ 返回 基类::{1}(static_cast<参数&&>(值)...); }}" -f $p[0], $p[1])
}
$hashSpec = if ($spec.stdHash) { @"

// std::hash 的特化必须挂在【对外那个类型】上（派生层之后），所以放在这里
名域 std {
    模板 <>
    结构 hash<标准::$pub> {
        _NODISCARD size_t operator()(常量 标准::$pub& _键) 常量 noexcept {
            返回 _键.hash_code();
        }
    };
}
"@ } else { '' }

$layer = @"


// ============================================================================
//  第二层：在【中文的基础上】派生，把英文原名补回来
//  · 第一层 标准::细节::$cls 是抄自微软的中文实现，成员名全中文
//  · 本层加回英文原名，所以两种名字在【同一个对象】上都能用
//  · 与微软的原类型并存：它是【另一个类型】，不碰 std 里的定义
// ============================================================================
名域 标准 {
类型 $pub : 公开 细节::$cls {
公开:
    使用 基类 = 细节::$cls;
    使用 基类::基类;

    // 英文原名，一模板转发回中文名（不需要写签名，重载也自动跟过去）
$($fwd -join "`n")
};
}$hashSpec
"@
$text = $text + $layer
Write-Host "  步6 派生层 + 英文转发 $($spec.derive.Count) 条$(if ($spec.stdHash) { ' + std::hash 特化' })"

New-Item -ItemType Directory -Force $out | Out-Null
$outPath = Join-Path $out $pub
[System.IO.File]::WriteAllText($outPath, $text, $utf8)
Write-Host ("  输出: {0}  ({1} 行)" -f $outPath, ([System.IO.File]::ReadAllLines($outPath)).Count)

# --- 编译器当改名校对 ---
$probe = Join-Path $env:TEMP ('zh2_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.cpp')
[System.IO.File]::WriteAllText($probe, "#包含 <$pub>`n整数 主函数(){ 返回 0; }`n", $utf8)
$rev = @{}
foreach ($k in $spec.members.Keys) { $rev[$spec.members[$k]] = $k }
foreach ($k in $spec.data.Keys)    { $rev[$spec.data[$k]] = $k }
for ($round = 1; $round -le 8; $round++) {
    $raw = & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -ferror-limit=0 -fsyntax-only `"$probe`" 2>&1"
    $hits = @()
    foreach ($l in @($raw)) {
        if ([string]$l -match "$pub`:(\d+):(\d+): error: .*没有名为（成员名） '([^']+)' 的成员") {
            $hits += [pscustomobject]@{ Line=[int]$Matches[1]; Col=[int]$Matches[2]; Name=$Matches[3] }
        }
    }
    if ($hits.Count -eq 0) { Write-Host ("  校对第 {0} 轮: 无同名冲突" -f $round) -ForegroundColor Green; break }
    $lines = [System.IO.File]::ReadAllLines($outPath); $fixed = 0
    foreach ($h in ($hits | Sort-Object Line,Col -Descending)) {
        if (-not $rev.ContainsKey($h.Name)) { continue }
        $idx = $h.Line - 1; $line = $lines[$idx]
        $lb = [System.Text.Encoding]::UTF8.GetBytes($line); $nb = [System.Text.Encoding]::UTF8.GetBytes($h.Name)
        $off = $h.Col - 1
        if ($off -lt 0 -or ($off + $nb.Length) -gt $lb.Length) { continue }
        $ok = $true; for ($i=0; $i -lt $nb.Length; $i++) { if ($lb[$off+$i] -ne $nb[$i]) { $ok=$false; break } }
        if (-not $ok) { continue }
        $ci = [System.Text.Encoding]::UTF8.GetString($lb,0,$off).Length
        $lines[$idx] = $line.Remove($ci,$h.Name.Length).Insert($ci,$rev[$h.Name]); $fixed++
    }
    [System.IO.File]::WriteAllLines($outPath, $lines, $utf8)
    Write-Host ("  校对第 {0} 轮: 指出 {1} 处，改回英文 {2} 处" -f $round,$hits.Count,$fixed)
    if ($fixed -eq 0) { break }
}
Remove-Item $probe -Force -ErrorAction SilentlyContinue

# --- 最终验证：中文名 / 英文名 / 与 std 并存 ---
Write-Host ""
Write-Host "=== 验证 ===" -ForegroundColor Cyan
$t = Join-Path $root 'build\_zh2'
if (Test-Path $t) { Remove-Item -Recurse -Force $t }
New-Item -ItemType Directory -Force $t | Out-Null
$cases = @(
  @('只引中文头',        "#包含 <$pub>`n整数 主函数(){ 标准::$pub 甲(类型标识(整数)); 返回 0; }"),
  @('与微软原头并存',    "#包含 <$pub>`n`n#包含 <$Header>`n整数 主函数(){ 标准::$pub 甲(类型标识(整数)); std::$origType 乙(类型标识(整数)); 返回 0; }"),
  @('英文名与中文名并用',"#包含 <$pub>`n整数 主函数(){ 标准::$pub 甲(类型标识(整数)); 返回 (整数)甲.hash_code() - (整数)甲.哈希值() + (整数)甲.name()[0] * 0; }")
)
$pass = 0
foreach ($c in $cases) {
    $src = Join-Path $t 't.cpp'
    [System.IO.File]::WriteAllText($src, $c[1] + "`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -fsyntax-only `"$src`" > `"$t\o.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { Write-Host ("  [ok]   {0}" -f $c[0]); $pass++ }
    else {
        Write-Host ("  [FAIL] {0}" -f $c[0]) -ForegroundColor Yellow
        Get-Content "$t\o.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' } |
            Select-Object -First 3 | ForEach-Object { Write-Host ("         " + ([string]$_).Trim()) }
    }
}
Write-Host ("  {0} / {1}" -f $pass, $cases.Count)
Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
