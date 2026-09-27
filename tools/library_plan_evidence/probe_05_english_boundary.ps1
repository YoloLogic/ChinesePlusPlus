# 边界到底有多宽：中文库（抄来翻译的独立实现）+ 派生兼容层 + 转换，
# 与英文 std::vector 的各种接口逐项对拍。PURE ASCII。
$ErrorActionPreference = 'Continue'
$cxx    = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$vsInc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$root   = 'E:\Chinese++\build\_border'
$ourInc = Join-Path $root 'ourinc'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Force $ourInc | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Zh([string]$c){ $s=''; foreach($x in $c.Split(',')){ $s += [char][int]("0x"+$x.Trim()) }; return $s }
$BZ=Zh '6807,51C6'; $XJ=Zh '7EC6,8282'; $XL=Zh '5411,91CF'; $XLSX=Zh '5411,91CF,5B9E,73B0'
$YR=Zh '538B,5165'; $CC=Zh '5C3A,5BF8';  $DY=Zh '6253,5370'

$orig = [System.IO.File]::ReadAllText((Join-Path $vsInc 'vector'))
$t = $orig.Replace('#ifndef _VECTOR_','#ifndef _ZH_VEC_IMPL_').Replace('#define _VECTOR_','#define _ZH_VEC_IMPL_')
$t = $t.Replace('_STD_BEGIN', "namespace $BZ { namespace $XJ {`nusing namespace std;").Replace('_STD_END','} }')
$t = [regex]::Replace($t,'\bvector\b',$XLSX)
$t = [regex]::Replace($t,'\bpush_back\b',$YR)
$t = [regex]::Replace($t,'\bsize\b',$CC)
$t = $t.Replace("using $XLSX = _STD $XLSX<_Ty, polymorphic_allocator<_Ty>>;",
                "using $XLSX = $BZ::$XJ::$XLSX<_Ty, std::pmr::polymorphic_allocator<_Ty>>;")

$t += "`n#include <vector>   // 兼容层要与英文 std::vector 转换，所以这里必须引它`n"
$t += @"

// ============ 派生兼容层：中文基础上派生，补英文名 + 与 std::vector 转换 ============
namespace $BZ {
    template <class _Ty, class _Alloc = std::allocator<_Ty>>
    class $XL : public $XJ::$XLSX<_Ty, _Alloc> {
    public:
        using 基类 = $XJ::$XLSX<_Ty, _Alloc>;
        using 基类::基类;

        template <class... _A> void push_back(_A&&... _v) { 基类::$YR(static_cast<_A&&>(_v)...); }
        auto size() const { return 基类::$CC(); }

        // 与英文 std::vector 的桥
        $XL(const std::vector<_Ty, _Alloc>& v) : 基类(v.begin(), v.end()) {}
        operator std::vector<_Ty, _Alloc>() const { return std::vector<_Ty, _Alloc>(基类::begin(), 基类::end()); }
    };
}
"@
[System.IO.File]::WriteAllText((Join-Path $ourInc "${XL}_h"), $t, $utf8)

$inc = @('-std=c++20', "-isystem$ourInc")
$pass=0; $fail=0
function T([string]$label,[bool]$expectOk,[string]$body){
    $src=Join-Path $root 't.cpp'; [System.IO.File]::WriteAllText($src,$body,$utf8)
    $o = & $cxx @inc -fsyntax-only $src 2>&1
    $c=$LASTEXITCODE; $ok = ($c -eq 0)
    $ne=@($o)|Where-Object{[string]$_ -match 'error:'}
    $mark = if($ok -eq $expectOk){'ok  '}else{'DIFF'}
    if($ok -eq $expectOk){$script:pass++}else{$script:fail++}
    Write-Host ("  [{0}] {1}" -f $mark,$label)
    if(-not $ok){ Write-Host ("         " + ([string]($ne|Select-Object -First 1)).Trim()) }
}
$H="${XL}_h"
$pre = "#include <$H>`n#include <vector>`n#include <cstdio>`n"
$pre += "void $DY(const std::vector<int>& v){ (void)v; }`n"
$pre += "template <class T> void 模板收(const std::vector<T>& v){ (void)v; }`n"
$pre += "template <class C> void 泛型收(const C& c){ (void)c; }`n"

Write-Host ''
Write-Host '=== 中文库对象 与 英文世界 的边界 ==='
T '① 中文名 + 英文名 + 转换，都用' $true ($pre + "int main(){ $BZ::$XL<int> v; v.$YR(1); v.push_back(2); std::vector<int> w = v; $BZ::$XL<int> z = w; return (int)(v.size()+w.size()+z.size())-6; }")
T '② 传给【非模板】英文接口 void f(const std::vector<int>&)' $true ($pre + "int main(){ $BZ::$XL<int> v; v.$YR(1); $DY(v); return 0; }")
T '③ 传给【模板】英文接口 template<class T> f(const std::vector<T>&)' $false ($pre + "int main(){ $BZ::$XL<int> v; v.$YR(1); 模板收(v); return 0; }")
T '④ 传给【泛型】接口 template<class C> f(const C&)' $true ($pre + "int main(){ $BZ::$XL<int> v; v.$YR(1); 泛型收(v); return 0; }")
T '⑤ 范围 for 遍历' $true ($pre + "int main(){ $BZ::$XL<int> v; v.$YR(1); int s=0; for(int x: v) s+=x; return s-1; }")
T '⑥ 标准算法 std::sort(v.begin(), v.end())' $true ($pre + "#include <algorithm>`nint main(){ $BZ::$XL<int> v; v.$YR(2); v.$YR(1); std::sort(v.begin(), v.end()); return v[0]-1; }")
Write-Host ''
Write-Host "  $pass 符合预期, $fail 与预期不符"
