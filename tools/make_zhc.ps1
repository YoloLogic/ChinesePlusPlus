# ============================================================================
#  make_zhc.ps1 -- 步骤 3：26 个 C 包装头 -> 中文别名层
#
#  为什么是别名不是抄一份（方案铁律 4）：
#    C 包装头自己没有实现，只是把 C 库名字搬进 std。size_t / max_align_t / FILE
#    这类**必须与全局那个同一类型**（对齐 / ABI）。抄一份就变成"另一种类型"。
#
#  ⚠ 三种机制，不是一种（第一轮 8/25 就是只用了"类型别名"一种）：
#    类型   使用 中文名 = std::原名;
#    函数   模板 <类型名... 参数> 声明类型(自动) 中文名(参数&&... 值) { 返回 std::原名(...); }
#           ⚠ 返回类型用 声明类型(自动)（见 §16.52）：有些 C 函数返回引用/指针语义，
#             `自动` 会把它们按值推导掉。
#           —— 函数没有"别名"机制：使用 std::fopen; 引入的是【原名 fopen】
#    值宏   内联 常量 类型 中文名 = 原名;
#    变参 C 函数（printf/scanf/setlocale）无法转发 —— 只记原名，见 $variadicNote
#
#  用法：powershell -File tools\make_zhc.ps1
# ============================================================================
param([switch] $ExportJson)   # -ExportJson：导出整张表为 JSON 后退出（供用法对照表生成器用）
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $root 'zhstdlib'
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force $out | Out-Null

# 每种 C 包装头里采用【原名引入】的名字（变参函数，转发不了）
$variadicNote = 'printf fprintf sprintf snprintf scanf sscanf fscanf setlocale setjmp va_start va_arg va_end va_copy'

