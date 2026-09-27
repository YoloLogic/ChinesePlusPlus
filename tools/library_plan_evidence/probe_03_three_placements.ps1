# 抄一份 vector 的三种落地位置，看各自能不能编译、代价是什么。
$ErrorActionPreference = 'Continue'
$cxx    = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$vsInc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$root   = 'E:\Chinese++\build\_copy2'
$ourInc = Join-Path $root 'ourinc'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Force $ourInc | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$BZ = "$([char]0x6807)$([char]0x51C6)"      # 标准
$XL = "$([char]0x5411)$([char]0x91CF)"      # 向量
$YR = "$([char]0x538B)$([char]0x5165)"      # 压入

$orig = [System.IO.File]::ReadAllText((Join-Path $vsInc 'vector'))
$anchor = '_CONSTEXPR20 void push_back(const _Ty& _Val) { // insert element at end, provide strong guarantee'
$zhMember = "    template <class... _ZhA> void $YR(_ZhA&&... _ZhV) { push_back(static_cast<_ZhA&&>(_ZhV)...); }`n"

function Make([string]$mode) {
    $t = $orig.Replace('#ifndef _VECTOR_', '#ifndef _ZH_VECTOR_').Replace('#define _VECTOR_', '#define _ZH_VECTOR_')
    if ($mode -ne 'stay') {
        $t = $t.Replace('_STD_BEGIN', "namespace $BZ {").Replace('_STD_END', '}')
    }
    $t = [regex]::Replace($t, '\bvector\b', $XL)
    $t = $t.Replace($anchor, $zhMember + $anchor)
    if ($mode -eq 'usingns') {
        $t = $t.Replace("namespace $BZ {", "namespace $BZ {`nusing namespace std;")
    }
    $name = "$XL" + "_" + $mode
    [System.IO.File]::WriteAllText((Join-Path $ourInc $name), $t, $utf8)
    return $name
}

$inc = @('-std=c++20', "-isystem$ourInc")
function Show([string]$label, [string]$hdr, [string]$body) {
    $src = Join-Path $root 't.cpp'
    [System.IO.File]::WriteAllText($src, $body, $utf8)
    $out = & $cxx @inc -fsyntax-only $src 2>&1
    $code = $LASTEXITCODE
    Write-Host ""
    Write-Host "===== $label"
    Write-Host "  exit=$code"
    $errs = @($out) | Where-Object { $null -ne $_ -and ([string]$_ -match 'error:') }
    Write-Host ("  错误条数: " + $errs.Count)
    if ($code -ne 0) {
        $errs | Select-Object -First 4 | ForEach-Object { Write-Host ("    " + ([string]$_).Trim()) }
    }
    return $code
}

# ---- 甲：内容留在 std（类名改成 向量，即 std::向量）
$hStay = Make 'stay'
Show '甲) 抄一份但【留在 std】里：std::向量' $hStay "#include <$hStay>`nint main(){ std::$XL<int> v; v.$YR(1); return (int)v.size()==1?0:1; }" | Out-Null

# ---- 乙：搬进 标准，并加 using namespace std; 兜住内部件
$hUsing = Make 'usingns'
Show '乙) 搬进 标准 + using namespace std;' $hUsing "#include <$hUsing>`nint main(){ $BZ::$XL<int> v; v.$YR(1); return (int)v.size()==1?0:1; }" | Out-Null

# ---- 丙：搬进 标准，不加任何兜底（对照）
$hPlain = Make 'plain'
Show '丙) 搬进 标准，不加兜底（对照）' $hPlain "#include <$hPlain>`nint main(){ $BZ::$XL<int> v; v.$YR(1); return 0; }" | Out-Null
