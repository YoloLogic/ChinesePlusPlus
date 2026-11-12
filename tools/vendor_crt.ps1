# ============================================================================
#  vendor_crt.ps1 -- 把【链接层地基】做进仓库（§18.48 批3）
#
#  产出（都落在 vendor\crt\，打包时复制到 <包>\lib\crt\）：
#    · 我们的 CRT：libcmt.lib（crt0.obj + newdelete.obj + stl-internals.obj）与 oldnames.lib（占位）
#      —— 顶掉 clang 默认的 `-defaultlib:libcmt -defaultlib:oldnames`；
#    · 导入库：msvcp140 / vcruntime140 / vcruntime140_1 —— 用 gendef 从**我们随包的 DLL** 导出表生成；
#    · 系统层导入库：ucrt / ucrtbase / kernel32 / user32 / gdi32 / comctl32 / ole32 / oleaut32 /
#      shell32 / advapi32 / uuid —— 直接抄 mingw-w64 的（public domain，绑到 ucrtbase.dll/kernel32.dll 等）。
#
#  合规口径（写进 SOURCE.txt）：Windows SDK 与 MSVC CRT 的**二进制**不许随包；我们发的是
#    (a) 自己写的启动对象/运行时胶水；(b) 从**我们随包的 DLL**导出表生成的导入库；(c) mingw 的 public domain 导入库。
#    导入库本身只是"DLL 导出名 + 跳转桩"（事实性接口信息）。
#
#  构建机需要（都在本机实测可用）：
#    · 我们的编译器 build\Release\bin\chinese++.exe（编 vendor\crt\*.c/*.cpp）
#    · mingw-w64：gendef.exe 与 x86_64-w64-mingw32\lib\lib*.a
#    · 微软 VS 的 lib.exe（把 .def 变成 .lib、把 obj 打成库；**产物**入库，工具不随包）
#
#  用法：
#    pwsh -NoProfile -File tools\vendor_crt.ps1
#    pwsh -NoProfile -File tools\vendor_crt.ps1 -Check
# ============================================================================
param(
    [string] $MingwRoot,
    [string] $CrtDllDir,
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$dest = Join-Path $root 'vendor\crt'
$src  = Join-Path $root 'vendor\crt'          # crt0.c / newdelete.cpp / stl-internals.cpp 就在这里面
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work = Join-Path $root 'build\_vendor_crt'

function Find-MingwPaths([string] $Hint) {
    $roots = @()
    if ($Hint) { $roots += $Hint }
    $roots += @('E:\c++\mingw64', 'C:\msys64\mingw64', 'E:\CLion 2026.1.2\bin\mingw', 'C:\mingw64')
    foreach ($r in $roots) {
        $lib = Join-Path $r 'x86_64-w64-mingw32\lib'
        $gd  = Join-Path $r 'bin\gendef.exe'
        if ((Test-Path $lib) -and (Test-Path $gd)) { return @{ Root = $r; Lib = $lib; GenDef = $gd } }
    }
    throw '找不到 mingw-w64（需要 bin\gendef.exe 与 x86_64-w64-mingw32\lib）—— 用 -MingwRoot 指定'
}

function Find-VsTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $roots = @()
    if (Test-Path $vswhere) {
        $p = & $vswhere -latest -products * -property installationPath 2>$null
        if ($p) { $roots += $p.Trim() }
    }
    foreach ($r in $roots) {
        $lib = Get-ChildItem (Join-Path $r 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'bin\Hostx64\x64\lib.exe' } |
               Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($lib) {
            $redist = Get-ChildItem (Join-Path $r 'VC\Redist\MSVC') -Recurse -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -like 'Microsoft.VC*.CRT' -and $_.FullName -match '\\x64\\' -and $_.FullName -notmatch '\\onecore\\' } |
                      Select-Object -First 1
            return @{ LibExe = $lib; Redist = $(if ($redist) { $redist.FullName } else { $null }) }
        }
    }
    throw '找不到 VS 的 lib.exe（构建机需要 VS Build Tools；产物入库，工具不随包）'
}

if ($Check) {
    if (-not (Test-Path $dest)) { Write-Host '❌ vendor\crt 不存在 —— 先跑一次不带 -Check 的' -ForegroundColor Red; exit 1 }
    $tf = Join-Path $dest 'SOURCE.txt'
    if (-not (Test-Path $tf)) { Write-Host '❌ 缺 vendor\crt\SOURCE.txt' -ForegroundColor Red; exit 1 }
    $bad = @(); $n = 0
    foreach ($line in (Get-Content $tf | Where-Object { $_ -match '^[0-9a-f]{64}  ' })) {
        $hash = $line.Substring(0, 64); $rel = $line.Substring(66)
        $f = Join-Path $dest $rel
        $n++
        if (-not (Test-Path -LiteralPath $f)) { $bad += "缺文件：$rel"; continue }
        if ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() -ne $hash) { $bad += "内容变了：$rel" }
    }
    if ($bad.Count) {
        Write-Host '❌ 链接层地基与 SOURCE.txt 不一致（§18.48 批3）：' -ForegroundColor Red
        $bad | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Red }
        exit 1
    }
    if (-not $Quiet) { Write-Host ("链接层地基：通过（{0} 个库，逐文件 SHA256 一致）" -f $n) -ForegroundColor Green }
    exit 0
}

