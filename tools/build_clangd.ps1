# 中文 C++ 项目 —— 在既有 MSBuild 构建树上补完 clang-tools-extra，产出 clangd.exe
#
# 背景（来自系统事件日志，2026-09-21 22:43）：
#   CL.exe      崩溃，出错模块 c1xx.dll，异常码 0xc00000fd（栈溢出）
#   CL.exe      崩溃，异常码 0xe06d7363（C++ 异常，通常是 bad_alloc）
#   MSBuild.exe 未处理异常 System.OutOfMemoryException
# 原因：32 逻辑 CPU × MSBuild /m 默认 32 路 × 每个项目内 /MP 再开一批 c1xx，
#       单进程峰值 1.5-3 GB，而本机提交上限只有约 36 GB。属于内存耗尽，不是生成器缺陷。
#
# 对策：只编 clangd 这一个可执行目标，并把并发压到内存装得下的水平。
#   /p:CL_MPCount=1   每个项目只开 1 个 c1xx（等价于 Ninja 的一编译单元一进程）
#   /m:N              全局最多 N 个并发编译器，N 由可用提交余量推算
# 现有 122 个静态库 / 2976 个 .obj 全部复用，不需要重编任何 LLVM/clang 基础库。
#
# 两个踩过的坑：
#   1) MSBuild.exe 位于 Visual Studio 安装目录（工作区之外），需要放宽文件沙箱才能启动。
#   2) 不能用 `msbuild LLVM.sln /t:clangd`：MSBuild 会把目标名传播给被引用的项目，
#      而 ZERO_CHECK.vcxproj 没有 "clangd" 目标，直接报 MSB4057。改为直接编 vcxproj。
# 控制台信息一律使用 ASCII，避免宿主按非 UTF-8 代码页解码时出现乱码。

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root    = 'E:\Chinese++'
$Proj    = Join-Path $Root 'build\tools\clang\tools\extra\clangd\tool\clangd.vcxproj'
$MsBuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe'
$LogDir  = Join-Path $Root 'build\_clangd_build'
$Clangd  = Join-Path $Root 'build\Release\bin\clangd.exe'

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-CommitHeadroomGB {
    try {
        $s = (Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit' -ErrorAction Stop).CounterSamples
        $c = ($s | Where-Object Path -match 'committed').CookedValue
        $l = ($s | Where-Object Path -match 'limit').CookedValue
        return [math]::Round(($l - $c) / 1GB, 1)
    } catch { return $null }
}

# 每个并发编译器预留约 4 GB（Release 下 clang-tidy / clangDaemon 的大 TU 实测量级）
$headroom = Get-CommitHeadroomGB
if ($null -eq $headroom) { $first = 4 } else { $first = [math]::Floor($headroom / 4) }
if ($first -lt 1) { $first = 1 }
if ($first -gt 8) { $first = 8 }

$levels = @()
$n = $first
while ($n -ge 1) { $levels += $n; if ($n -eq 1) { break }; $n = [math]::Floor($n / 2) }

$hrText = if ($null -eq $headroom) { 'unknown' } else { "$headroom GB" }
Write-Output "commit headroom: $hrText  ->  initial parallelism: /m:$first"
Write-Output "attempt sequence: $($levels -join ' , ')"
Write-Output "project: $Proj"
Write-Output ""

if (-not (Test-Path $Proj))   { Write-Output "project not found: $Proj";   exit 2 }
if (-not (Test-Path $MsBuild)){ Write-Output "MSBuild not found: $MsBuild"; exit 2 }

$succeeded = $false
foreach ($m in $levels) {
    $log = Join-Path $LogDir ("msbuild_m{0}.log" -f $m)
    if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
    $h = Get-CommitHeadroomGB
    $hText = if ($null -eq $h) { '?' } else { "$h GB" }
    Write-Output "=============================================================="
    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] msbuild clangd.vcxproj /m:$m /p:CL_MPCount=1   (headroom $hText)"
    Write-Output "  log: $log"
    Write-Output "=============================================================="
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $MsBuild $Proj /p:Configuration=Release /p:Platform=x64 `
        /m:$m /p:CL_MPCount=1 /nodeReuse:false /nologo /v:n 2>&1 |
        Out-File -FilePath $log -Encoding utf8
    $code = $LASTEXITCODE
    $sw.Stop()
    Write-Output ("[$(Get-Date -Format 'HH:mm:ss')] exit code $code, elapsed {0:N1} min" -f $sw.Elapsed.TotalMinutes)

    # 程序根本没启动起来（沙箱/路径问题）：重试其它并发度没有意义，直接退出
    $started = $false
    if (Test-Path $log) {
        $raw = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($raw -and $raw.Length -gt 32 -and $raw -notmatch 'failed to run|Access is denied') { $started = $true }
    }
    if (-not $started) {
        Write-Output "--- MSBuild did not start; log head ---"
        if (Test-Path $log) { Get-Content $log -TotalCount 20 | ForEach-Object { '  ' + $_ } }
        Write-Output "--- end ---"
        Write-Output "ABORT: launcher problem, not a compile problem."
        exit 3
    }

    if ($code -eq 0) { $succeeded = $true; break }

    Write-Output "--- key errors, last 25 ---"
    Select-String -Path $log -Pattern 'error [A-Z]+[0-9]+|fatal error|: error|MSB[0-9]{4}|OutOfMemory|stack overflow' -ErrorAction SilentlyContinue |
        Select-Object -Last 25 | ForEach-Object { '  ' + $_.Line.Trim() }
    Write-Output "--- end errors ---"
}

Write-Output ""
if ($succeeded -and (Test-Path $Clangd)) {
    $f = Get-Item $Clangd
    Write-Output "SUCCESS: $($f.FullName)  $([math]::Round($f.Length/1MB,1)) MB  $($f.LastWriteTime)"
    exit 0
}
Write-Output "NOT SUCCESSFUL. clangd.exe exists: $(Test-Path $Clangd)"
exit 1