# 表：英文头 -> @{ zh=中文头名; a=@( 条目... ) }
#   条目 = @('类型','中文名','std::英文')
#          @('函数','中文名','std::英文')
#          @('宏',  '中文名','原名','类型')
$T = [ordered]@{
  'cstddef' = @{ zh='C标准定义'; a=@(
      @('类型','大小类型','std::size_t'), @('类型','指针差类型','std::ptrdiff_t'),
      @('类型','空指针类型','std::nullptr_t'), @('类型','最大对齐类型','std::max_align_t'),
      @('类型','字节','std::byte')) }
  'cstdint' = @{ zh='C标准整数'; a=@(
      @('类型','整数8位','std::int8_t'), @('类型','整数16位','std::int16_t'),
      @('类型','整数32位','std::int32_t'), @('类型','整数64位','std::int64_t'),
      @('类型','无符号整数8位','std::uint8_t'), @('类型','无符号整数16位','std::uint16_t'),
      @('类型','无符号整数32位','std::uint32_t'), @('类型','无符号整数64位','std::uint64_t'),
      @('类型','指针整数','std::intptr_t'), @('类型','无符号指针整数','std::uintptr_t'),
      @('类型','最大整数','std::intmax_t'), @('类型','最大无符号整数','std::uintmax_t')) }
  'cstdio' = @{ zh='C标准输入输出'; a=@(
      @('类型','文件','std::FILE'),
      @('函数','打开文件','std::fopen'), @('函数','关闭文件','std::fclose'),
      @('函数','读文件','std::fread'), @('函数','写文件','std::fwrite'),
      @('函数','取字符','std::fgetc'), @('函数','放字符','std::fputc'),
      @('函数','取字符串','std::fgets'), @('函数','放字符串','std::fputs'),
      @('函数','定位文件','std::fseek'), @('函数','冲刷文件','std::fflush'),
      @('变量','标准输入','stdin','文件*'), @('变量','标准输出','stdout','文件*'),
      @('变量','标准错误','stderr','文件*'),
      @('宏','文件结束','EOF','整数')) }
  'cstdlib' = @{ zh='C标准库'; a=@(
      @('函数','分配内存','std::malloc'), @('函数','释放内存','std::free'),
      @('函数','退出','std::exit'), @('函数','取环境变量','std::getenv'),
      @('函数','转整数','std::atoi'), @('函数','转长整数','std::atol'),
      @('函数','转双精度','std::atof'), @('函数','随机数','std::rand'),
      @('函数','设随机种子','std::srand'), @('函数','绝对值','std::abs'),
      @('函数','快速排序','std::qsort'), @('函数','二分查找','std::bsearch'),
      @('函数','执行命令','std::system')) }
  'cstring' = @{ zh='C字符串'; a=@(
      @('函数','字符串长度','std::strlen'), @('函数','复制字符串','std::strcpy'),
      @('函数','连接字符串','std::strcat'), @('函数','比较字符串','std::strcmp'),
      @('函数','复制内存','std::memcpy'), @('函数','移动内存','std::memmove'),
      @('函数','填充内存','std::memset'), @('函数','比较内存','std::memcmp'),
      @('函数','查找字符','std::strchr'), @('函数','查找子串','std::strstr')) }
  'cmath' = @{ zh='C数学'; a=@(
      @('函数','平方根','std::sqrt'), @('函数','幂','std::pow'),
      @('函数','绝对值','std::fabs'), @('函数','向下取整','std::floor'),
      @('函数','向上取整','std::ceil'), @('函数','四舍五入','std::round'),
      @('函数','自然指数','std::exp'), @('函数','自然对数','std::log'),
      @('函数','常用对数','std::log10'), @('函数','正弦','std::sin'),
      @('函数','余弦','std::cos'), @('函数','正切','std::tan'),
      @('函数','反正弦','std::asin'), @('函数','反余弦','std::acos'),
      @('函数','反正切','std::atan'), @('函数','双参反正切','std::atan2'),
      @('函数','余数','std::fmod'), @('函数','双曲正弦','std::sinh')) }
  'ctime' = @{ zh='C时间'; a=@(
      @('类型','时间类型','std::time_t'), @('类型','时钟类型','std::clock_t'),
      @('类型','时间结构','std::tm'),
      @('函数','取时间','std::time'), @('函数','取时钟','std::clock'),
      @('函数','本地时间','std::localtime'), @('函数','世界时','std::gmtime'),
      @('函数','格式化时间','std::strftime'), @('函数','时间差','std::difftime')) }
  'cctype' = @{ zh='C字符类别'; a=@(
      @('函数','是字母','std::isalpha'), @('函数','是数字','std::isdigit'),
      @('函数','是空白','std::isspace'), @('函数','是标点','std::ispunct'),
      @('函数','是字母数字','std::isalnum'), @('函数','是小写','std::islower'),
      @('函数','是大写','std::isupper'), @('函数','转大写','std::toupper'),
      @('函数','转小写','std::tolower')) }
  'cwchar' = @{ zh='C宽字符'; a=@(
      @('函数','宽字符串长度','std::wcslen'), @('函数','宽字符串复制','std::wcscpy'),
      @('函数','宽字符串比较','std::wcscmp'), @('函数','宽字符串连接','std::wcscat')) }
  'cwctype' = @{ zh='C宽字符类别'; a=@(
      @('函数','是宽字母','std::iswalpha'), @('函数','是宽数字','std::iswdigit'),
      @('函数','是宽空白','std::iswspace'), @('函数','转宽大写','std::towupper'),
      @('函数','转宽小写','std::towlower')) }
  'csetjmp' = @{ zh='C跳转'; a=@( @('类型','跳转缓冲','std::jmp_buf'),
      @('函数','长跳转','std::longjmp') ) }
  'csignal' = @{ zh='C信号'; a=@(
      @('类型','信号类型','std::sig_atomic_t'),
      @('函数','信号处理','std::signal'), @('函数','引发信号','std::raise')) }
  'clocale' = @{ zh='C本地化'; a=@(
      @('类型','本地化结构','std::lconv'),
      @('函数','取本地化数值','std::localeconv')) }
  'cfenv' = @{ zh='C浮点环境'; a=@(
      @('类型','浮点环境类型','std::fenv_t'), @('类型','浮点异常类型','std::fexcept_t'),
      @('函数','清除浮点异常','std::feclearexcept'), @('函数','测试浮点异常','std::fetestexcept')) }
  'cinttypes' = @{ zh='C整数格式'; a=@(
      @('类型','整数除法结构','std::imaxdiv_t'),
      @('函数','整数除法','std::imaxdiv'), @('函数','最大整数绝对值','std::imaxabs')) }
  'cassert'    = @{ zh='C断言';     a=@() }
  'ccomplex'   = @{ zh='C复数';     a=@() }
  'cfloat'     = @{ zh='C浮点极值'; a=@( @('宏','单精度最大值','FLT_MAX','单精度'),
                                          @('宏','双精度最大值','DBL_MAX','双精度') ) }
  'climits'    = @{ zh='C整数极值'; a=@( @('宏','整数最大值','INT_MAX','整数'),
                                          @('宏','整数最小值','INT_MIN','整数'),
                                          @('宏','长整数最大值','LONG_MAX','长型') ) }
  'ciso646'    = @{ zh='C替代拼写'; a=@() }
  'cstdalign'  = @{ zh='C对齐';     a=@() }
  'cstdbool'   = @{ zh='C布尔';     a=@() }
  'ctgmath'    = @{ zh='C泛型数学'; a=@() }
  'cuchar'     = @{ zh='C字符转换'; a=@() }
  'cstdarg'    = @{ zh='C变参';     a=@() }
}

