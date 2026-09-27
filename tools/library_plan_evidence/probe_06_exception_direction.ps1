# 异常类型能不能"抄一份"？—— 这决定了 stdexcept 那一族要不要特殊处理。
$ErrorActionPreference = 'Continue'
$cxx  = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$root = 'E:\Chinese++\build\_excp'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Force $root | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Zh([string]$c){ $s=''; foreach($x in $c.Split(',')){ $s += [char][int]("0x"+$x.Trim()) }; return $s }
$BZ = Zh '6807,51C6'                  # 标准
$YX = Zh '5F02,5E38'                  # 异常
$YXCW = Zh '8FD0,884C,65F6,9519,8BEF' # 运行时错误
$LZ = Zh '903B,8F91,9519,8BEF'        # 逻辑错误

$hdr = @"
#pragma once
#include <stdexcept>
#include <string>
namespace $BZ {
    // 甲：抄一份式 —— 在自己的名域里重新定义一个（模拟"抄来翻译"的结果）
    类型 $YXCW : 公开 std::runtime_error {
        使用 std::runtime_error::runtime_error;
    };
    // 乙：派生式 —— 在 std 的基础上派生（另一种做法）
    类型 $LZ : 公开 std::logic_error {
        使用 std::logic_error::logic_error;
    };
}
"@
[System.IO.File]::WriteAllText((Join-Path $root '标准异常.h'), $hdr, $utf8)

$inc = @('-std=c++20', "-isystem$root")
function T([string]$label,[string]$body,[int]$expect){
    $src = Join-Path $root 't.cpp'
    [System.IO.File]::WriteAllText($src,$body,$utf8)
    $exe = Join-Path $root 't.exe'
    $o = & $cxx @inc -o $exe $src 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "===== $label"
        Write-Host "  编译失败: $(([string]($o|Select-Object -First 1)).Trim())"
        return
    }
    & cmd /c "`"$exe`" >nul 2>&1"
    $r = $LASTEXITCODE
    $mark = if ($r -eq $expect) {'ok  '} else {'DIFF'}
    Write-Host ""
    Write-Host "===== $label"
    Write-Host "  返回 $r （期望 $expect）  [$mark]"
}

Write-Host ''
Write-Host '=== 异常捕获的兼容性 ==='

T "① 第三方抛 std::runtime_error，用【中文抄来的类型】捕获" @"
#include <标准异常.h>
int main(){
    尝试 { 抛出 std::runtime_error("第三方抛的"); }
    捕获 ($BZ::$YXCW& e) { 返回 0; }
    捕获 (...) { 返回 1; }
}
"@ 1

T "② 第三方抛 std::runtime_error，用【英文原名】捕获（对照）" @"
#include <标准异常.h>
int main(){
    尝试 { 抛出 std::runtime_error("第三方抛的"); }
    捕获 (std::runtime_error& e) { 返回 0; }
    捕获 (...) { 返回 1; }
}
"@ 0

T "③ 【派生的】中文类型抛出去，英文原名能否捕获" @"
#include <标准异常.h>
int main(){
    尝试 { 抛出 $BZ::$LZ("我们抛的"); }
    捕获 (std::logic_error& e) { 返回 0; }
    捕获 (...) { 返回 1; }
}
"@ 0

T "④ 派生容器里，std::exception 能否兜住中文异常" @"
#include <标准异常.h>
int main(){
    尝试 { 抛出 $BZ::$LZ("我们抛的"); }
    捕获 (std::exception& e) { 返回 0; }
    捕获 (...) { 返回 1; }
}
"@ 0
