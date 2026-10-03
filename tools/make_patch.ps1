# ============================================================================
#  Generate patches\zh-keywords.patch and patches\zh-diagnostics.patch from
#  "our tree" vs the clean reference tree.
#
#  WHY A TEMP GIT REPO
#    Our LLVM tree is not a git checkout, so there is no git diff to take.
#    We find the differing files ourselves, recreate them in a throwaway git
#    repo (clean version committed first, then overwritten with ours), and let
#    git produce a patch whose headers are the standard a/clang/... b/clang/...
#    -- so it applies to any clean LLVM source tree with git apply.
#
#  WHY THE SCAN COVERS clang\ *AND* llvm\
#    MSVC reads a source file using the active code page unless /utf-8 is set.
#    That global /utf-8 lives in llvm\CMakeLists.txt. Scanning only clang\
#    therefore shipped an INCOMPLETE patch: applied to a clean tree on MSVC,
#    the Chinese tables would be read as GBK and fail SILENTLY.
#
#  WHY TWO PATCHES
#    Keywords and diagnostics are independent features with independent risk.
#    Both need the same one-line /utf-8 prerequisite, which lives in
#    llvm\CMakeLists.txt and therefore belongs to the keywords patch.
#
#    ⚠ 2026-10-03 起这条独立性是【单向】的，别再当成双向的（§18.4 P-05）：
#      为"中文关键字不能当标识符"新增了一条诊断 `err_chinese_keyword_as_identifier`，
#      它的 **ID 定义**（clang/include/clang/Basic/DiagnosticParseKinds.td）跟着
#      **解析器代码**走 => 关键字补丁；它的**中文正文**只能放在
#      `ChineseDiagnostics.def`（那是诊断汉化的唯一挂表处）=> 诊断补丁。
#      所以：
#        · 只打 keywords 补丁  => 能编（新诊断的正文回退英文）✓
#        · 只打 diagnostics 补丁 => **编不过**（ChineseDiagnostics.def 引用了
#          关键字补丁里才有的 diag:: 名字）✗ —— 这是刻意的取舍，不是疏忽：
#          让新消息跟着"关键字"这个特性走，比把解析器改动塞进诊断补丁更合理。
#      这条没有机器守卫（只是脚本注释），改补丁切分时请回头读这一段。
#
#  WHY cmd REDIRECTION FOR git diff
#    The patch contains Chinese comments. Piping through PowerShell rewrites
#    them; cmd redirection keeps the bytes exactly as git wrote them.
#
#  WHY THE REVERSE CHECK, AND WHY -SelfTest EXISTS  (do not remove either)
#    Step 4 applies the patch back onto the clean files and compares SHA256.
#    That is the only evidence the patch is trustworthy and complete.
#
#    The verification is PER-FILE, not "the two trees are identical". Only files
#    that exist in OUR tree are ever considered, so a file that exists only in
#    the reference tree can never appear in a patch and is not our business.
#    Known case: E:\LLVM-main\clang\lib\Parse\.idea\ holds three IDE leftovers
#    (editor.xml etc.) that our tree does not have -- reported by an independent
#    reviewer; it does not make the patches wrong, it just means "tree-level
#    equality" would be the wrong thing to claim. (2026-09-22)
#
#    This script USED TO BE A RUBBER STAMP: New-Patch printed its progress with
#    Write-Output AND returned a boolean, so `if (-not (New-Patch ...))` captured
#    the whole output stream -- the evidence was swallowed, and the captured
#    value was a non-empty array (always truthy), making `$ok = $false`
#    unreachable. A deliberately broken patch still reported "all patches
#    verified" and exited 0.
#      - An independent reviewer found this on 2026-09-22 by injecting a forced
#        failure and observing exit code 0.
#      - The project had ALREADY hit this exact class of bug once before
#        (Invoke-Step + Write-Output in rebuild_clang.ps1). It is a trap, not an
#        accident: in PowerShell, progress output MUST go to Write-Host, and the
#        return value MUST be captured into a variable before it is tested.
#
#    Therefore:
#      1. every progress line inside New-Patch uses Write-Host;
#      2. callers do `$r = New-Patch ...; if (-not $r) { $ok = $false }`;
#      3. -SelfTest proves the gate CAN fail (see below), and is wired into
#         tests\checks\verify_make_patch_gate.ps1 so run_all.ps1 covers it.
#
#  ENCODING: THIS FILE IS INTENTIONALLY PURE ASCII (see the project's own
#    rebuild_clang.ps1 header for why: PowerShell 5.1 reads a BOM-less file as
#    GBK, and script editors keep dropping the BOM).
#
#  USAGE:
#      powershell -File E:\Chinese++\tools\make_patch.ps1
#      powershell -File E:\Chinese++\tools\make_patch.ps1 -Which diagnostics
#      powershell -File E:\Chinese++\tools\make_patch.ps1 -SelfTest
# ============================================================================

