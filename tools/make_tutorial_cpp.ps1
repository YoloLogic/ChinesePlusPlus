# 由「模板 + 真源码」生成《Chinese++ 教学教程》。
#
# 为什么要生成而不是手写：
#   教程里嵌的代码必须【与能跑的例子逐字一致】。手抄的副本一定会漂
#   （本项目已经栽过多次「两份副本各说各话」，见 §18.54 那次真事故）。
#   所以教程正文写在 教程\教程模板.md 里，例子代码从 教程\例子\*.cpp 切进去，
#   期望输出也从例子的头部注释里抽出来 —— 三份东西只有一个真相。
#
# 用法：
#   pwsh -File tools\make_tutorial_cpp.ps1          # 生成 教程\Chinese++-教学教程.md
#   pwsh -File tools\make_tutorial_cpp.ps1 -Check   # 只核对，不写盘（闸门用）
#
# 模板里的占位符：
#   {{例子:01-骨架.cpp}}       -> 该例子文件的全文
#   {{期望输出:01-骨架.cpp}}    -> 该例子头部注释里「// 期望输出：」之后的那些行
#
# 例子头部的约定（生成器与守卫都按这个约定解析）：
#   // 期望输出：
#   // 第一行
#   // 第二行
#   （遇到空注释行或非注释行即结束）

param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tplPath = Join-Path $root '教程\教程模板.md'
$outPath = Join-Path $root '教程\Chinese++-教学教程.md'
$exDir = Join-Path $root '教程\例子'

if (-not (Test-Path $tplPath)) { throw "找不到模板：$tplPath" }
if (-not (Test-Path $exDir)) { throw "找不到例子目录：$exDir" }

# 从例子文件里抽出「期望输出」那些行
function Get-Expected([string]$path) {
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    $out = New-Object System.Collections.Generic.List[string]
    $in = $false
    foreach ($line in $lines) {
        $t = $line.Trim()
        if (-not $in) {
            if ($t -match '^//\s*期望输出[:：]\s*$') { $in = $true }
            continue
        }
        if (-not $t.StartsWith('//')) { break }
        $body = $t.Substring(2).Trim()
        if ($body -eq '') { break }   # 空注释行 = 期望输出到此为止
        $out.Add($body)
    }
    if ($out.Count -eq 0) { throw "例子 $path 里没有「// 期望输出：」块（或块是空的）" }
    return $out
}

$tpl = [System.IO.File]::ReadAllText($tplPath)

# ---------- 关键字总表：从权威的《中文对照表》切进来 ----------
# 为什么这么干：本仓已经有编译器真正在用、且由 tools\make_cheatsheet.py 生成的
# 《中文对照表》（packaging\中文对照表.md），并有第 27 道守卫防它漂移。
# 教学教程不该让读者跳去别处查表，也不该手抄一份（手抄必漂）。
# 所以把它的第一～四节（关键字 / 运算符替代拼写 / 预处理指令 / 入口点）原样切进来；
# 切进来之后由本脚本的 -Check 负责「表变了教程就得重新生成」。
$cheatsheetPath = Join-Path $root 'packaging\中文对照表.md'
if (-not (Test-Path $cheatsheetPath)) { throw "找不到权威对照表：$cheatsheetPath" }
$csText = [System.IO.File]::ReadAllText($cheatsheetPath)
$csStart = $csText.IndexOf('## 一、')
$csEnd = $csText.IndexOf('## 五、')
if ($csStart -lt 0 -or $csEnd -le $csStart) { throw '对照表结构变了：取不到第一～四节（生成器要跟着改）' }
$keywordTables = $csText.Substring($csStart, $csEnd - $csStart).TrimEnd()
# 切片里的 ## 标题降一级成 ###，免得与教程自己的「## 第 N 课」并列
$keywordTables = [regex]::Replace($keywordTables, '(?m)^## ', '### ')
$tpl = $tpl.Replace('{{关键字总表}}', $keywordTables)

# 收集模板里引用到的例子名
$names = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($tpl, '\{\{(?:例子|期望输出):([^}]+)\}\}')) {
    if (-not $names.Contains($m.Groups[1].Value)) { $names.Add($m.Groups[1].Value) }
}
if ($names.Count -eq 0) { throw '模板里没有 {{例子:...}} 占位符（模板被改坏了？）' }

$text = $tpl
foreach ($name in $names) {
    $p = Join-Path $exDir $name
    if (-not (Test-Path $p)) { throw "模板引用了不存在的例子：$name" }
    $src = ([System.IO.File]::ReadAllText($p)).TrimEnd("`r", "`n")
    $exp = (Get-Expected $p) -join "`n"
    $text = $text.Replace("{{例子:$name}}", $src)
    $text = $text.Replace("{{期望输出:$name}}", $exp)
}

# 占位符必须全部被替换掉
$left = [regex]::Matches($text, '\{\{(?:例子|期望输出):[^}]+\}\}')
if ($left.Count -gt 0) { throw ("还有没被替换的占位符：{0}" -f (($left | ForEach-Object { $_.Value }) -join '、')) }

if ($Check) {
    if (-not (Test-Path $outPath)) { throw "缺少 $outPath，请先运行 tools\make_tutorial_cpp.ps1" }
    $cur = [System.IO.File]::ReadAllText($outPath)
    if ($cur -ne $text) {
        throw ("教程与模板/例子不一致：$outPath`n" +
               "  请运行 tools\make_tutorial_cpp.ps1 并提交结果；`n" +
               "  若你手改过教程正文，请把改动搬进 教程\教程模板.md（它才是正文的真相）。")
    }
    Write-Host ("教程与模板/例子一致（{0} 个例子，{1} 行）：{2}" -f $names.Count, ($text -split "`n").Count, $outPath)
    exit 0
}

[System.IO.File]::WriteAllText($outPath, $text)
Write-Host ("已生成 {0}（{1} 个例子，{2} 行）" -f $outPath, $names.Count, ($text -split "`n").Count)
