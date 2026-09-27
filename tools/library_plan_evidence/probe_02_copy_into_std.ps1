# 抄一份 <vector>，放进 namespace 标准，类名改成 向量，加一个中文成员 ——
# 看它到底能不能编译，以及第一批错误是什么。PURE ASCII。
$ErrorActionPreference = 'Continue'
$cxx    = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$vsInc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$root   = 'E:\Chinese++\build\_copy'
$ourInc = Join-Path $root 'ourinc'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Force $ourInc | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$BZ = "$([char]0x6807)$([char]0x51C6)"      # 标准
$XL = "$([char]0x5411)$([char]0x91CF)"      # 向量
$YR = "$([char]0x538B)$([char]0x5165)"      # 压入

$orig = [System.IO.File]::ReadAllText((Join-Path $vsInc 'vector'))
"原文件: $(([System.IO.File]::ReadAllLines((Join-Path $vsInc 'vector'))).Count) 行"
"_STD_BEGIN 出现 $(([regex]::Matches($orig,'_STD_BEGIN')).Count) 次，_STD_END $(([regex]::Matches($orig,'_STD_END')).Count) 次"
"裸词 vector 出现 $(([regex]::Matches($orig,'\bvector\b')).Count) 次"

# 1) 换守卫（避免和微软的 <vector> 抢 _VECTOR_）
$t = $orig.Replace('#ifndef _VECTOR_', '#ifndef _ZH_VECTOR_').Replace('#define _VECTOR_', '#define _ZH_VECTOR_')
# 2) 把 std 命名空间换成 标准
$t = $t.Replace('_STD_BEGIN', "namespace $BZ {").Replace('_STD_END', '}')
# 3) 类名 vector -> 向量（内部名是 _Vector_ 大写 V，不会被误伤）
$t = [regex]::Replace($t, '\bvector\b', $XL)
# 4) 加一个中文成员，英文原名原样保留
$anchor = '_CONSTEXPR20 void push_back(const _Ty& _Val) { // insert element at end, provide strong guarantee'
if ($t.IndexOf($anchor) -lt 0) { throw 'anchor lost after rename' }
$t = $t.Replace($anchor, "    template <class... _ZhA> void $YR(_ZhA&&... _ZhV) { push_back(static_cast<_ZhA&&>(_ZhV)...); }`n$anchor")
[System.IO.File]::WriteAllText((Join-Path $ourInc $XL), $t, $utf8)
"造好 <$XL>: $(([System.IO.File]::ReadAllLines((Join-Path $ourInc $XL))).Count) 行"

$inc = @('-std=c++20', "-isystem$ourInc")
function Show([string]$label, [string]$body) {
    $src = Join-Path $root 't.cpp'
    [System.IO.File]::WriteAllText($src, $body, $utf8)
    $out = & $cxx @inc -fsyntax-only $src 2>&1
    $code = $LASTEXITCODE
    Write-Host ""
    Write-Host "===== $label"
    Write-Host "  exit=$code"
    if ($code -ne 0) {
        @($out) | Where-Object { $null -ne $_ } | Select-Object -First 6 |
            ForEach-Object { Write-Host ("    " + ([string]$_).Trim()) }
    }
    return $code
}

$a = Show 'A) 只引我们的 <向量>（整份抄来的实现）' "#include <$XL>`nint main(){ $BZ::$XL<int> v; v.$YR(1); return (int)v.size()==1?0:1; }"

$b = Show 'B) <向量> + <vector> 同一文件（这才是"撞车"的真正考验）' `
    "#include <$XL>`n#include <vector>`nint main(){ $BZ::$XL<int> a; a.$YR(1); std::vector<int> b; b.push_back(2); return (int)(a.size()+b.size())-3; }"

$c = Show 'C) 两种类名都在，且两种成员名都可用' `
    "#include <$XL>`n#include <vector>`nint main(){ $BZ::$XL<int> a; a.$YR(1); a.push_back(2); std::vector<int> b; b.push_back(3); return (int)(a.size()+b.size())-4; }"