$n = 0; $cnt = @{ '类型'=0; '函数'=0; '宏'=0 }; $made = @()

# ---------------------------------------------------------------------------
#  共享名哨兵：同一个中文名被【两个头】提供时，必须用宏哨兵包住。
#
#  为什么（实测，全量组合探针抓到的第一个真问题）：
#    汉语别名全都落在同一个 标准 里，而 C 库函数在标准里是【故意重叠】的 ——
#    std::abs 既属于 <cstdlib> 也属于 <cmath>。于是 <C标准库> 和 <C数学>
#    都想声明 标准::绝对值，两个头一起引 -> error: 重定义（名字）'绝对值'。
#
#  修法：宏哨兵。哪个头先被引，名字就在哪个头里生效；两个头一起引也不冲突。
#  哨兵名必须用【ASCII】—— 宏名的中文写法还没验过，不冒这个险。
#
#  ⚠ 这张表只登记"确实重复"的名字。同类问题由 verify_zhstdlib.ps1 的
#     「全部头一起引」组合探针兜住（它会直接把重定义报出来）。
# ---------------------------------------------------------------------------
$SENTINEL = @{
    '绝对值' = '_ZH_ABS'   # std::abs (<cstdlib>) 与 std::fabs (<cmath>)
}

# ---------------------------------------------------------------------------
#  §17.24 C 轨道的**真实用例**（真编译 + 真运行）
#
#  为什么要补：这条轨道以前每个产物的核对只是
#      `#包含 <中文头>` + `整数 主函数(){ 返回 0; }`
#  —— 与 §17.19.58 别名轨道那次"空测"是同一类问题：**只证明"产品能解析"，
#  不证明"名字能用"**。26 个 C 产物因此一个名字都没被真正用过（守卫台账里
#  它们整片躺在"变参转发器：一元/二元实参都编不过"里）。
#
#  这里的每段程序都**编译成 exe 并运行**，退出码必须是 0；编不过或跑挂=红。
#  实参用真实类型（字符串/文件/缓冲区/比较器），不是整数字面量的哑实参 ——
#  这正是"哑实参天然不匹配"那批名字的唯一正解：给条目补一条真用的用例。
# ---------------------------------------------------------------------------
$TESTS = [ordered]@{
    'C字符串' = @'
#包含 <C字符串>
整数 主函数(){
    字符 甲[16] = "abc"; 字符 乙[16] = {0};
    如果 (标准::字符串长度(甲) != 3) { 返回 1; }
    标准::复制字符串(乙, 甲);
    标准::连接字符串(乙, "d");
    如果 (标准::比较字符串(乙, "abcd") != 0) { 返回 2; }
    如果 (标准::查找字符(乙, 'c') == 空指针) { 返回 3; }
    如果 (标准::查找子串(乙, "bc") == 空指针) { 返回 4; }
    标准::复制内存(乙, 甲, 4);
    如果 (标准::比较内存(乙, 甲, 4) != 0) { 返回 5; }
    标准::移动内存(乙, 甲, 4);
    标准::填充内存(乙, 0, 4);
    返回 0;
}
'@
    'C标准输入输出' = @'
#包含 <C标准输入输出>
整数 主函数(){
    常量 字符* 路径 = "build/_zhc_case.txt";
    标准::文件* 甲 = 标准::打开文件(路径, "w");
    如果 (甲 == 空指针) { 返回 1; }
    标准::放字符串("abc", 甲);
    标准::放字符('d', 甲);
    标准::写文件("ef", 1, 2, 甲);
    标准::冲刷文件(甲);
    标准::关闭文件(甲);
    甲 = 标准::打开文件(路径, "r");
    如果 (甲 == 空指针) { 返回 2; }
    字符 缓冲[16] = {0};
    如果 (标准::取字符串(缓冲, 16, 甲) == 空指针) { 返回 3; }
    标准::取字符(甲);
    标准::定位文件(甲, 0, 0);
    标准::读文件(缓冲, 1, 3, 甲);
    标准::关闭文件(甲);
    返回 0;
}
'@
    'C标准库' = @'
#包含 <C标准库>
整数 比较整数(常量 空型* 甲, 常量 空型* 乙){
    常量 整数* 左 = (常量 整数*)甲; 常量 整数* 右 = (常量 整数*)乙;
    如果 (*左 < *右) { 返回 -1; }
    如果 (*右 < *左) { 返回 1; }
    返回 0;
}
整数 主函数(){
    如果 (标准::转整数("42") != 42) { 返回 1; }
    如果 (标准::转长整数("42") != 42) { 返回 2; }
    (空型)标准::转双精度("4.2");
    (空型)标准::随机数();
    (空型)标准::取环境变量("PATH");
    整数 组[4] = {3, 1, 2, 0}; 整数 键 = 2;
    标准::快速排序(组, 4, sizeof(整数), 比较整数);
    如果 (标准::二分查找(&键, 组, 4, sizeof(整数), 比较整数) == 空指针) { 返回 3; }
    空型* 内存 = 标准::分配内存(8);
    标准::释放内存(内存);
    标准::释放内存(空指针);
    如果 (标准::执行命令("exit /b 0") != 0) { 返回 4; }
    返回 0;
}
'@
    'C时间' = @'
#包含 <C时间>
整数 主函数(){
    标准::时间类型 现 = 标准::取时间(空指针);
    (空型)标准::取时钟();
    标准::时间结构* 本 = 标准::本地时间(&现);
    标准::时间结构* 世 = 标准::世界时(&现);
    如果 (本 == 空指针 || 世 == 空指针) { 返回 1; }
    字符 缓冲[64] = {0};
    如果 (标准::格式化时间(缓冲, 64, "%Y", 本) == 0) { 返回 2; }
    返回 0;
}
'@
    'C宽字符' = @'
#包含 <C宽字符>
整数 主函数(){
    宽字符 甲[16] = L"abc"; 宽字符 乙[16] = {0};
    如果 (标准::宽字符串长度(甲) != 3) { 返回 1; }
    标准::宽字符串复制(乙, 甲);
    标准::宽字符串连接(乙, L"d");
    如果 (标准::宽字符串比较(乙, L"abcd") != 0) { 返回 2; }
    返回 0;
}
'@
    'C本地化' = @'
#包含 <C本地化>
整数 主函数(){
    标准::本地化结构* 甲 = 标准::取本地化数值();
    如果 (甲 == 空指针) { 返回 1; }
    返回 0;
}
'@
    'C跳转' = @'
#包含 <C跳转>
整数 主函数(){
    标准::跳转缓冲 缓冲;
    如果 (setjmp(缓冲) == 0) { 标准::长跳转(缓冲, 1); }
    返回 0;
}
'@
    'C信号' = @'
#包含 <C信号>
整数 主函数(){
    标准::信号处理(2, 空指针);   // SIGINT -> 默认处理
    // 引发信号 不在此调用：MSVC 的 raise(0) 走无效参数处理器，会 fail-fast（实测 0xC0000409）
    返回 0;
}
'@
}
foreach ($h in $T.Keys) { if ($TESTS.Contains($T[$h].zh)) { $T[$h]['t'] = $TESTS[$T[$h].zh] } }

