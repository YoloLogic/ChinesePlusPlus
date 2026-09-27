# 同上，但把路径规范化后再分类，并用 ReadAllLines 数行数（与前面口径一致）。
$ErrorActionPreference = 'Continue'
$cxx  = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$root = 'E:\Chinese++\build\_closure'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Force $root | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$msvc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$sdk  = 'C:\Program Files (x86)\Windows Kits\10\Include'
$clangInc = 'E:\Chinese++\build\Release\lib\clang\24\include'

function Lines([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    return ([System.IO.File]::ReadAllLines($p)).Count
}

foreach ($h in @('vector','string','map')) {
    $src = Join-Path $root 't.cpp'
    [System.IO.File]::WriteAllText($src, "#include <$h>`nint main(){return 0;}`n", $utf8)
    $out = & cmd /c "`"$cxx`" -std=c++20 -fsyntax-only -H `"$src`" 2>&1"
    $raw = @($out) | ForEach-Object { if ([string]$_ -match '^\.+\s+(.+?)\s*$') { $Matches[1] } }
    # normalise / -> \
    $paths = @($raw | ForEach-Object { $_.Replace('/','\') } | Sort-Object -Unique)

    $g = @{}
    foreach ($p in $paths) {
        $k = if     ($p.StartsWith($msvc,     'OrdinalIgnoreCase')) { 'MSVC STL' }
             elseif ($p.StartsWith($sdk,      'OrdinalIgnoreCase')) { 'Windows SDK' }
             elseif ($p.StartsWith($clangInc, 'OrdinalIgnoreCase')) { 'clang 内建' }
             else { '其它' }
        if (-not $g.ContainsKey($k)) { $g[$k] = [pscustomobject]@{ N = 0; L = 0 } }
        $g[$k].N++; $g[$k].L += (Lines $p)
    }
    $totN = ($g.Values | Measure-Object -Property N -Sum).Sum
    $totL = ($g.Values | Measure-Object -Property L -Sum).Sum
    "=== <$h>  闭包 {0} 个头 / {1:N0} 行 ===" -f $totN, $totL
    foreach ($k in @('MSVC STL','Windows SDK','clang 内建','其它')) {
        if ($g.ContainsKey($k)) { "    {0,-12} {1,4} 个头  {2,9:N0} 行" -f $k, $g[$k].N, $g[$k].L }
    }
    if ($h -eq 'vector' -or $h -eq 'map') {
        ''
        "  <$h> 闭包里的 MSVC STL 头（{0} 个）：" -f $g['MSVC STL'].N
        ($paths | Where-Object { $_.StartsWith($msvc,'OrdinalIgnoreCase') } |
            ForEach-Object { Split-Path $_ -Leaf } | Sort-Object) -join '  '
        ''
        "  最大的几个：" 
        $paths | Where-Object { $_.StartsWith($msvc,'OrdinalIgnoreCase') } |
            ForEach-Object { [pscustomobject]@{ F = (Split-Path $_ -Leaf); L = (Lines $_) } } |
            Sort-Object L -Descending | Select-Object -First 12 |
            ForEach-Object { "    {0,-26} {1,7:N0} 行" -f $_.F, $_.L }
    }
    ''
}
Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
