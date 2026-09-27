# ============================================================================
#  make_zhc.ps1 -- 步骤 3：把 26 个 C 包装头做成【中文别名层】
#
#  为什么是别名、不是抄一份（方案铁律 4）：
#    C 包装头自己没有实现，只是把 C 库名字搬进 std。而 size_t / max_align_t /
#    FILE 这类类型**必须与全局那个是同一个类型**（对齐 / ABI），
#    抄一份就变成"另一种类型"。实测抄 cstddef 会直接炸：
#      using _STD max_align_t;  // 把全局的引进 std，再引回全局 —— 搬名域后断链
#
#  产物：zhstdlib\<中文头名>，内容是 #include <原头> + 名域 标准 { 使用 中文名 = 原名; }
#
#  用法：powershell -File tools\make_zhc.ps1
# ============================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $root 'zhstdlib'
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force $out | Out-Null

# 表：英文头 -> 中文头 -> @(中文名 = 英文名, ...)   只列【非宏】实体（宏不能用 使用 别名）
$T = [ordered]@{
  'cstddef' = @{ zh='C标准定义'; a=@(
      @('大小类型','std::size_t'), @('指针差类型','std::ptrdiff_t'),
      @('空指针类型','std::nullptr_t'), @('最大对齐类型','std::max_align_t'),
      @('字节','std::byte')) }
  'cstdint' = @{ zh='C标准整数'; a=@(
      @('整数8位','std::int8_t'), @('整数16位','std::int16_t'),
      @('整数32位','std::int32_t'), @('整数64位','std::int64_t'),
      @('无符号整数8位','std::uint8_t'), @('无符号整数16位','std::uint16_t'),
      @('无符号整数32位','std::uint32_t'), @('无符号整数64位','std::uint64_t'),
      @('指针整数','std::intptr_t'), @('无符号指针整数','std::uintptr_t'),
      @('最大整数','std::intmax_t'), @('最大无符号整数','std::uintmax_t')) }
  'cstdio' = @{ zh='C标准输入输出'; a=@(
      @('文件','std::FILE'), @('打开文件','std::fopen'), @('关闭文件','std::fclose'),
      @('打印','std::printf'), @('格式化打印','std::fprintf'), @('扫描','std::scanf'),
      @('读文件','std::fread'), @('写文件','std::fwrite'), @('取字符','std::fgetc'),
      @('放字符','std::fputc'), @('取字符串','std::fgets'), @('放字符串','std::fputs'),
      @('标准输入','std::stdin'), @('标准输出','std::stdout'), @('标准错误','std::stderr'),
      @('定位文件','std::fseek'), @('冲刷文件','std::fflush')) }
  'cstdlib' = @{ zh='C标准库'; a=@(
      @('分配内存','std::malloc'), @('释放内存','std::free'), @('退出','std::exit'),
      @('取环境变量','std::getenv'), @('转整数','std::atoi'), @('转长整数','std::atol'),
      @('转双精度','std::atof'), @('随机数','std::rand'), @('设随机种子','std::srand'),
      @('绝对值','std::abs'), @('快速排序','std::qsort'), @('二分查找','std::bsearch'),
      @('执行命令','std::system'), @('转整数串','std::itoa')) }
  'cstring' = @{ zh='C字符串'; a=@(
      @('字符串长度','std::strlen'), @('复制字符串','std::strcpy'), @('连接字符串','std::strcat'),
      @('比较字符串','std::strcmp'), @('复制内存','std::memcpy'), @('移动内存','std::memmove'),
      @('填充内存','std::memset'), @('比较内存','std::memcmp'), @('查找字符','std::strchr'),
      @('查找子串','std::strstr'), @('反转字符串','std::strrev')) }
  'cmath' = @{ zh='C数学'; a=@(
      @('平方根','std::sqrt'), @('幂','std::pow'), @('绝对值','std::fabs'),
      @('向下取整','std::floor'), @('向上取整','std::ceil'), @('四舍五入','std::round'),
      @('自然指数','std::exp'), @('自然对数','std::log'), @('常用对数','std::log10'),
      @('正弦','std::sin'), @('余弦','std::cos'), @('正切','std::tan'),
      @('反正弦','std::asin'), @('反余弦','std::acos'), @('反正切','std::atan'),
      @('双参反正切','std::atan2'), @('余数','std::fmod'), @('双曲正弦','std::sinh')) }
  'ctime' = @{ zh='C时间'; a=@(
      @('时间类型','std::time_t'), @('时钟类型','std::clock_t'),
      @('时间结构','std::tm'), @('取时间','std::time'), @('取时钟','std::clock'),
      @('本地时间','std::localtime'), @('世界时','std::gmtime'),
      @('格式化时间','std::strftime'), @('时间差','std::difftime')) }
  'cctype' = @{ zh='C字符类别'; a=@(
      @('是字母','std::isalpha'), @('是数字','std::isdigit'), @('是空白','std::isspace'),
      @('是标点','std::ispunct'), @('是字母数字','std::isalnum'), @('是小写','std::islower'),
      @('是大写','std::isupper'), @('转大写','std::toupper'), @('转小写','std::tolower')) }
  'cwchar' = @{ zh='C宽字符'; a=@(
      @('宽字符长度','std::wcslen'), @('宽字符复制','std::wcscpy'),
      @('宽字符比较','std::wcscmp'), @('宽字符连接','std::wcscat')) }
  'cwctype' = @{ zh='C宽字符类别'; a=@(
      @('是宽字母','std::iswalpha'), @('是宽数字','std::iswdigit'),
      @('是宽空白','std::iswspace'), @('转宽大写','std::towupper'), @('转宽小写','std::towlower')) }
  'csetjmp' = @{ zh='C跳转'; a=@(
      @('跳转缓冲','std::jmp_buf'), @('设置跳转','std::setjmp'), @('长跳转','std::longjmp')) }
  'csignal' = @{ zh='C信号'; a=@(
      @('信号处理','std::signal'), @('引发信号','std::raise'),
      @('信号类型','std::sig_atomic_t')) }
  'clocale' = @{ zh='C本地化'; a=@(
      @('本地化结构','std::lconv'), @('设置本地化','std::setlocale'),
      @('本地化数值','std::localeconv')) }
  'cfenv' = @{ zh='C浮点环境'; a=@(
      @('浮点环境类型','std::fenv_t'), @('浮点异常类型','std::fexcept_t'),
      @('清除浮点异常','std::feclearexcept'), @('测试浮点异常','std::fetestexcept')) }
  'cinttypes' = @{ zh='C整数格式'; a=@(
      @('整数除法结构','std::imaxdiv_t'), @('整数除法','std::imaxdiv'),
      @('最大整数绝对值','std::imaxabs')) }
  'cuchar' = @{ zh='C字符转换'; a=@(
      @('16位字符','char16_t'), @('32位字符','char32_t')) }
  'cstdarg' = @{ zh='C变参'; a=@( @('变参列表','std::va_list') ) }
  'cassert'    = @{ zh='C断言';     a=@() }
  'ccomplex'   = @{ zh='C复数';     a=@() }
  'cfloat'     = @{ zh='C浮点极值'; a=@() }
  'climits'    = @{ zh='C整数极值'; a=@() }
  'ciso646'    = @{ zh='C替代拼写'; a=@() }
  'cstdalign'  = @{ zh='C对齐';     a=@() }
  'cstdbool'   = @{ zh='C布尔';     a=@() }
  'ctgmath'    = @{ zh='C泛型数学'; a=@() }
}

