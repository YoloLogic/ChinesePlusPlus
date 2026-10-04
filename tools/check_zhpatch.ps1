# ============================================================================
#  补丁与源码树一致性守卫（第 23 道）—— §18.11
#  （大检查台账里"待定：这次顺带发现的一条'没有护栏'的事"）
#
#  背景（台账原话）：
#    改了**编译器源码**却忘记重跑 `tools\make_patch.ps1` ⇒ 补丁与源码树不一致，
#    而**没有任何守卫会发现**（`regen_zhstdlib.ps1` 里 `patch` / `补丁` /
#    `make_patch` 三个词一次都不出现）。P-01 那次靠"人记得"跑了。
#    ⇒ 建议把"补丁必须能重放成当前源码树"做成闸门项。
#
#  判据（两条）：
#    ① **不落后**：重新生成一遍补丁（`make_patch.ps1 -Check`：生成到 scratch，
#       **不动** `patches\`），再与仓库里那份**逐字节**比 —— 不一致就红。
#       不一致的含义只有一个：**改了编译器源码而 patches\ 里那份是旧的**。
#    ② **自测**：逐字节比较这个判据必须**能失败** —— 改坏一个字节必须报不同，
#       自己和自己比必须报相同。
#
#  为什么这么便宜：`make_patch.ps1` 末尾那段"把补丁打回干净树、必须等于我们的树"
#  本来就是现成的判据（台账原话），只差接进闸门。
#
#  跑法：pwsh -NoProfile -File tools\check_zhpatch.ps1
#  退出码：0 = 补丁与源码树一致；1 = 有失败
# ============================================================================

$ErrorActionPreference = 'Continue'
$Root = 'E:\Chinese++'
$真 = Join-Path $Root 'patches'
$新 = Join-Path $Root 'build\_zhpatch'
New-Item -ItemType Directory -Force $新 | Out-Null

$script:fail = 0
function 过($t) { Write-Host ("  [通过] $t") -ForegroundColor Green }
function 错($t) { Write-Host ("  [失败] $t") -ForegroundColor Red; $script:fail++ }

function 文件相同([string]$x, [string]$y) {
    if (-not (Test-Path $x) -or -not (Test-Path $y)) { return $false }
    return ((Get-FileHash $x -Algorithm SHA256).Hash -eq (Get-FileHash $y -Algorithm SHA256).Hash)
}

# ---------------------------------------------------------------------------
#  ① 重新生成（到 scratch）+ 重放校验，再逐字节比
# ---------------------------------------------------------------------------
$log = Join-Path $新 'make_patch_check.log'
& pwsh -NoProfile -File (Join-Path $Root 'tools\make_patch.ps1') -Check *> $log
$rc = $LASTEXITCODE
if ($rc -ne 0) {
    错 ("重新生成补丁失败（make_patch.ps1 -Check 退出码 {0}）—— 要么源码树本身有问题，要么'补丁打回干净树 != 我们的树'；日志尾：" -f $rc)
    Get-Content $log -Tail 12 | ForEach-Object { Write-Host ("         " + $_) -ForegroundColor DarkRed }
}

foreach ($n in @('zh-keywords.patch', 'zh-diagnostics.patch')) {
    $老 = Join-Path $真 $n
    $生成 = Join-Path $新 $n
    if (-not (Test-Path $老)) { 错 ("patches\{0} 不存在（补丁没生成过？）" -f $n); continue }
    if (-not (Test-Path $生成)) { 错 ("{0}：-Check 没生成出这一份（上一条应该已经报错）" -f $n); continue }
    $尺寸 = (Get-Item $生成).Length
    if (文件相同 $老 $生成) {
        过 ("{0}：与重新生成的**逐字节一致**（{1:N0} 字节 —— 补丁没有落后于源码树）" -f $n, $尺寸)
    } else {
        错 ("{0}：与重新生成的不一致 —— **改了编译器源码之后忘了重跑 tools\make_patch.ps1**（或 patches\ 里那份是旧的，会误导打补丁的人）" -f $n)
    }
}

# ---------------------------------------------------------------------------
#  ② §18.12 补的：**keywords 补丁必须能单独编**（D-06 记的"单向依赖"）
#
#  为什么补这一条：`$DiagFiles` 是一张**手写清单**（make_patch.ps1 里写明「没进这张
#  清单的新文件会落到 keywords 补丁里去」）。P-14 就踩了：DeclPrinter.cpp 引用了
#  诊断补丁才引入的 `PrintingPolicy::ChineseSpelling`，却因为没进清单而落进了
#  keywords 补丁 ⇒ **只打 keywords 会编不过**。而"补丁 == 源码树"那条判据
#  **看不见**这件事（两边一致，只是切错了）。
#
#  判据：keywords 补丁里**不许出现**诊断侧新增的符号（那几样只在诊断补丁里定义）。
#  这是**静态**判据（比"真去编一遍"便宜得多，一次全量 clang 构建 30 分钟起）；
#  它挡不住"诊断补丁里定义的其它东西"，但挡住了"新增文件忘了归诊断补丁"这个
#  实际会发生的错法。**真正的编译验证目前没有自动化**（太贵）—— 这一条登记在案，
#  升级路径就是"把 keywords 补丁打到干净树上、只编 clang"。
# ---------------------------------------------------------------------------
$诊断侧符号 = @(
    'ChineseSpelling',                  # PrintingPolicy 的字段（诊断补丁的 PrettyPrinter.h）
    'ChineseDiagnostics.def',           # 中文诊断表
    'ChineseDiagnostics',               # DiagnosticOptions 的开关
    'getColumnUnit', 'ColumnUnitKind'   # §18.5 P-02 加的列号口径
)
$kwPatch = Join-Path $新 'zh-keywords.patch'

