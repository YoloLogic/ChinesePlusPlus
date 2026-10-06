# ============================================================================
#  vendor_mingw.ps1 -- 把 mingw-w64 的【自由许可】头搬进我们的仓库（§18.48 批2）
#
#  为什么能抄：mingw-w64 的头是 **public domain**（每个文件头部写明
#  "This file has no copyright assigned and is placed in the Public Domain"），
#  所以可以随包发（保留声明即可）。我们用它替代**不许再发行**的 Windows SDK 头
#  （UCRT + Win32），以及给 MSVC STL 提供它需要的 corecrt.h / sal.h / crtdefs.h。
#
#  【实测边界，2026-10-06】mingw 头**不能**整目录照搬：
#    · clang 资源目录里也有的名字（immintrin.h / iso646.h / yvals_core.h …）
#      **绝不能搬** —— 我们放 -isystem 比 clang 的 -internal-isystem 靠前，会 shadow 掉
#      clang 自己那份（批1 实测：immintrin.h 抢在前面时整个 <vector> 编不过）；
#    · `vcruntime*.h` mingw **没有** ⇒ 由 `vendor\compiler-support\` 手搓件提供（§18.48 批2）；
#    · mingw 的 `sal.h`/`concurrencysal.h`/`crtdefs.h`/`_mingw*.h`/`corecrt*.h` **要搬**：
#      它们是 public domain，而且正是 mingw 的 UCRT/Win32 头与 MSVC STL 共同需要的桥梁。
#
#  用法：
#    pwsh -NoProfile -File tools\vendor_mingw.ps1 [-From <mingw 的 x86_64-w64-mingw32\include>]
#    pwsh -NoProfile -File tools\vendor_mingw.ps1 -Check
# ============================================================================
param(
    [string] $From,
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$dest = Join-Path $root 'vendor\mingw'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Find-MingwInclude {
    param([string] $Hint)
    if ($Hint) {
        if (-not (Test-Path $Hint)) { throw "没有这个目录：$Hint" }
        return (Resolve-Path $Hint).Path
    }
    $cands = @(
        'E:\c++\mingw64\x86_64-w64-mingw32\include',
        'C:\msys64\mingw64\x86_64-w64-mingw32\include',
        'C:\mingw64\x86_64-w64-mingw32\include',
        'E:\CLion 2026.1.2\bin\mingw\x86_64-w64-mingw32\include',
        'C:\Program Files\Git\mingw64\x86_64-w64-mingw32\include'
    )
    foreach ($c in $cands) { if (Test-Path (Join-Path $c 'windows.h')) { return (Resolve-Path $c).Path } }
    throw '找不到 mingw-w64 的 x86_64-w64-mingw32\include —— 用 -From 显式指定'
}

function Find-ClangResourceInc {
    $base = Join-Path $root 'build\Release\lib\clang'
    if (-not (Test-Path $base)) { throw '找不到 build\Release\lib\clang —— 无法判定"绝不能 shadow"的那批名字' }
    $hit = Get-ChildItem $base -Directory | Sort-Object Name -Descending |
           ForEach-Object { Join-Path $_.FullName 'include' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $hit) { throw '找不到 clang 资源头目录' }
    return (Resolve-Path $hit).Path
}

if ($Check) {
    if (-not (Test-Path $dest)) { Write-Host '❌ vendor\mingw 不存在 —— 先跑一次不带 -Check 的' -ForegroundColor Red; exit 1 }
    $srcTxt = Join-Path $dest 'SOURCE.txt'
    if (-not (Test-Path $srcTxt)) { Write-Host '❌ 缺 vendor\mingw\SOURCE.txt' -ForegroundColor Red; exit 1 }
    $bad = @(); $n = 0
    foreach ($line in (Get-Content $srcTxt | Where-Object { $_ -match '^[0-9a-f]{64}  ' })) {
        $hash = $line.Substring(0, 64); $rel = $line.Substring(66)
        $f = Join-Path $dest $rel
        $n++
        if (-not (Test-Path -LiteralPath $f)) { $bad += "缺文件：$rel"; continue }
        if ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() -ne $hash) { $bad += "内容变了：$rel" }
    }
    if ($bad.Count) {
        Write-Host '❌ mingw 抄件与 SOURCE.txt 不一致（§18.48）：' -ForegroundColor Red
        $bad | Select-Object -First 10 | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor Red }
        exit 1
    }
    if (-not $Quiet) { Write-Host ("mingw 抄件：通过（{0} 个文件，逐文件 SHA256 一致）" -f $n) -ForegroundColor Green }
    exit 0
}

$src = Find-MingwInclude $From
$clangInc = Find-ClangResourceInc
Write-Host "来源：$src"
Write-Host "clang 资源目录：$clangInc"