$n = 0; $totalAlias = 0; $made = @()
foreach ($h in $T.Keys) {
    $zh = $T[$h].zh
    $body = @()
    foreach ($pair in $T[$h].a) {
        $body += ("    使用 {0,-18} = {1};" -f $pair[0], $pair[1])
        $totalAlias++
    }
    $note = if ($T[$h].a.Count -eq 0) {
        "    // 本头只提供【宏】（如 EOF / INT_MAX / assert / va_start），宏不能用「使用」别名；"
        "    // 要中文名得用 `#定义` 或 `内联 常量`，留给命名表定稿后再补。"
    } else { '' }

    $sample = if ($T[$h].a.Count -gt 0) { $T[$h].a[0][1] } else { 'C 库的名字' }
    $text = @"
// <$zh> —— $h 的中文别名层
//
// 为什么是别名而不是抄一份（方案铁律 4）：
//   C 包装头自己没有实现，只是把 C 库名字搬进 std；而 $sample 这类
//   **必须与全局那个是同一个类型**（对齐 / ABI）。抄一份就变成"另一种类型"。
//   实测抄 cstddef 直接炸：「using _STD max_align_t;」那条"桥"搬名域后断链。
//
// 英文原名照旧可用：这里只是【多一个名字】，原头一个字节没动。
#pragma once
#include <$h>

名域 标准 {
$($body -join "`n")
$note
}
"@
    [System.IO.File]::WriteAllText((Join-Path $out $zh), $text, $utf8)
    $made += $zh; $n++
}

Write-Host "=== 步骤 3：C 包装头别名层 ===" -ForegroundColor Cyan
Write-Host ("  生成 {0} 个中文头，共 {1} 条 `使用` 别名" -f $n, $totalAlias)
Write-Host ("  " + ($made -join ' '))

# ---- 删掉抄坏的 26 个副本（它们在 shadow 真正的 <cstddef> 等）----
$victims = @()
foreach ($h in $T.Keys) {
    $p = Join-Path $out $h
    if (Test-Path $p) { Remove-Item $p -Force; $victims += $h }
}
Write-Host ("  已删除抄坏的副本 {0} 个（原先 shadow 着真头）" -f $victims.Count) -ForegroundColor Yellow

# ---- 验证：26 个中文头逐个能编 ----
Write-Host ""
Write-Host "=== 验证 ===" -ForegroundColor Cyan
$tmp = Join-Path $root 'build\_zhc'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force $tmp | Out-Null
$ok = 0; $bad = @()
foreach ($h in $T.Keys) {
    $zh = $T[$h].zh
    $src = Join-Path $tmp 't.cpp'
    [System.IO.File]::WriteAllText($src, "#包含 <$zh>`n整数 主函数(){ 返回 0; }`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -fsyntax-only `"$src`" > `"$tmp\o.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { $ok++ }
    else {
        $first = Get-Content "$tmp\o.txt" -ErrorAction SilentlyContinue |
                 Where-Object { $_ -match 'error:' } | Select-Object -First 1
        $bad += [pscustomobject]@{ Zh = $zh; Err = ([string]$first).Trim() }
    }
}
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host ("  通过 {0} / {1}" -f $ok, $n) -ForegroundColor Green
$bad | ForEach-Object { Write-Host ("    {0,-16} {1}" -f $_.Zh, $_.Err) -ForegroundColor Yellow }
