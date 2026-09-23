# 验证新构建的 clangd：能否用改过的词法表识别中文关键字
#
# 用法: powershell -File E:\Chinese++\tests\checks\verify_clangd.ps1
#
# 意义：clangd 只影响 IDE 里的语法高亮与补全。它能认出中文关键字，靠的就是我们
# 改过的同一套 clang 词法关键字表（clang/include/clang/Basic/ChineseKeywords.def，
# 由 lib/Basic/IdentifierTable.cpp 展开 ZH_KEYWORD 宏）。
#
# 判定依据（全部来自读源码，不是猜的）：
#   clang-tools-extra/clangd/tool/Check.cpp
#     showErrors()            只在 Severity >= Error 时计入 ErrCount，打印格式为
#                             "E[时间] [检查名] Line N: 消息"
#     check() 结尾            return C.ErrCount == 0;  并打印 "All checks completed, N errors"
#     ClangdMain.cpp:1058     直接把这个 bool 当进程退出码
#     Check.cpp:439           ++ErrCount 位于 testLocationFeatures() 内部，即
#                             "逐个位置试各种重构" 的失败也会算进 ErrCount
#   => 必须加 --check-locations=false，退出码才只反映真正的诊断。
#      （默认 true，会在 `跳过;`/`跳出;` 上触发 ExtractFunction 的固有失败，
#        让一个完全正确的文件也报 3 errors，这是个纯粹的假阳性。）
#
# 设计要点：
#   1) 用【不含任何 #include】的用例，避免依赖 compile_commands.json；
#   2) 配一个【故意写错】的对照组，若对照组也不报错，说明判定失效、结论不可信。
#
# 注意：本文件必须带 UTF-8 BOM 保存。宿主是 Windows PowerShell 5.1，无 BOM 的
# UTF-8 脚本会被按 ANSI(GBK) 解码，中文字符串会被拆成乱码字节并导致语法错误。

$ErrorActionPreference = 'Continue'

$Clangd    = 'E:\Chinese++\build\Release\bin\clangd.exe'
$GoodSrc   = 'E:\Chinese++\tests\09-diagnostics\min_ok.cpp'
$BadSrc    = 'E:\Chinese++\tests\09-diagnostics\token_glue_bad.cpp'
$LogDir    = 'E:\Chinese++\build\_clangd_build'
$CheckArgs = @('--check-locations=false')

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$script:Out = New-Object System.Collections.ArrayList
function Say([string]$s) { [void]$script:Out.Add($s) }

Say '=============================================================='
Say 'clangd 中文关键字验证'
Say '=============================================================='

if (-not (Test-Path $Clangd)) { Say "FAIL: 找不到 $Clangd"; $script:Out | ForEach-Object { $_ }; exit 1 }
$f = Get-Item $Clangd
Say ("binary : {0}" -f $f.FullName)
Say ("size   : {0:N1} MB    built: {1}" -f ($f.Length / 1MB), $f.LastWriteTime)
Say ("check  : --check=<file> {0}" -f ($CheckArgs -join ' '))
Say ''

# --- 1. --version -------------------------------------------------------
Say '--- 1. --version ---'
$ver = (& $Clangd --version 2>&1 | Out-String)
if ($ver -match 'failed to run|Access is denied') {
    Say '  FAIL: clangd.exe 无法启动（沙箱/权限），不是 clangd 本身的问题。'
    Say ('  请在普通终端里手动执行: ' + $Clangd + ' --version')
    Say ''
    $script:Out | ForEach-Object { $_ }
    exit 3
}
($ver -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { Say ('  ' + $_.Trim()) }
Say ''

# --- 2/3. 正例与对照组 ---------------------------------------------------
function Invoke-Check {
    param([string]$Path, [string]$Label)

    Say "--- $Label ---"
    Say "  file: $Path"
    if (-not (Test-Path $Path)) { Say '  SKIP (文件不存在)'; Say ''; return $null }

    $leaf   = Split-Path $Path -Leaf
    $outLog = Join-Path $LogDir "$leaf.stdout.log"
    $errLog = Join-Path $LogDir "$leaf.stderr.log"
    $allLog = Join-Path $LogDir "$leaf.check.log"

    # 用文件重定向而不是 2>&1 | Out-String：后者会把 stderr 包成 PowerShell 错误记录，
    # 在文本里混入 "At line ... CategoryInfo" 之类的噪声。
    & $Clangd "--check=$Path" @CheckArgs 1>$outLog 2>$errLog
    $code = $LASTEXITCODE

    $raw = ((Get-Content $outLog -Raw -EA SilentlyContinue) + "`n" +
            (Get-Content $errLog -Raw -EA SilentlyContinue))
    $raw | Set-Content -Path $allLog -Encoding UTF8

    $m        = [regex]::Match($raw, 'All checks completed,\s*(\d+)\s+errors')
    $reported = if ($m.Success) { [int]$m.Groups[1].Value } else { -1 }
    $diags    = @(($raw -split "`r?`n") | Where-Object { $_ -match '\] Line \d+: ' })
    $parsed   = ($raw -match 'Building AST')

    Say ("  退出码: {0}    clangd 报告错误数: {1}    Line 诊断: {2}    走到 Building AST: {3}" -f `
         $code, $reported, $diags.Count, $parsed)
    if ($diags.Count -gt 0) {
        $diags | Select-Object -First 6 | ForEach-Object { Say ('    ' + $_.Trim()) }
    }
    Say ("  明细日志: {0}" -f $allLog)
    Say ''
    return [pscustomobject]@{
        ExitCode = $code; Reported = $reported; Diags = $diags.Count; Parsed = $parsed
    }
}

$good = Invoke-Check -Path $GoodSrc -Label '2. 正例：纯中文关键字，期望 退出码 0 / 0 errors'
$bad  = Invoke-Check -Path $BadSrc  -Label '3. 对照组：故意写错（返回甲），期望 退出码非 0 / >=1 error'

# --- 结论 --------------------------------------------------------------
Say '=============================================================='
$ok = $true
if ($null -eq $good -or $good.ExitCode -ne 0 -or $good.Reported -ne 0) {
    Say ("不通过: 中文正例 退出码={0} 报告错误数={1}，有关键字未被识别。" -f `
         $(if($good){$good.ExitCode}else{'N/A'}), $(if($good){$good.Reported}else{'N/A'}))
    $ok = $false
}
if ($null -eq $good -or -not $good.Parsed) {
    Say '不通过: 正例没有走到 "Building AST"，解析流程未完整跑完。'
    $ok = $false
}
if ($null -eq $bad -or $bad.ExitCode -eq 0 -or $bad.Diags -lt 1) {
    Say '不可信: 对照组没有报错，说明判定路径失效，正例结果无意义。'
    $ok = $false
}
if ($ok) {
    Say '结论: 通过。clangd 用改过的词法表识别中文关键字，IDE 标红问题应已解决。'
    Say ''
    Say 'CLion 配置: Settings -> Languages and Frameworks -> Clangd'
    Say "  把 clangd 可执行文件指向: $Clangd"
}
Say '=============================================================='

$script:Out | ForEach-Object { $_ }
if ($ok) { exit 0 } else { exit 1 }