$mw = Find-MingwPaths $MingwRoot
$vs = Find-VsTools
if (-not $CrtDllDir) { $CrtDllDir = $vs.Redist }
if (-not $CrtDllDir -or -not (Test-Path $CrtDllDir)) { throw '找不到 VC 运行库 DLL 目录（-CrtDllDir）' }
$cxx = Join-Path $root 'build\Release\bin\chinese++.exe'
if (-not (Test-Path $cxx)) { throw "找不到我们的编译器：$cxx（先构建）" }

if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory -Force $work | Out-Null
$log = @()

# --- 1) 我们的三个对象 + libcmt.lib / oldnames.lib ---------------------------
$inc = @('-nostdinc', '-D_UCRT')
foreach ($d in @((Join-Path $root 'vendor\compiler-support'), (Join-Path $root 'vendor\msvc-stl'), (Join-Path $root 'vendor\mingw'),
                 (Get-ChildItem (Join-Path $root 'build\Release\lib\clang') -Directory | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'include' } | Select-Object -First 1))) {
    $inc += @('-isystem', $d)
}
$objs = @()
foreach ($f in @('crt0.c', 'newdelete.cpp', 'stl-internals.cpp', 'security-cookie.cpp',
                 'startup-extra.cpp', 'typeinfo.cpp', 'asan-annotate.cpp', 'runtime-extra.cpp')) {
    $o = Join-Path $work ($f -replace '\.[^.]+$', '.obj')
    #  typeinfo.cpp 必须 -fno-rtti：见该文件头部 WHY ③ —— 一旦本模块自己发 RTTI，
    #  clang 会先占掉 `??_7type_info@@6B@` 这个名字，真正的 vftable 被改名为 `.1`。
    $extra = if ($f -eq 'typeinfo.cpp') { @('-fno-rtti') } else { @() }
    & $cxx @(@('-std=c++20', '-c') + $extra + $inc + @((Join-Path $src $f), '-o', $o)) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $o)) { throw "编译 vendor\crt\$f 失败（§18.48 批3）" }
    $objs += $o
    $log += "compile: chinese++.exe -std=c++20 -c$($extra -join '') -nostdinc -D_UCRT ... `"vendor\crt\$f`""
}
& $vs.LibExe /nologo /out:"$dest\libcmt.lib" @objs 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'lib.exe 打 libcmt.lib 失败' }
$log += 'lib: lib.exe /out:vendor\crt\libcmt.lib crt0.obj newdelete.obj stl-internals.obj security-cookie.obj startup-extra.obj typeinfo.obj asan-annotate.obj'
'static int _zh_oldnames_stub; int* _zh_oldnames_ref(void){ return &_zh_oldnames_stub; }' |
    Set-Content -Encoding ASCII (Join-Path $work 'stub.c')
& $cxx @(@('-std=c++20', '-c') + $inc + @((Join-Path $work 'stub.c'), '-o', (Join-Path $work 'stub.obj'))) 2>&1 | Out-Null
& $vs.LibExe /nologo /out:"$dest\oldnames.lib" (Join-Path $work 'stub.obj') 2>&1 | Out-Null
$log += 'lib: lib.exe /out:vendor\crt\oldnames.lib stub.obj  (placeholder: clang always adds -defaultlib:oldnames)'

# --- 2) 从我们随包的 DLL 生成导入库（msvcp140 / vcruntime140 / vcruntime140_1）---
foreach ($n in @('msvcp140', 'vcruntime140', 'vcruntime140_1')) {
    $dll = Join-Path $CrtDllDir "$n.dll"
    if (-not (Test-Path $dll)) { throw "缺 $dll（VC 运行库 DLL，应由 -CrtDllDir 指向）" }
    Push-Location $work
    try {
        & $mw.GenDef $dll 2>&1 | Out-Null
        $def = Join-Path $work "$n.def"
        if (-not (Test-Path $def)) { throw "gendef 没有产出 $n.def" }
        if (-not (Select-String -Path $def -Pattern '\bDATA\b' -Quiet)) {
            Write-Host ("  [warn] {0}.def 里没有 DATA 行 —— 数据导出可能不完整" -f $n) -ForegroundColor Yellow
        }
        & $vs.LibExe /nologo /machine:x64 "/def:$def" "/out:$dest\$n.lib" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "lib.exe /def 生成 $n.lib 失败" }
        $log += "gendef `"<VC Redist>\$n.dll`" ; lib.exe /def:$n.def /out:vendor\crt\$n.lib"
    } finally { Pop-Location }
}