# -ExportJson：把整张表以 JSON 输出后退出（供 tools\make_zh_usage.ps1 生成用法对照表）。
#   同一张表、不靠正则扫描 —— 扫描正则会漂移（见 make_zhstdlib2.ps1 同一开关的说明）。
#   §17.24：条目里多了 `t`（真实用例原文）—— 实例化守卫靠它算"用例覆盖"。
if ($ExportJson) { $T | ConvertTo-Json -Depth 8; exit 0 }

foreach ($h in $T.Keys) {
    $zh = $T[$h].zh
    $body = @()
    foreach ($e in $T[$h].a) {
        $line = $null
        switch ($e[0]) {
            '类型' { $line = ("    使用 {0} = {1};" -f $e[1], $e[2]); $cnt['类型']++ }
            # §16.52 返回类型用 声明类型(自动)：`自动` 会把引用/指针返回语义按值推导掉。
            '函数' { $line = ("    模板 <类型名... 参数> 声明类型(自动) {0}(参数&&... 值) {{ 返回 {1}(static_cast<参数&&>(值)...); }}" -f $e[1], $e[2]); $cnt['函数']++ }
            '宏'   { $line = ("    内联 常量 {0} {1} = {2};" -f $e[3], $e[1], $e[2]); $cnt['宏']++ }
            '变量' { $line = ("    内联 {0} 常量& {1} = {2};" -f $e[3], $e[1], $e[2]); $cnt['变量']++ }
        }
        if ($null -eq $line) { continue }
        if ($SENTINEL.ContainsKey($e[1])) {
            # 共享名：用宏哨兵包住，哪个头先引就在哪个头里生效
            $g = $SENTINEL[$e[1]]
            $body += "#ifndef $g"
            $body += "#define $g"
            $body += $line
            $body += "#endif // $g"
        } else {
            $body += $line
        }
    }
    $text = @"
// <$zh> —— $h 的中文别名层
//
// 为什么是别名而不是抄一份（方案铁律 4）：
//   C 包装头自己没有实现，只是把 C 库名字搬进 std；这些类型
//   **必须与全局那个是同一个类型**（对齐 / ABI）。抄一份就变成"另一种类型"。
//   实测抄 cstddef 直接炸：「using _STD max_align_t;」那条"桥"搬名域后断链。
//
// 三种机制都用上了（见 docs\标准库汉化\标准库汉化方案.md §3.4）：
//   类型 -> 使用 中文名 = std::原名;
//   函数 -> 一模板转发（函数没有"别名"机制）
//   宏   -> 内联 常量 承载它的值
//
// 英文原名照旧可用：这里只是【多一个名字】，原头一个字节没动。
// 变参 C 函数（$variadicNote）无法转发，只能继续用原名。
#pragma once
#include <$h>

名域 标准 {
$($body -join "`n")
}
"@
    [System.IO.File]::WriteAllText((Join-Path $out $zh), $text, $utf8)
    $made += $zh; $n++
}

