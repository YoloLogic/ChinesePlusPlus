# 《Chinese++ 教学教程》守卫 —— 真编译、真运行、逐行核对期望输出。
#
# 本守卫做四件事：
#   ① 教程正文与「模板 + 例子源码」一致（转调 make_tutorial_cpp.ps1 -Check）
#   ② 逐个例子【真编译】（chinese++.exe）—— 编译不过就是失败
#   ③ 逐个例子【真运行】，把实际输出与例子头部声明的「期望输出」逐行比对
#   ④ 自带自测：故意把某条期望输出改掉，比对必须报不一致
#      —— 判据要能失败，否则它是橡皮图章
#
# 为什么比对的还是「例子头部声明的期望输出」而不是教程里的文本：
#   教程里的输出是由 make_tutorial_cpp.ps1 从同一个来源切进去的（第①项已核对），
#   所以只要①③过了，教程里印的输出也必然与实际一致 —— 一个真相，两处呈现。
#
# 用法：
#   pwsh -File tools\check_tutorial_cpp.ps1
#   pwsh -File tools\check_tutorial_cpp.ps1 -Quiet

param(
    [string]$Cxx = 'E:\Chinese++\build\Release\bin\chinese++.exe',
    [string]$Work = 'E:\Chinese++\build\_review_own\tutorial',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exDir = Join-Path $root '教程\例子'
$bad = 0

function Say([string]$s) { if (-not $Quiet) { Write-Host $s } }

# 与 make_tutorial_cpp.ps1 用同一个约定解析「// 期望输出：」块
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
        if ($body -eq '') { break }
        $out.Add($body)
    }
    return $out
}

# 逐行比对：行尾空格不计较（有些例子为了排版会在行尾留一个空格）
function Compare-Output($expected, $actual) {
    $e = @($expected | ForEach-Object { $_.TrimEnd() })
    $a = @($actual | ForEach-Object { $_.TrimEnd() })
    if ($e.Count -ne $a.Count) { return "行数不同：期望 $($e.Count) 行，实际 $($a.Count) 行" }
    for ($i = 0; $i -lt $e.Count; $i++) {
        if ($e[$i] -cne $a[$i]) { return "第 $($i + 1) 行不同：期望「$($e[$i])」，实际「$($a[$i])」" }
    }
    return $null
}

# ---------- ① 教程与模板/例子一致 ----------
Say '=== ① 教程正文与模板/例子是否一致 ==='
& pwsh -NoProfile -File (Join-Path $root 'tools\make_tutorial_cpp.ps1') -Check
if ($LASTEXITCODE -ne 0) { Write-Host '  ❌ 教程与模板/例子不一致（见上面的提示）' -ForegroundColor Red; $bad++ }
else { Say '  ✅ 一致' }

# ---------- ②③ 逐个例子真编译真运行 ----------
Say ''
Say '=== ②③ 逐个例子真编译 + 真运行 + 比对期望输出 ==='
if (-not (Test-Path $Cxx)) { throw "找不到编译器：$Cxx" }
New-Item -ItemType Directory -Force -Path $Work | Out-Null

# 先守【例子目录的构成】：只许有 `NN-名字.cpp`，且不许为空。
# 为什么加它（2026-10-07 真事故）：一次失败的 PowerShell 操作（.NET 用的是进程目录、
# 不认 Set-Location）在例子目录里留下了一个【空的 .chts 文件】，被闸门一并提交了 ——
# 而它是空的，编译器与后续检查都不会吭声。所以构成也要机器守。
$all = @(Get-ChildItem $exDir -File | Sort-Object Name)
$stray = @($all | Where-Object { $_.Name -notmatch '^\d\d-.+\.cpp$' })
$empty = @($all | Where-Object { $_.Length -eq 0 })
if ($stray.Count -eq 0 -and $empty.Count -eq 0) { Say ("  ✅ 例子目录构成正常（{0} 个 .cpp，无杂项、无空文件）" -f $all.Count) }
else {
    if ($stray.Count -gt 0) { Write-Host ("  ❌ 例子目录里有多余文件（只许 NN-名字.cpp）：{0}" -f (($stray | ForEach-Object { $_.Name }) -join '、')) -ForegroundColor Red }
    if ($empty.Count -gt 0) { Write-Host ("  ❌ 例子目录里有空文件：{0}" -f (($empty | ForEach-Object { $_.Name }) -join '、')) -ForegroundColor Red }
    $bad++
}

