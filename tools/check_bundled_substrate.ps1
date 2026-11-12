# ============================================================================
#  check_bundled_substrate.ps1 -- bundled 地基的验收判据（可复现、能失败）
#  Chinese++ section 18.50
#
#  两个矩阵：
#    A) zhstdlib 全头矩阵：每个头各写一个最小程序，用包内 bundled cfg 编译
#    B) 链接探针：真用 API 的程序，编译 + 链接 + 运行
#
#  输出：
#    · 控制台：通过/失败计数
#    · <OutDir>\头矩阵.md     逐头结果（可当 0.4 的验收清单）
#    · <OutDir>\缺失符号.txt  链接器吐出的全部 undefined symbol（去重）
#
#  用法：
#    pwsh -NoProfile -File tools\check_bundled_substrate.ps1
#    pwsh -NoProfile -File tools\check_bundled_substrate.ps1 -Pkg <path to package>
# ============================================================================
param(
    [string] $Pkg = 'E:\Chinese++\dist\Chinese++-0.3-win64',
    [string] $OutDir = 'E:\Chinese++\build\_substrate_check',
    [switch] $SkipHeaders
)

$ErrorActionPreference = 'Continue'
$cxx = Join-Path $Pkg 'bin\chinese++.exe'
if (-not (Test-Path $cxx)) { throw "找不到包内编译器：$cxx" }
$zh = Join-Path $Pkg 'zhstdlib'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force $OutDir, (Join-Path $OutDir 'probe') | Out-Null