Write-Host "=== 步骤 3：C 包装头别名层（三种机制）===" -ForegroundColor Cyan
Write-Host ("  生成 {0} 个中文头：类型 {1} 条 / 函数 {2} 条 / 宏 {3} 条" -f $n, $cnt['类型'], $cnt['函数'], $cnt['宏'])

# 删掉抄坏的副本（它们在 shadow 真正的 <cstddef> 等）
$victims = 0
foreach ($h in $T.Keys) { $p = Join-Path $out $h; if (Test-Path $p) { Remove-Item $p -Force; $victims++ } }
Write-Host ("  已删除抄坏的副本 {0} 个" -f $victims) -ForegroundColor Yellow

# ---------------------------------------------------------------------------
#  把【还没翻译完的英文名副本】挪出 zhstdlib\，挪到 build\zhstdlib_raw\
#
#  为什么必须挪：英文名的副本会【shadow 微软真头】。实测 zhstdlib\type_traits
#  把真 <type_traits> 挤掉，于是所有 #include <type_traits> 的头都报
#  「std 中没有名为 declval 的模板」—— 连累 cmath / ccomplex / ctgmath。
#  中文文件名不是"最后美化一下"，它是让"并存"成立的前提（方案 §3.5）。
#  所以在阶段 2 定好中文文件名之前，未完成品一律不放 zhstdlib\。
# ---------------------------------------------------------------------------
$rawDir = Join-Path $root 'build\zhstdlib_raw'
New-Item -ItemType Directory -Force $rawDir | Out-Null
$moved = 0
Get-ChildItem $out -File | Where-Object { $_.Name -match '^[A-Za-z_][A-Za-z0-9_]*$' } | ForEach-Object {
    Move-Item $_.FullName (Join-Path $rawDir $_.Name) -Force; $moved++
}
Write-Host ("  已把 {0} 个未完成的英文名副本挪到 build\zhstdlib_raw\（它们会 shadow 真头）" -f $moved) -ForegroundColor Yellow