# --- 3) 系统层导入库：抄 mingw 的（public domain）-----------------------------
$sysLibs = @{
    'ucrt' = 'libucrt.a'; 'ucrtbase' = 'libucrtbase.a'; 'kernel32' = 'libkernel32.a';
    'user32' = 'libuser32.a'; 'gdi32' = 'libgdi32.a'; 'comctl32' = 'libcomctl32.a';
    'ole32' = 'libole32.a'; 'oleaut32' = 'liboleaut32.a'; 'shell32' = 'libshell32.a';
    'advapi32' = 'libadvapi32.a'; 'uuid' = 'libuuid.a';
    # mingwex：mingw-w64 自己补的 CRT 实现（strnlen/wcsnlen/__security_cookie 一族的部分符号）。
    # MEASURED：--coverage 链 clang_rt.profile 时它提供 strnlen；/GS 的 cookie 由我们的 security-cookie.cpp 提供。
    'mingwex' = 'libmingwex.a';
}
foreach ($k in $sysLibs.Keys) {
    $s = Join-Path $mw.Lib $sysLibs[$k]
    if (-not (Test-Path $s)) { throw "mingw 里缺 $($sysLibs[$k])" }
    Copy-Item $s (Join-Path $dest "$k.lib") -Force
    $log += "copy: mingw x86_64-w64-mingw32\lib\$($sysLibs[$k]) -> vendor\crt\$k.lib  (public domain)"
}

#  --- 3b) mingw32.lib：只从 libmingw32.a 里取**那一个**成员 ---------------------
#  WHY: MEASURED —— libmingwex.a 的 sqrt.o 引用 __mingw_raise_matherr，而它的**定义**
#  在 libmingw32.a 的 usermatherr.o 里（`nm --defined-only` 实测；libmingwex.a 只有
#  mingw_matherr.o，那个定义的是 _MINGW_INSTALL_DEBUG_MATHERR，不是它）。
#  ⚠ 千万**不要**把整个 libmingw32.a 当库发出去再交给链接器：它里面还有 mingw 自己的
#  启动/初始化对象，实测那样会让一个普通程序在**静态初始化阶段**就 0xC0000005 崩掉
#  （同一个 smoke 程序：整包 0xC0000005，只取这一个成员则正常）。
#  所以这里只解出 usermatherr.o，重新打成 1 KB 的 mingw32.lib。
$mwAr = Join-Path (Split-Path $mw.Root -Parent) 'bin\ar.exe'
if (-not (Test-Path $mwAr)) { $mwAr = Join-Path $mw.Root 'bin\ar.exe' }
if (-not (Test-Path $mwAr)) { throw '找不到 mingw 的 ar.exe（解 libmingw32.a 的成员要用）' }
$extract = Join-Path $work 'matherr'
New-Item -ItemType Directory -Force $extract | Out-Null
Push-Location $extract
try {
    & $mwAr x (Join-Path $mw.Lib 'libmingw32.a') 'lib64_libmingw32_a-usermatherr.o' 2>&1 | Out-Null
} finally { Pop-Location }
$uobj = Join-Path $extract 'lib64_libmingw32_a-usermatherr.o'
if (-not (Test-Path $uobj)) { throw 'libmingw32.a 里没有 lib64_libmingw32_a-usermatherr.o' }
Rename-Item $uobj (Join-Path $extract 'usermatherr.obj') -Force
& $vs.LibExe /nologo "/out:$dest\mingw32.lib" (Join-Path $extract 'usermatherr.obj') 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'lib.exe 打 mingw32.lib 失败' }
$log += 'ar x libmingw32.a lib64_libmingw32_a-usermatherr.o ; lib.exe /out:vendor\crt\mingw32.lib usermatherr.obj  (one member only -- see the note in tools\vendor_crt.ps1)'

# --- 4) SOURCE.txt（逐文件 SHA256 + 生成命令）--------------------------------
$rows = @()
foreach ($f in (Get-ChildItem $dest -File | Where-Object { $_.Name -ne 'SOURCE.txt' } | Sort-Object Name)) {
    $rows += ("{0}  {1}" -f (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower(), $f.Name)
}
$header = @(
    "# 链接层地基（§18.48 批3）—— 我们自己的 CRT + 导入库",
    "#",
    "# 合规口径：Windows SDK 与 MSVC CRT 的**二进制**不许随包。这里发的是：",
    "#   (a) 我们自己写的启动对象与运行时胶水（vendor\crt\*.c/*.cpp，源码同目录）；",
    "#   (b) 从**我们随包的 DLL**（msvcp140/vcruntime140/vcruntime140_1）导出表生成的导入库；",
    "#   (c) mingw-w64 的导入库（public domain）。",
    "#   导入库 = 【DLL 导出名 + 跳转桩】（事实性接口信息）。",
    "#",
    "# 生成命令（构建机：我们的编译器 + mingw 的 gendef + VS 的 lib.exe）：",
    ($log | ForEach-Object { "#   " + $_ }),
    "#",
    "# 下面每行：<SHA256>  <文件名>   （-Check 逐个核对）",
    ""
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $dest 'SOURCE.txt'), $header + ($rows -join "`n") + "`n", $utf8)

$sz = [math]::Round((((Get-ChildItem $dest -File) | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host ("✅ 链接层地基：{0} 个库 / {1} MB → {2}" -f (($rows).Count), $sz, $dest) -ForegroundColor Green
