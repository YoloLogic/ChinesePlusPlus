# ============================================================================
#  make_zhalias.ps1 -- 「只能别名」的 C++ 头 -> 中文别名层
#
#  为什么这些头不能抄（方案铁律 4：类型身份参与语义的只能用别名）：
#    numbers          全是变量模板（常量），不是类
#    typeinfo         RTTI —— typeid() 返回 std::type_info 的引用
#    initializer_list 花括号初始化由编译器生成 std::initializer_list
#    ratio            std::chrono 的算术依赖它的类型身份
#    tuple            结构化绑定走 std::tuple_size / std::get 的特化
#    type_traits      全是 traits 检测
#    pair             有【公开数据成员】first/second（派生补不回英文名，会改布局）
#
#  机制（同 make_zhc.ps1 的三种，再加"常量"）：
#    常量  -> 内联 常量 类型 中文名 = std::原名;
#    类型  -> 使用 中文名 = std::原名;
#    函数  -> 模板 <类型名... 参数> 自动 中文名(参数&&... 值) { 返回 std::原名(...); }
#
#  用法：powershell -File tools\make_zhalias.ps1 -Header numbers
# ============================================================================
param([string] $Header = 'numbers')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $root 'zhstdlib'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 表：条目 = @('常量','中文名','std::原名','类型')
#            @('类型','中文名','std::原名')
#            @('函数','中文名','std::原名')      —— 通用一模板转发
#            @('原样','<整行代码>')              —— 原样发出（成员要转发成自由函数时用）
$H = [ordered]@{
  'ratio' = @{ zh = '比'; src = 'ratio'; a = @(
      # 必须同一类型：std::chrono 的算术依赖 ratio 的类型身份（铁律 4）
      @('原样','模板 <整数 分子, 整数 分母 = 1>
    使用 比 = std::ratio<分子, 分母>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相加 = std::ratio_add<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相减 = std::ratio_subtract<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相乘 = std::ratio_multiply<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相除 = std::ratio_divide<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相等 = std::ratio_equal<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比不等 = std::ratio_not_equal<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比小于 = std::ratio_less<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比小于等于 = std::ratio_less_equal<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比大于 = std::ratio_greater<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比大于等于 = std::ratio_greater_equal<比甲, 比乙>;'),
      # SI 词头（中文标准词头）
      @('原样','使用 阿托 = std::atto;   使用 飞托 = std::femto;  使用 皮可 = std::pico;'),
      @('原样','使用 纳诺 = std::nano;   使用 微   = std::micro;  使用 毫   = std::milli;'),
      @('原样','使用 厘   = std::centi;  使用 分   = std::deci;   使用 十   = std::deca;'),
      @('原样','使用 百   = std::hecto;  使用 千   = std::kilo;   使用 兆   = std::mega;'),
      @('原样','使用 吉   = std::giga;   使用 太   = std::tera;   使用 拍   = std::peta;'),
      @('原样','使用 艾   = std::exa;')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <比>`n静态断言(std::is_same<标准::比<1, 2>, std::ratio<1, 2>>::value, "");`n整数 主函数(){ 返回 (整数)标准::比<1, 2>::num - 1; }'),
      @('与 <ratio> 并存 + SI 词头同类型','#包含 <比>`n#包含 <ratio>`n静态断言(std::is_same<标准::千, std::kilo>::value, "");`n静态断言(std::is_same<标准::毫, std::milli>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('比相加 与 std::ratio_add 同类型','#包含 <比>`n静态断言(std::is_same<标准::比相加<标准::比<1, 2>, 标准::比<1, 3>>, std::ratio_add<std::ratio<1, 2>, std::ratio<1, 3>>>::value, "");`n整数 主函数(){ 返回 0; }')
    )
  }
  'typeinfo' = @{ zh = '类型信息'; src = 'typeinfo'; a = @(
      # 类型：必须同一类型 —— typeid() 返回的就是 std::type_info 的引用（铁律 4）
      @('类型','类型信息','std::type_info'),
      # 异常类型也只能别名：捕获按类型匹配，抄一份/派生就抓不到别人抛的（铁律 4）
      @('类型','类型转换失败','std::bad_cast'),
      @('类型','类型标识失败','std::bad_typeid'),
      # 成员改不了名（类型是 std 的），只能做成中文自由函数
      @('原样','内联 常量 字符* 名称(常量 类型信息& 信息) noexcept { 返回 信息.name(); }'),
      @('原样','内联 size_t 哈希值(常量 类型信息& 信息) noexcept { 返回 信息.hash_code(); }'),
      @('原样','内联 布尔 先于(常量 类型信息& 甲, 常量 类型信息& 乙) noexcept { 返回 甲.before(乙); }'),
      @('原样','内联 布尔 相等(常量 类型信息& 甲, 常量 类型信息& 乙) noexcept { 返回 甲 == 乙; }'),
      @('原样','内联 布尔 不等(常量 类型信息& 甲, 常量 类型信息& 乙) noexcept { 返回 甲 != 乙; }')
  )
    tests = @(
      @('只引中文头（类型别名 + 中文自由函数）','#包含 <类型信息>`n整数 主函数(){ 返回 (整数)标准::哈希值(类型标识(整数)) * 0; }'),
      @('与 <typeinfo> 并存','#包含 <类型信息>`n#包含 <typeinfo>`n整数 主函数(){ 常量 std::type_info& 乙 = 类型标识(整数); 返回 (整数)标准::哈希值(类型标识(整数)) * 0 + (整数)乙.hash_code() * 0; }'),
      @('类型身份必须相同（铁律 4）','#包含 <类型信息>`n静态断言(std::is_same<标准::类型转换失败, std::bad_cast>::value, "");`n静态断言(std::is_same<标准::类型信息, std::type_info>::value, "");`n整数 主函数(){ 返回 0; }')
    )
  }
  'numbers' = @{ zh = '数字'; src = 'numbers'; a = @(
      @('常量','圆周率','std::numbers::pi','双精度'),
      @('常量','自然常数','std::numbers::e','双精度'),
      @('常量','欧拉常数','std::numbers::egamma','双精度'),
      @('常量','黄金比例','std::numbers::phi','双精度'),
      @('常量','二的自然对数','std::numbers::ln2','双精度'),
      @('常量','十的自然对数','std::numbers::ln10','双精度'),
      @('常量','以二为底自然常数的对数','std::numbers::log2e','双精度'),
      @('常量','以十为底自然常数的对数','std::numbers::log10e','双精度'),
      @('常量','二的平方根','std::numbers::sqrt2','双精度'),
      @('常量','三的平方根','std::numbers::sqrt3','双精度'),
      @('常量','圆周率的倒数','std::numbers::inv_pi','双精度'),
      @('常量','圆周率平方根的倒数','std::numbers::inv_sqrtpi','双精度'),
      @('常量','三的平方根的倒数','std::numbers::inv_sqrt3','双精度')
  ) }
}

$spec = $H[$Header]
if (-not $spec) { throw "表里没有 $Header" }

$body = @(); $n = @{ '常量'=0; '类型'=0; '函数'=0; '原样'=0 }
foreach ($e in $spec.a) {
    switch ($e[0]) {
        '常量' { $body += ("    内联 常量 {0} {1} = {2};" -f $e[3], $e[1], $e[2]); $n['常量']++ }
        '类型' { $body += ("    使用 {0} = {1};" -f $e[1], $e[2]); $n['类型']++ }
        '函数' { $body += ("    模板 <类型名... 参数> 自动 {0}(参数&&... 值) {{ 返回 {1}(static_cast<参数&&>(值)...); }}" -f $e[1], $e[2]); $n['函数']++ }
        '原样' { $body += ("    " + $e[1]); $n['原样']++ }
    }
}

$text = @"
// <$($spec.zh)> —— $($spec.src) 的中文别名层
//
// 为什么是别名而不是抄一份（方案铁律 4）：
//   本头里是【常量】而不是类 —— 常量换不了类型，只能承载它的值。
//   这类头一旦抄一份，就会和 std 里那份成为两套互不相认的东西。
//
// 英文原名照旧可用：这里只是【多一个名字】，原头一个字节没动。
// 变体（英文里带 _v 的变量模板形式）暂未提供中文名，属"必须的妥协"，见方案 §六。
#pragma once
#include <$($spec.src)>

名域 标准 {
$($body -join "`n")
}
"@
New-Item -ItemType Directory -Force $out | Out-Null
$outPath = Join-Path $out $spec.zh
[System.IO.File]::WriteAllText($outPath, $text, $utf8)
Write-Host "=== <$($spec.zh)> ===" -ForegroundColor Cyan
Write-Host ("  生成 常量 {0} / 类型 {1} / 函数 {2} / 原样 {3}" -f $n['常量'], $n['类型'], $n['函数'], $n['原样'])

# 验证：能引、能用、与原名并存
$t = Join-Path $root 'build\_zha'
if (Test-Path $t) { Remove-Item -Recurse -Force $t }
New-Item -ItemType Directory -Force $t | Out-Null
$cases = if ($spec.ContainsKey('tests')) { $spec.tests } else {
    $first = $spec.a | Where-Object { $_[0] -eq '常量' } | Select-Object -First 1
    @(
      @('只引中文头', "#包含 <$($spec.zh)>`n整数 主函数(){ 返回 (整数)标准::$($first[1]); }"),
      @('与微软原头并存', "#包含 <$($spec.zh)>`n#包含 <$($spec.src)>`n整数 主函数(){ 返回 (整数)标准::$($first[1]) + (整数)$($first[2]); }")
    )
}
$pass = 0
foreach ($c in $cases) {
    $src = Join-Path $t 't.cpp'
    [System.IO.File]::WriteAllText($src, $c[1] + "`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -fsyntax-only `"$src`" > `"$t\o.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { Write-Host ("  [ok]   {0}" -f $c[0]); $pass++ }
    else {
        Write-Host ("  [FAIL] {0}" -f $c[0]) -ForegroundColor Yellow
        Get-Content "$t\o.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' } |
            Select-Object -First 2 | ForEach-Object { Write-Host ("         " + ([string]$_).Trim()) }
    }
}
Write-Host ("  {0} / {1}" -f $pass, $cases.Count)
Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