# ---------------------------------------------------------------------------
#  A) 全头矩阵
# ---------------------------------------------------------------------------
$头结果 = @()
if (-not $SkipHeaders) {
    # 每个 -isystem 目录是 include 根的候选，取最长前缀得到 include 名
    $根们 = @($zh, (Join-Path $zh '标准库'), (Join-Path $zh '别名'),
               (Join-Path $zh 'C运行库'), (Join-Path $zh 'windows系统'))
    $头们 = Get-ChildItem $zh -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.h', '.hpp', '' } |
        Sort-Object FullName

    Write-Host ("A) 头矩阵：" + $头们.Count + " 个文件")
    $i = 0
    foreach ($h in $头们) {
        $i++
        # 求 include 名：找到最长的匹配根
        $名 = $null
        foreach ($r in $根们) {
            if ($h.FullName.StartsWith($r + '\')) {
                $rel = $h.FullName.Substring($r.Length + 1) -replace '\\', '/'
                if ($名 -eq $null -or $rel.Length -lt $名.Length) { $名 = $rel }
            }
        }
        if (-not $名) { continue }

        $probe = Join-Path $OutDir ('probe\h' + $i + '.cpp')
        $源 = "#包含 <" + $名 + ">`r`n整数 主函数() { 返回 0; }`r`n"
        [System.IO.File]::WriteAllText($probe, $源, $utf8)
        $out = & $cxx -std=c++2c -fsyntax-only $probe 2>&1 | Out-String
        $码 = $LASTEXITCODE
        $首错 = (($out -split "`r?`n") | Where-Object { $_ -match 'error:|错误:' } | Select-Object -First 1)
        $头结果 += [pscustomobject]@{
            头 = $名
            通过 = ($码 -eq 0)
            首错 = if ($首错) { ([string]$首错).Trim().Substring(0, [Math]::Min(160, ([string]$首错).Trim().Length)) } else { '' }
        }
        if ($i % 20 -eq 0) { Write-Host ("   ... " + $i + "/" + $头们.Count) }
    }
}

$通过数 = @($头结果 | Where-Object { $_.通过 }).Count
$失败数 = @($头结果 | Where-Object { -not $_.通过 }).Count
Write-Host ("A) 结果：" + $通过数 + " 通过 / " + $失败数 + " 失败")

$md = @('# bundled 地基 · 头矩阵', '', ('生成时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), '',
        ('包：`' + $Pkg + '`' + "`n" + ''), ('**' + $通过数 + ' 通过 / ' + $失败数 + ' 失败**' + "`n" + ''), '| 头 | 结果 | 首错 |', '|---|---|---|')
foreach ($r in ($头结果 | Sort-Object @{Expression='通过';Descending=$false}, 头)) {
    $md += ('| `' + $r.头 + '` | ' + $(if ($r.通过) { '通过' } else { '**失败**' }) + ' | ' + $r.首错 + ' |')
}
[System.IO.File]::WriteAllText((Join-Path $OutDir '头矩阵.md'), ($md -join "`r`n"), $utf8)

# ---------------------------------------------------------------------------
#  B) 链接探针（真用 API：编译 + 链接 + 运行）
# ---------------------------------------------------------------------------
$探针 = @{
    '文件系统' = @'
#包含 <文件系统>
整数 主函数() {
    自动 目录 = std::filesystem::temp_directory_path() / "zh_fs_probe";
    std::filesystem::create_directory(目录);
    自动 文件 = 目录 / "a.txt";
    { std::ofstream(文件) << "x"; }
    std::filesystem::copy_file(文件, 目录 / "b.txt", std::filesystem::copy_options::overwrite_existing);
    std::filesystem::rename(目录 / "b.txt", 目录 / "c.txt");
    返回 std::filesystem::exists(目录 / "c.txt") ? 0 : 1;
}
'@
    '系统错误' = @'
#包含 <系统错误>
#包含 <C标准输入输出>
整数 主函数() {
    尝试 { 抛出 std::system_error(5, std::system_category()); }
    捕获 (std::system_error& 错) {
        标准::格式化输出("捕获到 code=%d`n", 错.code().value());
        返回 错.code().value() == 5 ? 0 : 1;
    }
}
'@
    '时间' = @'
#包含 <时间>
整数 主函数() {
    自动& 库 = std::chrono::get_tzdb();
    返回 库.version.empty() ? 1 : 0;
}
'@
    '内存资源' = @'
#包含 <内存资源>
外部 "C" std::pmr::memory_resource* _Aligned_get_default_resource() noexcept;
整数 主函数() {
    自动* 资源 = _Aligned_get_default_resource();
    void* 块 = 资源->allocate(64, 64);
    资源->deallocate(块, 64, 64);
    返回 块 ? 0 : 1;
}
'@
    '复数' = @'
#包含 <复数>
整数 主函数() { std::complex<双精度> 甲(-1.0, 0.0); 返回 标准::符号位(甲) ? 0 : 1; }
'@
    '格式化文本' = @'
#包含 <格式化文本>
#包含 <C标准输入输出>
整数 主函数() { 自动 串 = std::format("{}+{}={}", 1, 2, 3); 标准::格式化输出("%s`n", 串.c_str()); 返回 串 == "1+2=3" ? 0 : 1; }
'@
}

$链接结果 = @()
Write-Host ("B) 链接探针：" + $探针.Count + " 个")
foreach ($名 in $探针.Keys) {
    $probe = Join-Path $OutDir ('probe\L_' + $名 + '.cpp')
    [System.IO.File]::WriteAllText($probe, $探针[$名], $utf8)
    $exe = Join-Path $OutDir ('probe\L_' + $名 + '.exe')
    $out = & $cxx -std=c++2c -o $exe $probe 2>&1 | Out-String
    $码 = $LASTEXITCODE
    $运行 = ''
    if ($码 -eq 0 -and (Test-Path $exe)) {
        $运行 = (& $exe 2>&1 | Out-String).Trim()
    }
    $缺失 = @(($out -split "`r?`n") | ForEach-Object { $m = [regex]::Match($_, 'undefined symbol:\s*(\S+)'); if ($m.Success) { $m.Groups[1].Value } })
    $首错 = (($out -split "`r?`n") | Where-Object { $_ -match 'error:|错误:' } | Select-Object -First 1)
    $链接结果 += [pscustomobject]@{
        探针 = $名
        通过 = ($码 -eq 0)
        运行输出 = $运行
        缺失符号 = $缺失
        首错 = if ($首错) { ([string]$首错).Trim().Substring(0, [Math]::Min(180, ([string]$首错).Trim().Length)) } else { '' }
    }
    Write-Host ("   " + $名.PadRight(10) + $(if ($码 -eq 0) { " 通过" } else { " 失败（缺 " + @($缺失).Count + " 个符号）" }))
}

$链接通过 = @($链接结果 | Where-Object { $_.通过 }).Count
Write-Host ("B) 结果：" + $链接通过 + " 通过 / " + (@($链接结果).Count - $链接通过) + " 失败")

# 缺失符号台账（去重）
$全缺失 = @($链接结果 | ForEach-Object { $_.缺失符号 } | Where-Object { $_ } | Sort-Object -Unique)
[System.IO.File]::WriteAllText((Join-Path $OutDir '缺失符号.txt'), ($全缺失 -join "`r`n"), $utf8)
Write-Host ("缺失符号（去重）：" + @($全缺失).Count + " 个 → " + (Join-Path $OutDir '缺失符号.txt'))

$md2 = @('# bundled 地基 · 链接探针', '', ('**' + $链接通过 + ' 通过 / ' + (@($链接结果).Count - $链接通过) + ' 失败**' + "`n" + ''),
        '| 探针 | 结果 | 缺失符号 | 首错 |', '|---|---|---|---|')
foreach ($r in ($链接结果 | Sort-Object @{Expression='通过';Descending=$false}, 探针)) {
    $md2 += ('| ' + $r.探针 + ' | ' + $(if ($r.通过) { '通过' } else { '**失败**' }) + ' | ' + (($r.缺失符号 | Select-Object -Unique) -join ', ') + ' | ' + $r.首错 + ' |')
}
$md2 += ''
$md2 += '## 缺失符号台账（去重 ' + @($全缺失).Count + ' 个）'
$md2 += ''
foreach ($s in $全缺失) { $md2 += ('- `' + $s + '`') }
[System.IO.File]::WriteAllText((Join-Path $OutDir '链接探针.md'), ($md2 -join "`r`n"), $utf8)

Write-Host ''
Write-Host ('报告：' + $OutDir + '\头矩阵.md 、链接探针.md 、缺失符号.txt')
