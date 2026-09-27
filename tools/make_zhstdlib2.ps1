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
    tparam  = @{ decl = ''; args = '' }
    tests = @(
      @('只引中文头','#包含 <类型索引>`n整数 主函数(){ 标准::类型索引 甲(类型标识(整数)); 返回 0; }'),
      @('与微软原头并存','#包含 <类型索引>`n#包含 <typeindex>`n整数 主函数(){ 标准::类型索引 甲(类型标识(整数)); std::type_index 乙(类型标识(整数)); 返回 0; }'),
      @('英文名与中文名并用','#包含 <类型索引>`n整数 主函数(){ 标准::类型索引 甲(类型标识(整数)); 返回 (整数)甲.hash_code() * 0 + (整数)甲.哈希值() * 0 + (整数)甲.name()[0] * 0; }')
    )
  }
  # ---- C++20 并发原语：与别的 std 接口没有类型交互，适合"抄一份 + 派生" ----
  'barrier' = @{
    zh      = '屏障'
    types   = [ordered]@{ 'barrier' = '屏障实现'
                          '_No_completion_function' = '_无完成函数'
                          '_Arrival_token' = '_到达令牌'
                          '_Counter_t' = '_计数器类型'
                          'arrival_token' = '到达令牌' }
    members = [ordered]@{ 'arrive' = '到达'; 'arrive_and_drop' = '到达并退出'
                          'arrive_and_wait' = '到达并等待'; 'wait' = '等待' }
    data    = [ordered]@{}
    derive  = @( @('arrive','到达'), @('arrive_and_drop','到达并退出'),
                 @('arrive_and_wait','到达并等待'), @('wait','等待') )
    deriveTypes = @( @('arrival_token','到达令牌') )
    stdHash = $false
    # barrier 是【类模板】，派生层必须重复模板形参（第一版没给 -> "需要模板实参"）
    tparam = @{ decl = '模板 <类型名 完成函数 = 细节::_无完成函数>'; args = '<完成函数>' }
    tests = @(
      @('只引中文头','#包含 <屏障>`n整数 主函数(){ 标准::屏障<> 甲(3); 甲.到达(); 返回 0; }'),
      @('与微软原头并存','#包含 <屏障>`n#包含 <barrier>`n整数 主函数(){ 标准::屏障<> 甲(3); 甲.到达(); std::barrier<> 乙(3); 乙.arrive(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <屏障>`n整数 主函数(){ 标准::屏障<> 甲(3); 甲.到达(); 甲.arrive(); 返回 0; }')
    )
  }
  'semaphore' = @{
    zh      = '信号量'
    types   = [ordered]@{ 'counting_semaphore' = '计数信号量实现'
                          '_Semaphore_max' = '_信号量最大值'
                          '_Semaphore_least_max_value' = '_信号量最小最大值' }
    members = [ordered]@{ 'acquire' = '获取'; 'try_acquire' = '尝试获取'
                          'try_acquire_for' = '尝试限时获取'
                          'try_acquire_until' = '尝试获取至时刻'
                          'release' = '释放'; 'max' = '最大' }
    data    = [ordered]@{}
    derive  = @( @('acquire','获取'), @('try_acquire','尝试获取'),
                 @('try_acquire_for','尝试限时获取'),
                 @('try_acquire_until','尝试获取至时刻'),
                 @('release','释放'), @('max','最大') )
    stdHash = $false
    # 非类型模板形参（ptrdiff_t）—— 形参名也要中文
    tparam  = @{ decl = '模板 <ptrdiff_t 最小最大值 = 细节::_信号量最大值>'; args = '<最小最大值>' }
    tests = @(
      @('只引中文头','#包含 <信号量>`n整数 主函数(){ 标准::计数信号量<2> 甲(0); 甲.释放(); 返回 0; }'),
      @('与微软原头并存','#包含 <信号量>`n#包含 <semaphore>`n整数 主函数(){ 标准::计数信号量<2> 甲(0); 甲.释放(); std::counting_semaphore<2> 乙(0); 乙.release(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <信号量>`n整数 主函数(){ 标准::计数信号量<2> 甲(0); 甲.释放(); 甲.release(); 返回 0; }')
    )
  }
  'condition_variable' = @{
    zh      = '条件变量'
    # ⚠ std::condition_variable（非 _any）其实定义在 <mutex> 里；这个头只有 _any
    pub     = '条件变量任意'
    types   = [ordered]@{ 'condition_variable_any' = '条件变量任意实现'
                          '_Unlock_guard' = '_解锁卫兵'
                          '_Cv_any_notify_all' = '_条件变量任意通知全部' }
    members = [ordered]@{ 'notify_all' = '通知全部'; 'notify_one' = '通知一个'
                          'wait' = '等待'; 'wait_for' = '限时等待'
                          'wait_until' = '等待至时刻' }
    data    = [ordered]@{}
    derive  = @( @('notify_all','通知全部'), @('notify_one','通知一个'),
                 @('wait','等待'), @('wait_for','限时等待'),
                 @('wait_until','等待至时刻') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    tests = @(
      @('只引中文头','#包含 <条件变量>`n整数 主函数(){ 标准::条件变量任意 甲; 甲.通知全部(); 返回 0; }'),
      @('与微软原头并存','#包含 <条件变量>`n#包含 <condition_variable>`n整数 主函数(){ 标准::条件变量任意 甲; 甲.通知全部(); std::condition_variable_any 乙; 乙.notify_all(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <条件变量>`n整数 主函数(){ 标准::条件变量任意 甲; 甲.通知一个(); 甲.notify_one(); 返回 0; }')
    )
  }
  'latch' = @{
    zh      = '门闩'
    types   = [ordered]@{ 'latch' = '门闩实现' }
    members = [ordered]@{ 'count_down' = '递减'; 'try_wait' = '尝试等待'
                          'wait' = '等待'; 'arrive_and_wait' = '到达并等待' }
    data    = [ordered]@{}
    derive  = @( @('count_down','递减'), @('try_wait','尝试等待'),
                 @('wait','等待'), @('arrive_and_wait','到达并等待') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    tests = @(
      @('只引中文头','#包含 <门闩>`n整数 主函数(){ 标准::门闩 甲(1); 甲.递减(); 返回 0; }'),
      @('与微软原头并存','#包含 <门闩>`n#包含 <latch>`n整数 主函数(){ 标准::门闩 甲(1); 甲.递减(); std::latch 乙(1); 乙.count_down(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <门闩>`n整数 主函数(){ 标准::门闩 甲(2); 甲.递减(); 甲.count_down(); 返回 0; }')
    )
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
# 头名与对外类名不一定相同（例：<条件变量> 里只有 condition_variable_any）
$pub = if ($spec.ContainsKey('pub')) { $spec.pub } else { $spec.zh }
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
$fwdT = @()
if ($spec.ContainsKey('deriveTypes')) {
    foreach ($p in $spec.deriveTypes) { $fwdT += ("    使用 {0} = 基类::{1};" -f $p[0], $p[1]) }
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
$($spec.tparam.decl)
类型 $pub : 公开 细节::$cls$($spec.tparam.args) {
公开:
    使用 基类 = 细节::$cls$($spec.tparam.args);
    使用 基类::基类;

    // 嵌套类型名也要补回英文（数据成员不行 —— 那会改布局）
$($fwdT -join "`n")

    // 英文原名，一模板转发回中文名（不需要写签名，重载也自动跟过去）
$($fwd -join "`n")
};
}$hashSpec
"@
#$text = $text + $layer    # ← 派生层改到"编译器校对之后"再追加，见下
New-Item -ItemType Directory -Force $out | Out-Null
$outPath = Join-Path $out $spec.zh
[System.IO.File]::WriteAllText($outPath, $text, $utf8)
Write-Host ("  输出: {0}  ({1} 行)" -f $outPath, ([System.IO.File]::ReadAllLines($outPath)).Count)

# --- 编译器当改名校对 ---
$probe = Join-Path $env:TEMP ('zh2_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.cpp')
[System.IO.File]::WriteAllText($probe, "#包含 <$($spec.zh)>`n整数 主函数(){ 返回 0; }`n", $utf8)
$rev = @{}
foreach ($k in $spec.members.Keys) { $rev[$spec.members[$k]] = $k }
foreach ($k in $spec.data.Keys)    { $rev[$spec.data[$k]] = $k }
for ($round = 1; $round -le 8; $round++) {
    $raw = & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -ferror-limit=0 -fsyntax-only `"$probe`" 2>&1"
    $hits = @()
    foreach ($l in @($raw)) {
        if ([string]$l -match "$($spec.zh)`:(\d+):(\d+): error: .*没有名为（成员名） '([^']+)' 的成员") {
            $hits += [pscustomobject]@{ Line=[int]$Matches[1]; Col=[int]$Matches[2]; Name=$Matches[3] }
        }
    }
    if ($hits.Count -eq 0) { Write-Host ("  校对第 {0} 轮: 无同名冲突" -f $round) -ForegroundColor Green; break }
    $lines = [System.IO.File]::ReadAllLines($outPath); $fixed = 0
    $doneLines = @{}
    foreach ($h in ($hits | Sort-Object Line,Col -Descending)) {
        if (-not $rev.ContainsKey($h.Name)) { continue }
        # 同一行一轮只改一处：坐标是按【改之前】那一行算的，改完长度就变了，
        # 同一行再改第二处会用错坐标（这也是坏掉派生层那个 bug 的成因之一）。
        # 剩下的下一轮再来，循环会兜住。
        if ($doneLines.ContainsKey($h.Line)) { continue }
        $idx = $h.Line - 1; $line = $lines[$idx]
        $lb = [System.Text.Encoding]::UTF8.GetBytes($line); $nb = [System.Text.Encoding]::UTF8.GetBytes($h.Name)
        $off = $h.Col - 1
        if ($off -lt 0 -or ($off + $nb.Length) -gt $lb.Length) { continue }
        $ok = $true; for ($i=0; $i -lt $nb.Length; $i++) { if ($lb[$off+$i] -ne $nb[$i]) { $ok=$false; break } }
        if (-not $ok) { continue }
        $ci = [System.Text.Encoding]::UTF8.GetString($lb,0,$off).Length
        $lines[$idx] = $line.Remove($ci,$h.Name.Length).Insert($ci,$rev[$h.Name]); $fixed++
        $doneLines[$h.Line] = $true
    }
    [System.IO.File]::WriteAllLines($outPath, $lines, $utf8)
    Write-Host ("  校对第 {0} 轮: 指出 {1} 处，改回英文 {2} 处" -f $round,$hits.Count,$fixed)
    if ($fixed -eq 0) { break }
}
Remove-Item $probe -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
#  派生层必须在【编译器校对之后】才追加。
#  为什么：校对是按编译器给的【字节坐标】直接改文件，如果派生层已经在那儿，
#  它的中文标识符会被误当冲突位置改坏 —— 实测把「到达令牌」改成了「到」「达」碎片。
# ---------------------------------------------------------------------------
[System.IO.File]::AppendAllText($outPath, $layer, $utf8)
Write-Host "  步6 派生层 + 英文转发 $($spec.derive.Count) 条$(if ($spec.deriveTypes) { " + 嵌套类型 $($spec.deriveTypes.Count) 条" })$(if ($spec.stdHash) { ' + std::hash 特化' })"

# --- 最终验证：中文名 / 英文名 / 与 std 并存 ---
Write-Host ""
Write-Host "=== 验证 ===" -ForegroundColor Cyan
$t = Join-Path $root 'build\_zh2'
if (Test-Path $t) { Remove-Item -Recurse -Force $t }
New-Item -ItemType Directory -Force $t | Out-Null
$cases = $spec.tests
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