param(
    [ValidateSet('all', 'keywords', 'diagnostics')]
    [string]$Which = 'all',
    # Gate self-test. Proves that a broken patch is actually reported.
    # Never use this to produce a real patch.
    [switch]$SelfTest
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Root = 'E:\Chinese++'
$Base = 'E:\LLVM-main'                  # clean reference tree (read-only)
$Mine = Join-Path $Root 'LLVM-main'     # our tree
$Work = Join-Path $Root 'build\_patchgen'

# Directories scanned for real differences (SHA256).
#
# THIS LIST HAS BEEN INCOMPLETE TWICE, both times shipping a patch that looked
# "verified" while silently losing a fix:
#   1. llvm\CMakeLists.txt   (the global MSVC /utf-8) was missing when only
#      clang\ was scanned -> Chinese tables would be read as GBK, silently.
#   2. clang-tools-extra\clangd\SourceCode.cpp (the clangd keyword fix) was
#      missing while only clang\ + llvm\ were scanned -> anyone rebuilding from
#      the patch would silently lose Chinese keyword support in clangd.
# Both were found by independent reviewers, not by the script.
# Therefore Assert-ScanCoverage below sweeps EVERY top-level directory on every
# run and refuses to continue if something outside this list differs.
$ScanDirs = @('clang', 'llvm', 'clang-tools-extra')

# Files owned by the diagnostics patch; everything else is the keywords patch.
# NOTE: this is an explicit list, so a NEW diagnostics file lands in the
# keywords patch unless it is added here. DiagnosticRenderer.cpp was added
# 2026-09-24: it carries five hand-built message strings that have no
# diagnostic ID to key a table entry on (see the comments there).
$DiagFiles = @(
    'clang/include/clang/Basic/ChineseDiagnostics.def',
    'clang/include/clang/Basic/DiagnosticOptions.def',
    # 2026-10-03（§18.5 P-02）加的：列号口径那个枚举（ColumnUnitKind）声明在这里，
    # 它与 DiagnosticOptions.def / Options.td / TextDiagnostic.cpp 是同一件事，
    # 漏了它就会把"诊断的开关注解"切到关键字补丁里去。
    'clang/include/clang/Basic/DiagnosticOptions.h',
    # 2026-10-04（§18.8 P-09）加：诊断里"内建类型名/限定符/表达式运算符用中文"
    # 这一整件事。它们都引用 `DiagnosticOptions::ChineseDiagnostics`
    # （在 DiagnosticOptions.def 里，属诊断补丁）⇒ 必须一起归诊断补丁，
    # 否则**只打关键字补丁会编不过**，D-06 记的"单向依赖"就被破坏了。
    # 注意：这些文件里用的是 `tok::getKeywordSpelling()` —— 它的**声明**上游就有，
    # 所以只打诊断补丁也能编（那时它回退英文拼写，中文表不在场）。
    'clang/include/clang/AST/PrettyPrinter.h',
    'clang/include/clang/Sema/Sema.h',
    'clang/lib/AST/Type.cpp',
    'clang/lib/AST/TypePrinter.cpp',
    'clang/lib/AST/StmtPrinter.cpp',
    'clang/lib/AST/ASTDiagnostic.cpp',
    'clang/include/clang/Options/Options.td',
    'clang/lib/Basic/Diagnostic.cpp',
    'clang/lib/Driver/ToolChains/Clang.cpp',
    'clang/lib/Frontend/DiagnosticRenderer.cpp',
    'clang/lib/Frontend/TextDiagnostic.cpp',
    'clang/lib/Frontend/CompilerInstance.cpp'
)

# Set by -SelfTest only: truncate the patch so reverse verification must fail.
$script:Sabotage = $false

# ---------------------------------------------------------------------------
# 0) sanity: the two trees must have the same top-level layout, otherwise the
#    scan would silently treat a whole project as "new".
# ---------------------------------------------------------------------------
function Assert-Layout {
    Write-Host "=== 0) layout check ==="
    $bd = Get-ChildItem $Base -Directory | Select-Object -ExpandProperty Name
    $md = Get-ChildItem $Mine -Directory | Select-Object -ExpandProperty Name
    $mineOnly = $md | Where-Object { $bd -notcontains $_ }
    if ($mineOnly) {
        Write-Host "!! top-level directories only in our tree: $($mineOnly -join ', ')"
        Write-Host "!! add them to `$ScanDirs or the patch will be incomplete."
        return $false
    }
    Write-Host "    ok: both trees have $($md.Count) top-level directories"
    Write-Host "    scanning: $($ScanDirs -join ', ')"
    return $true
}

# ---------------------------------------------------------------------------
# 0b) coverage sweep: make sure $ScanDirs really covers everything that differs
#
#    Cheap (metadata only: file count + total bytes per top-level directory),
#    but it closes the failure class that shipped twice: a fix living outside
#    the scanned directories never reaches the patch, while the script still
#    reports "all patches verified".
#
#    Residual, documented limitation: a change that keeps BOTH the file count
#    and the total byte size of a directory unchanged would slip past this
#    sweep. That is a narrow window, and it is why the list above is explicit.
# ---------------------------------------------------------------------------
function Assert-ScanCoverage {
    Write-Host "=== 0b) coverage sweep (every top-level directory) ==="
    $bd = Get-ChildItem $Base -Directory | Select-Object -ExpandProperty Name
    $outside = @()
    foreach ($d in ($bd | Sort-Object)) {
        $b = Get-ChildItem (Join-Path $Base $d) -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum
        $m = Get-ChildItem (Join-Path $Mine $d) -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum
        $bc = [int]$b.Count; $mc = [int]$m.Count
        $bs = [long]$b.Sum;  $ms = [long]$m.Sum
        if (($bc -ne $mc) -or ($bs -ne $ms)) {
            $tag = 'SCANNED'
            if ($ScanDirs -notcontains $d) { $tag = 'NOT SCANNED  <<<<'; $outside += $d }
            # No composite formatting here: {1,>8} is not a valid .NET format.
            Write-Host ("    {0,-20} files {1}/{2}  bytes {3}/{4}  differs  {5}" -f `
                $d, $bc, $mc, $bs, $ms, $tag)
        }
    }
    if ($outside.Count -gt 0) {
        Write-Host "!! these top-level directories differ but are NOT in `$ScanDirs:"
        Write-Host "!!   $($outside -join ', ')"
        Write-Host "!! the patch would be INCOMPLETE -- add them to `$ScanDirs and rerun"
        return $false
    }
    Write-Host "    ok: every differing top-level directory is covered by `$ScanDirs"
    return $true
}

# ---------------------------------------------------------------------------
# 1) find differing files
# ---------------------------------------------------------------------------
function Find-Changed {
    Write-Host "=== 1) find differing files ==="
    $changed = New-Object System.Collections.ArrayList
    foreach ($d in $ScanDirs) {
        $scanRoot = Join-Path $Mine $d
        if (-not (Test-Path $scanRoot)) { continue }
        Get-ChildItem $scanRoot -Recurse -File | ForEach-Object {
            # Normalise to forward slashes: FullName gives backslashes on
            # Windows, while every path in $DiagFiles / $utf8File uses forward
            # slashes. Comparing the two forms silently matched NOTHING.
            $rel = ($_.FullName.Substring($Mine.Length + 1)) -replace '\\', '/'
            $b = Join-Path $Base $rel
            if (-not [System.IO.File]::Exists($b)) { [void]$changed.Add($rel); return }
            if ($_.Length -ne (Get-Item $b).Length) { [void]$changed.Add($rel); return }
            if ((Get-FileHash $_.FullName -Algorithm SHA256).Hash -ne
                (Get-FileHash $b -Algorithm SHA256).Hash) {
                [void]$changed.Add($rel)
            }
        }
    }
    return @($changed | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# 2..4) build one patch, then verify it by applying it back
#
#  IMPORTANT: all progress goes to Write-Host. The ONLY thing this function
#  returns is the boolean verdict -- see the header for what happened when that
#  rule was broken.
# ---------------------------------------------------------------------------
function New-Patch {
    param(
        [string]$Name,
        [string[]]$Files,
        [string]$OutDir = (Join-Path $Root 'patches')
    )

    Write-Host ""
    Write-Host "=== $Name ==="
    if ($Files.Count -eq 0) { Write-Host "    no files, skipped"; return $true }

    $patch  = Join-Path $OutDir $Name
    $repo   = Join-Path $Work ($Name + '.repo')
    $verify = Join-Path $Work ($Name + '.verify')

    Remove-Item $repo   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $verify -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $repo   | Out-Null
    New-Item -ItemType Directory -Force $OutDir | Out-Null

    foreach ($rel in $Files) {
        $b = Join-Path $Base $rel
        if ([System.IO.File]::Exists($b)) {
            $dst = Join-Path $repo $rel
            New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
            Copy-Item $b $dst -Force
        }
    }
    # Every native command below is piped to Out-Null ON PURPOSE.
    # A native command's stdout goes to THIS FUNCTION'S OUTPUT STREAM, so a
    # single stray line (e.g. git's "nothing to commit" hint) turns the returned
    # verdict into a non-empty array -- and a non-empty array is always truthy.
    # That is precisely how this gate reported success on a broken patch.
    & git -c core.autocrlf=false -C $repo init -q 2>&1 | Out-Null
    & git -c core.autocrlf=false -C $repo -c user.email=patch@local -c user.name=patch add -A 2>&1 | Out-Null
    & git -c core.autocrlf=false -C $repo -c user.email=patch@local -c user.name=patch commit -q -m 'base: clean tree' 2>&1 | Out-Null

    foreach ($rel in $Files) {
        $m   = Join-Path $Mine $rel
        $dst = Join-Path $repo $rel
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item $m $dst -Force
    }
    # New files (ChineseKeywords.def, ChineseDiagnostics.def) are untracked, so
    # git diff would not see them; -N (intent-to-add) makes them show up as
    # "new file" in the patch.
    & git -c core.autocrlf=false -C $repo add -A -N 2>&1 | Out-Null

    if (Test-Path $patch) { Remove-Item $patch -Force }
    $cmdline = 'cd /d "{0}" && git -c core.autocrlf=false diff --no-color > "{1}"' -f $repo, $patch
    & cmd /c $cmdline 2>&1 | Out-Null
    if (-not (Test-Path $patch)) { Write-Host "    !! patch not produced"; return $false }

    if ($script:Sabotage) {
        # -SelfTest only: chop the patch so the reverse check MUST fail.
        $all = [System.IO.File]::ReadAllBytes($patch)
        $keep = [Math]::Max(1, $all.Length - 160)
        [System.IO.File]::WriteAllBytes($patch, $all[0..($keep - 1)])
        Write-Host "    [selftest] patch deliberately truncated to $keep bytes"
    }

    $pf = Get-Item $patch
    Write-Host ("    {0}" -f $pf.FullName)
    Write-Host ("    {0:N1} KB, {1} files" -f ($pf.Length / 1KB), $Files.Count)
    $bytes = [System.IO.File]::ReadAllBytes($patch)
    $cr = 0
    # `$cr++` would push the old value onto the output stream -- use += 1.
    foreach ($x in $bytes) { if ($x -eq 13) { $cr = $cr + 1 } }
    Write-Host ("    CR bytes: $cr  (must be 0, i.e. pure LF)")

    # ---- reverse verification -------------------------------------------
    New-Item -ItemType Directory -Force $verify | Out-Null
    foreach ($rel in $Files) {
        $b = Join-Path $Base $rel
        if ([System.IO.File]::Exists($b)) {
            $dst = Join-Path $verify $rel
            New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
            Copy-Item $b $dst -Force
        }
    }
    $applyLog = Join-Path $Work ($Name + '.apply.log')
    # GIT_CEILING_DIRECTORIES is load-bearing: $verify is a PLAIN directory that
    # git apply is meant to treat as "not a repository". Once E:\Chinese++ itself
    # became a git repo (2026-09-23), git apply started walking UP from $verify,
    # finding that repo, and silently doing nothing (exit code 0, no file
    # touched) -- so the byte comparison below failed even for a GOOD patch.
    # The ceiling stops the upward walk at $Work, restoring the original
    # "outside any repository" behaviour. Proven by an A/B run: with the outer
    # .git present the gate self-test failed; with it renamed away it passed.
    & cmd /c ('cd /d "{0}" && set "GIT_CEILING_DIRECTORIES={3}" && git -c core.autocrlf=false apply --verbose "{1}" > "{2}" 2>&1' -f $verify, $patch, $applyLog, $Work)
    $applyCode = $LASTEXITCODE
    Write-Host "    git apply exit code: $applyCode"
    if ($applyCode -ne 0) {
        Write-Host "    !! the patch does not apply to the clean tree"
        if (Test-Path $applyLog) { Get-Content $applyLog -TotalCount 6 | ForEach-Object { Write-Host "      $_" } }
        return $false
    }
    $bad = 0
    # += 1, not ++: a post-increment emits its old value into the output stream.
    foreach ($rel in $Files) {
        $v = Join-Path $verify $rel
        $m = Join-Path $Mine $rel
        if (-not [System.IO.File]::Exists($v)) { Write-Host "    missing: $rel"; $bad = $bad + 1; continue }
        if ((Get-FileHash $v -Algorithm SHA256).Hash -ne (Get-FileHash $m -Algorithm SHA256).Hash) {
            Write-Host "    content differs: $rel"; $bad = $bad + 1
        }
    }
    if ($bad -ne 0) { Write-Host "    !! $bad file(s) differ"; return $false }
    Write-Host "    OK: clean tree + patch == our tree, all $($Files.Count) files byte-identical"
    return $true
}

# ---------------------------------------------------------------------------
# Gate self-test (fast: one file, no full-tree scan)
#
# A verification gate that cannot fail is worthless, and this one already
# shipped broken once. So: run it on a good patch (must pass) and on a
# sabotaged patch (must fail). If the sabotaged run passes, exit 1.
# ---------------------------------------------------------------------------
if ($SelfTest) {
    # The probe must be a file that EXISTS IN BOTH TREES and differs. A brand-new
    # file (ChineseDiagnostics.def) exists only in our tree, so the base commit
    # would be empty and git would print "nothing to commit" -- which is how the
    # first version of this self-test itself leaked output into the verdict.
    $probe = @('clang/lib/Basic/Diagnostic.cpp')
    Write-Host "=== SELF-TEST ==="
    Write-Host "probe file: $($probe[0])"

    $script:Sabotage = $false
    Write-Host ""
    Write-Host "--- (a) a GOOD patch must PASS ---"
    $good = New-Patch 'selftest-good.patch' $probe $Work
    Write-Host ("    returned: type={0} count={1} value=[{2}]" -f `
        $good.GetType().Name, @($good).Count, (@($good) -join '|'))
    if ($good -eq $true) { Write-Host "    => TRUE (correct)" }
    else                 { Write-Host "    => NOT true (WRONG: good patch rejected)" }

    $script:Sabotage = $true
    Write-Host ""
    Write-Host "--- (b) a SABOTAGED patch must FAIL ---"
    $bad = New-Patch 'selftest-bad.patch' $probe $Work
    Write-Host ("    returned: type={0} count={1} value=[{2}]" -f `
        $bad.GetType().Name, @($bad).Count, (@($bad) -join '|'))
    if ($bad -eq $false) { Write-Host "    => FALSE (correct)" }
    else                 { Write-Host "    => NOT false (WRONG: gate is a rubber stamp)" }

    Remove-Item (Join-Path $Work 'selftest-good.patch') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Work 'selftest-bad.patch')  -Force -ErrorAction SilentlyContinue

    Write-Host ""
    # Compare against the exact singletons $true / $false, NOT with a truthiness
    # test: a leaked output line turns the verdict into a non-empty array, and
    # a non-empty array is ALWAYS truthy in PowerShell -- that is exactly how
    # this gate was a rubber stamp the first time.
    if (($good -eq $true) -and ($bad -eq $false)) {
        Write-Host "SELF-TEST PASSED: the gate accepts a good patch and rejects a broken one"
        exit 0
    }
    Write-Host "SELF-TEST FAILED: the verification gate does not distinguish good from broken"
    exit 1
}

# ---------------------------------------------------------------------------
# normal run
# ---------------------------------------------------------------------------
if (-not (Assert-Layout)) { exit 5 }
if (-not (Assert-ScanCoverage)) { exit 9 }

$changed = Find-Changed
Write-Host "    changed files: $($changed.Count)"
$changed | ForEach-Object { Write-Host "      $_" }
if ($changed.Count -eq 0) { Write-Host "nothing differs, done."; exit 0 }

$diagFiles = @($changed | Where-Object { $DiagFiles -contains $_ })
$keyFiles  = @($changed | Where-Object { $DiagFiles -notcontains $_ })
Write-Host "    -> keywords patch   : $($keyFiles.Count) files"
Write-Host "    -> diagnostics patch: $($diagFiles.Count) files"

# The /utf-8 prerequisite must stay on the keywords side.
$utf8File = 'llvm/CMakeLists.txt'
if ($changed -contains $utf8File) {
    if ($keyFiles -notcontains $utf8File) {
        Write-Host "!! $utf8File must belong to the keywords patch"
        exit 6
    }
    Write-Host "    ok: $utf8File (the /utf-8 prerequisite) is in the keywords patch"
} else {
    Write-Host "!! $utf8File is missing from the diff set -- the /utf-8 change is gone?"
    exit 7
}

$ok = $true
if ($Which -eq 'all' -or $Which -eq 'keywords') {
    # Capture the verdict, then check it is REALLY a boolean.
    # `if (-not (New-Patch ...))` was the original bug: it fed the function's
    # whole output stream into the condition, so the evidence was swallowed and
    # the truthy array made the failure branch unreachable.
    $r = New-Patch 'zh-keywords.patch' $keyFiles
    if ($r -isnot [bool]) {
        Write-Host "!! New-Patch leaked output into its verdict: [$(@($r) -join '|')]"
        exit 8
    }
    if (-not $r) { $ok = $false }
}
if ($Which -eq 'all' -or $Which -eq 'diagnostics') {
    $r = New-Patch 'zh-diagnostics.patch' $diagFiles
    if ($r -isnot [bool]) {
        Write-Host "!! New-Patch leaked output into its verdict: [$(@($r) -join '|')]"
        exit 8
    }
    if (-not $r) { $ok = $false }
}

Write-Host ""
if ($ok) { Write-Host "all patches verified"; exit 0 }
Write-Host "!! something failed"; exit 1