# 判据写成函数：真扫一遍 + 自测（合成内容）—— 判据必须**能失败**
function 提到诊断侧符号([string]$文) {
    $命中 = @()
    foreach ($符号 in $诊断侧符号) { if ($文.Contains($符号)) { $命中 += $符号 } }
    return $命中
}

if (Test-Path $kwPatch) {
    # 从补丁里取文件清单（`+++ b/<路径>`）
    $kwFiles = @()
    foreach ($l in [System.IO.File]::ReadAllLines($kwPatch)) {
        $m = [regex]::Match($l, '^\+\+\+ b/(.+)$')
        if ($m.Success) { $kwFiles += $m.Groups[1].Value.Trim() }
    }
    $越界 = @()
    foreach ($rel in $kwFiles) {
        $路径 = Join-Path $Root ('llvm-main\' + ($rel -replace '/', '\'))
        if (-not (Test-Path $路径)) { continue }
        # ⚠ 只看**非注释**行：注释里提一句"另一张表在哪个文件"不会让编译失败
        #   （ChineseKeywords.def 的注释就提到了 ChineseDiagnostics.def —— 误报过一次）
        $文 = ((@([System.IO.File]::ReadAllLines($路径)) |
                Where-Object { -not $_.TrimStart().StartsWith('//') }) -join "`n")
        foreach ($符号 in @(提到诊断侧符号 $文)) {
            $越界 += ("{0} 提到 [{1}]" -f $rel, $符号)
        }
    }
    if ($kwFiles.Count -eq 0) {
        错 "keywords 补丁里一个文件都没解析出来（判据没打中）"
    } elseif ($越界.Count -eq 0) {
        过 ("keywords 补丁可以**单独编**：{0} 个文件都没有提到诊断侧符号（{1}）" -f $kwFiles.Count, ($诊断侧符号 -join '、'))
    } else {
        错 ("keywords 补丁**会编不过**（D-06 的单向依赖被破坏）—— 这些文件该归 `$DiagFiles`：" + ($越界 -join '；'))    }
}

# ---------------------------------------------------------------------------
#  ③ 自测：上面两条判据都必须**能失败**
#     （逐字节比较：改坏一个字节必须报不同；keywords 越界检查：造一行提到
#      诊断侧符号的内容必须被抓到）
# ---------------------------------------------------------------------------
$样 = Join-Path $真 'zh-keywords.patch'
if (Test-Path $样) {
    $坏 = Join-Path $新 'selftest_mutated.patch'
    $b = [System.IO.File]::ReadAllBytes($样)
    $b[[int]($b.Length / 2)] = $b[[int]($b.Length / 2)] -bxor 0xFF
    [System.IO.File]::WriteAllBytes($坏, $b)
    if (文件相同 $样 $坏) {
        错 "自测失败：改坏一个字节竟然还算'一致' —— 这个判据是橡皮图章"
    } elseif (-not (文件相同 $样 $样)) {
        错 "自测失败：文件与它自己比竟然不算'一致'"
    } else {
        过 "自测：逐字节比较能区分（改坏一个字节 → 不同；自己和自己比 → 相同）"
    }
    Remove-Item $坏 -Force -ErrorAction SilentlyContinue
} else {
    错 "自测没法跑：patches\zh-keywords.patch 不存在"
}

$自测越界有 = @(提到诊断侧符号 '  Policy.ChineseSpelling = Context.getPrintingPolicy().ChineseSpelling;')
$自测越界无 = @(提到诊断侧符号 '  Policy.Alignof = true;')
if ($自测越界有.Count -eq 1 -and $自测越界有[0] -eq 'ChineseSpelling' -and $自测越界无.Count -eq 0) {
    过 "自测：keywords 越界检查能失败（提到 ChineseSpelling 会被抓到，普通策略设置不误报）"
} else {
    错 ("自测失败：越界检查该抓 {0} 个（期望 1 个 ChineseSpelling）、普通内容误报 {1} 个（期望 0）" -f $自测越界有.Count, $自测越界无.Count)
}

Write-Host ''
if ($script:fail -eq 0) { Write-Host '  => PASS' -ForegroundColor Green; exit 0 }
Write-Host ("  => FAIL（{0} 条）" -f $script:fail) -ForegroundColor Red
exit 1