#  【精确规则，2026-10-06 批2 实测】clang 资源目录里的同名文件分两种：
#    · **真身**（immintrin.h 等 intrinsic）⇒ 搬进来会 shadow 掉 clang 自己那份，**绝不搬**（批1 踩过）；
#    · **转发壳**（`#include_next <同名>`，如 limits.h / stdint.h / vadefs.h / float.h / iso646.h）
#      ⇒ 壳去"下一个搜索位置"找真身；没装 VS 时那里是空的 ⇒ **必须搬**（这就是"零 VS"的关键）。
#    判据：clang 那份里有没有 `#include_next` —— 机器可查，不靠人记。
function Test-MustNotShadow([string] $name) {
    $p = Join-Path $clangInc $name
    if (-not (Test-Path $p)) { return $false }
    $t = [System.IO.File]::ReadAllText($p)
    if ($t -match '#\s*include_next') { return $false }
    return $true
}

#  手搓件负责的名字（§18.48 批2）：不搬 mingw 的（mingw 大多也没有），
#  但显式列出来，免得将来 mingw 新增同名文件时被悄悄搬进来顶掉我们那份。
$handWritten = @('vcruntime.h','vcruntime_new.h','vcruntime_new_debug.h','vcruntime_typeinfo.h',
                 'vcruntime_string.h','vcruntime_exception.h')

if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null
$rows = @(); $kept = 0; $skippedClang = 0; $skippedHand = 0; $realForWrappers = @()
Get-ChildItem $src -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length + 1)
    $leaf = $_.Name
    if (Test-MustNotShadow $leaf) { $skippedClang++; return }
    if ($handWritten -contains $leaf) { $skippedHand++; return }
    $dst = Join-Path $dest $rel
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item $_.FullName $dst -Force
    $rows += ("{0}  {1}" -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower(), $rel)
    $kept++
    #  记下"我们替 clang 的转发壳补的真身"——零 VS 的关键件
    $cp = Join-Path $clangInc $leaf
    if ((Test-Path $cp) -and ([System.IO.File]::ReadAllText($cp) -match '#\s*include_next')) { $realForWrappers += $leaf }
}
#  ---------------------------------------------------------------------------
#  【唯一的补丁】_mingw_mac.h：让 clang 走 GNU 属性分支（§18.48 批2 实测）
#
#  为什么：我们的目标是 `-windows-msvc`（没有 __GNUC__），于是
#      #if defined (__GNUC__) && defined (__GNUC_MINOR__) ... #else
#      #  define __MINGW_GNUC_PREREQ(major, minor) 0
#  判 0 ⇒ 下游 __MINGW_NOTHROW/__MINGW_ATTRIB_NORETURN 取 **__declspec 分支**，
#  而 mingw 的头把它们用在**声明尾部**（`void __cdecl __MINGW_NOTHROW exit(int) __MINGW_ATTRIB_NORETURN;`），
#  clang 不接受尾置 __declspec ⇒ 实测 mingw 的 stdlib.h:388 报「顶层声明符之后缺少 ';'」，
#  连带 stdio.h / intrin.h / windows.h 全崩。
#  clang 两种位置都认 `__attribute__((...))` ⇒ 让 clang 被当成"满足 GNU 前置条件"即可，
#  **一处**改动解决整族宏。
#  ---------------------------------------------------------------------------
$patchFile = Join-Path $dest '_mingw_mac.h'
if (-not (Test-Path $patchFile)) { throw "vendor\mingw\_mingw_mac.h 不见了（补丁点失效，需重新核对 §18.48）" }
$pat = [System.IO.File]::ReadAllText($patchFile)
$patRe = [regex]'#else\r?\n#\s+define __MINGW_GNUC_PREREQ\(major, minor\) 0\r?\n#endif'
$n = ([regex]::Matches($pat, $patRe)).Count
if ($n -ne 1) { throw "_mingw_mac.h 的补丁点命中 $n 次（期望 1）—— 上游变了，先人工核对再改脚本" }
$patched = [regex]::Replace($pat, $patRe, "#elif defined (__clang__)`n#  define __MINGW_GNUC_PREREQ(major, minor) 1`n#else`n#  define __MINGW_GNUC_PREREQ(major, minor) 0`n#endif")
[System.IO.File]::WriteAllText($patchFile, $patched, (New-Object System.Text.UTF8Encoding($false)))
#  重新登记这一条的哈希（它是"补丁后"的内容，-Check 才对得上）
for ($i = 0; $i -lt $rows.Count; $i++) {
    if ($rows[$i] -match '  _mingw_mac\.h$') {
        $rows[$i] = ("{0}  _mingw_mac.h" -f (Get-FileHash -LiteralPath $patchFile -Algorithm SHA256).Hash.ToLower())
    }
}
Write-Host '  补丁：_mingw_mac.h 让 clang 走 GNU 属性分支（1 处）'