# 验证
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
$bad | ForEach-Object { Write-Host ("    {0,-16} {1}" -f $_.Zh, $_.Err) -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
#  §17.24 真实用例：**编译 + 运行**（不再只是"能 include"）
#    · 编不过或运行退出码 != 0 一律红 —— "跑 0 条的通过不是通过"
#    · 摘要行刻意不写成 `N / M`，免得闸门把它的收尾行解析错（闸门认的是上一行）
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 真实用例（编译 + 运行）===" -ForegroundColor Cyan
$caseTmp = Join-Path $root 'build\_zhc_case'
if (Test-Path $caseTmp) { Remove-Item -Recurse -Force $caseTmp }
New-Item -ItemType Directory -Force $caseTmp | Out-Null
$caseOk = 0; $caseBad = @(); $caseNone = @()
foreach ($h in $T.Keys) {
    $zh = $T[$h].zh
    if (-not $TESTS.Contains($zh)) { $caseNone += $zh; continue }
    $csrc = Join-Path $caseTmp 'r.cpp'; $cexe = Join-Path $caseTmp 'r.exe'
    [System.IO.File]::WriteAllText($csrc, $TESTS[$zh], $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" `"$csrc`" -o `"$cexe`" > `"$caseTmp\o.txt`" 2>&1"
    if ($LASTEXITCODE -ne 0) {
        $first = Get-Content "$caseTmp\o.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' } | Select-Object -First 1
        $caseBad += [pscustomobject]@{ Zh = $zh; What = '编译'; Err = ([string]$first).Trim() }
        continue
    }
    & $cexe | Out-Null
    if ($LASTEXITCODE -ne 0) { $caseBad += [pscustomobject]@{ Zh = $zh; What = '运行'; Err = "退出码 $LASTEXITCODE" }; continue }
    $caseOk++
}
Remove-Item -Recurse -Force $caseTmp -ErrorAction SilentlyContinue
Write-Host ("  真实用例通过 {0} 个；失败 {1} 个；无用例 {2} 个（{3}）" -f $caseOk, $caseBad.Count, $caseNone.Count, ($caseNone -join ' ')) -ForegroundColor $(if ($caseBad.Count) { 'Red' } else { 'Green' })
$caseBad | ForEach-Object { Write-Host ("    {0,-16} {1}：{2}" -f $_.Zh, $_.What, $_.Err) -ForegroundColor Red }
if ($caseBad.Count) { Write-Host "❌ C 轨道真实用例有失败 —— 不许带红提交" -ForegroundColor Red; exit 1 }

# ⚠ 闸门（regen_zhstdlib.ps1）对 `Once` 型生成器**只取最后一行**并解析 `N / M`。
#   所以这一行必须**永远是最后一行** —— 任何新摘要都排在它前面。
#   （第一次加真实用例时就是栽在这：摘要排在了后面，闸门把生成器判成 FAIL。）
Write-Host ("  通过 {0} / {1}" -f $ok, $n) -ForegroundColor Green