$files = @(Get-ChildItem "$exDir\*.cpp" | Sort-Object Name)
if ($files.Count -eq 0) { throw "例子目录里没有 .cpp：$exDir" }

$passed = 0
foreach ($f in $files) {
    $exe = Join-Path $Work ($f.BaseName + '.exe')
    if (Test-Path $exe) { Remove-Item $exe -Force }
    $compileLog = & $Cxx -std=c++20 -O0 -o $exe $f.FullName 2>&1 | Out-String
    if (-not (Test-Path $exe)) {
        Write-Host ("  ❌ {0}：编译失败" -f $f.Name) -ForegroundColor Red
        ($compileLog.Trim() -split "`n" | Select-Object -First 6) | ForEach-Object { Write-Host "      $_" }
        $bad++
        continue
    }
    $actual = @(& $exe 2>&1)
    $expected = Get-Expected $f.FullName
    $diff = Compare-Output $expected $actual
    if ($diff) {
        Write-Host ("  ❌ {0}：{1}" -f $f.Name, $diff) -ForegroundColor Red
        $bad++
    } else {
        Say ("  ✅ {0}（{1} 行输出逐行相符）" -f $f.Name, $expected.Count)
        $passed++
    }
}

# ---------- ④ 自带自测：把期望输出改掉，比对必须报不一致 ----------
Say ''
Say '=== ④ 自带自测：改掉一条期望输出，必须被抓住 ==='
$probe = $files[0]
$probeExe = Join-Path $Work ($probe.BaseName + '.exe')
if (Test-Path $probeExe) {
    $actual = @(& $probeExe 2>&1)
    $exp = @(Get-Expected $probe.FullName)
    $mutated = @($exp)
    $mutated[0] = $mutated[0] + '（这是故意改坏的）'
    $caught = [bool](Compare-Output $mutated $actual)
    if ($caught) { Say ("  ✅ 改坏后被抓住（{0}）" -f (Compare-Output $mutated $actual)) }
    else { Write-Host '  ❌ 改坏了却仍判通过 —— 本守卫是橡皮图章' -ForegroundColor Red; $bad++ }
} else {
    Write-Host '  ❌ 自测无法进行：探针例子没编译出 exe' -ForegroundColor Red
    $bad++
}

# ---------- ⑤ Word 文档（.docx）与教程正文同步 ----------
Say ''
Say '=== ⑤ Word 文档（.docx）是否与教程正文同步 ==='
$docxGen = Join-Path $root 'tools\make_tutorial_docx.ps1'
if (-not (Test-Path $docxGen)) {
    Write-Host '  ❌ 找不到 tools\make_tutorial_docx.ps1' -ForegroundColor Red
    $bad++
} else {
    & pwsh -NoProfile -File $docxGen -Check
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  ❌ docx 与教程正文不同步（见上面提示）' -ForegroundColor Red
        $bad++
    } else { Say '  ✅ 同步' }
}

# ---------- 结论 ----------
Say ''
if ($bad -eq 0) {
    Say ("教学教程守卫：通过（{0} 个例子全部真编译真运行、输出逐行相符；判据自测已证明会失败；docx 与正文同步）" -f $passed)
    exit 0
}
Write-Host ("教学教程守卫：失败 {0} 处" -f $bad) -ForegroundColor Red
exit 1