#  第二处补丁（同一原因，另一个判据）：_mingw.h 的属性块用的是 `#ifdef __GNUC__`（不是 PREREQ），
#  所以 clang 在 MSVC 模式下取到 `__declspec(noreturn)`；而 mingw 的头把它放在**声明尾部**
#  （`void __cdecl __MINGW_NOTHROW exit(int) __MINGW_ATTRIB_NORETURN;`）⇒ clang 报
#  「顶层声明符之后缺少 ';'」（stdlib.h:388）。把那一行改成 `#if defined(__GNUC__) || defined(__clang__)`
#  即可；**故意不定义 __GNUC__**（那会波及 MSVC STL 的分支判断）。
$p2File = Join-Path $dest '_mingw.h'
if (-not (Test-Path $p2File)) { throw "vendor\mingw\_mingw.h 不见了（补丁点失效，需重新核对 §18.48）" }
$p2 = [System.IO.File]::ReadAllText($p2File)
$p2Re = [regex]'#ifdef __GNUC__\r?\n#define __MINGW_ATTRIB_NORETURN __attribute__ \(\(__noreturn__\)\)'
if (([regex]::Matches($p2, $p2Re)).Count -ne 1) { throw '_mingw.h 的第二个补丁点命中数不是 1 —— 上游变了，先人工核对' }
$p2 = [regex]::Replace($p2, $p2Re, "#if defined(__GNUC__) || defined(__clang__)`n#define __MINGW_ATTRIB_NORETURN __attribute__ ((__noreturn__))")
[System.IO.File]::WriteAllText($p2File, $p2, (New-Object System.Text.UTF8Encoding($false)))
for ($i = 0; $i -lt $rows.Count; $i++) {
    if ($rows[$i] -match '  _mingw\.h$') {
        $rows[$i] = ("{0}  _mingw.h" -f (Get-FileHash -LiteralPath $p2File -Algorithm SHA256).Hash.ToLower())
    }
}
Write-Host '  补丁：_mingw.h 属性块接受 clang（1 处）'

#  第三处补丁（真凶，本轮实测抓到）：_mingw.h 在"非 __GNUC__"分支里把
#      # define __attribute__(x) /* nothing */
#  定义成**宏**。clang 在 MSVC 模式下没有 __GNUC__ ⇒ 中招：clang 自己的 intrinsic 头
#      typedef long long __m64 __attribute__((__vector_size__(8), __aligned__(8)));
#  被吃成 `typedef long long __m64;`，于是 mmintrin.h 里 `(__m64)(__v2si){…}` 报
#  「到内建类型的函数式转换只能带一个实参」，整份 <vector>/<windows.h> 编不过。
#  clang **完全支持** __attribute__ ⇒ 只对 clang 跳过这一行（同分支的 __declspec/__DECLSPEC_SUPPORTED 保持原样）。
$p3bFile = Join-Path $dest '_mingw.h'
$p3b = [System.IO.File]::ReadAllText($p3bFile)
$p3bRe = [regex]'# define __attribute__\(x\) /\* nothing \*/'
if (([regex]::Matches($p3b, $p3bRe)).Count -ne 1) { throw '_mingw.h 的 __attribute__ 补丁点命中数不是 1 —— 上游变了，先人工核对' }
$p3b = [regex]::Replace($p3b, $p3bRe, "# ifndef __clang__ /* Chinese++ 18.48 patch: clang understands __attribute__ */`n#  define __attribute__(x) /* nothing */`n# endif")
[System.IO.File]::WriteAllText($p3bFile, $p3b, (New-Object System.Text.UTF8Encoding($false)))
for ($i = 0; $i -lt $rows.Count; $i++) {
    if ($rows[$i] -match '  _mingw\.h$') {
        $rows[$i] = ("{0}  _mingw.h" -f (Get-FileHash -LiteralPath $p3bFile -Algorithm SHA256).Hash.ToLower())
    }
}
Write-Host '  补丁：_mingw.h 不再为 clang 禁用 __attribute__（1 处）'

$header = @(
    "# mingw-w64 头（原样搬运 + **一处记录在案的小补丁**）—— §18.48 批2",
    "#",
    "# 来源：$src",
    "# 抄取时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "# 抄取脚本：tools\vendor_mingw.ps1",
    "# 许可：public domain（每个文件头部自带 'no copyright assigned ... Public Domain'；",
    "#       mingw-w64 runtime package。保留原文件即保留声明）",
    "#",
    "# 为什么用它：Windows SDK 的头（UCRT + Win32）**不许再发行**，mingw-w64 这套是自由许可的等价物；",
    "# 同时它提供 MSVC STL 需要的 corecrt.h / sal.h / crtdefs.h / _mingw 簇。",
    "#",
    "# 没搬的（逐条可查）：",
    "#   a) clang 资源目录里也有同名的 $skippedClang 个 —— 搬进来会 shadow 掉 clang 自己那份（批1 实测踩过）；",
    "#   b) 由 vendor\compiler-support\ **手搓**的 $skippedHand 个：$($handWritten -join ' ')；",
    "#   c) 文件总数 $kept 个。",
    "#",
    "# 下面每行：<SHA256>  <相对路径>   （-Check 逐个核对）",
    ""
) -join "`n"
[System.IO.File]::WriteAllText((Join-Path $dest 'SOURCE.txt'), $header + ($rows -join "`n") + "`n", $utf8)

$sz = [math]::Round((((Get-ChildItem $dest -File) | Measure-Object Length -Sum).Sum) / 1MB, 1)
Write-Host ("✅ 搬好：{0} 个文件 / {1} MB → {2}" -f $kept, $sz, $dest) -ForegroundColor Green
Write-Host ("   跳过：clang 同名 {0} 个；手搓件 {1} 个" -f $skippedClang, $skippedHand)
