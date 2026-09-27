# 用户的完整设计：基类 = 抄来翻译的中文实现；在它上面派生一层补回英文名。
# 验证：中文名、英文名、微软 std::vector 三者能不能同时在。
$ErrorActionPreference = 'Continue'
$cxx    = 'E:\Chinese++\build\Release\bin\chinese++.exe'
$vsInc  = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$root   = 'E:\Chinese++\build\_layer'
$ourInc = Join-Path $root 'ourinc'
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
New-Item -ItemType Directory -Force $ourInc | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Zh([string]$cps){ $s=''; foreach($c in $cps.Split(',')){ $s += [char][int]("0x"+$c.Trim()) }; return $s }
$BZ   = Zh '6807,51C6'          # 标准
$XJ   = Zh '7EC6,8282'          # 细节
$XL   = Zh '5411,91CF'          # 向量
$XLSX = Zh '5411,91CF,5B9E,73B0'# 向量实现
$YR   = Zh '538B,5165'          # 压入
$CC   = Zh '5C3A,5BF8'          # 尺寸

$orig = [System.IO.File]::ReadAllText((Join-Path $vsInc 'vector'))
$anchor = '_CONSTEXPR20 void push_back(const _Ty& _Val) { // insert element at end, provide strong guarantee'

# ---- 第一层：抄一份，翻成中文，放进 标准::细节 ----
$t = $orig.Replace('#ifndef _VECTOR_', '#ifndef _ZH_VEC_IMPL_').Replace('#define _VECTOR_', '#define _ZH_VEC_IMPL_')
$t = $t.Replace('_STD_BEGIN', "namespace $BZ { namespace $XJ {`nusing namespace std;").Replace('_STD_END', '} }')
$t = [regex]::Replace($t, '\bvector\b', $XLSX)                  # 类名 -> 向量实现
$t = [regex]::Replace($t, '\bpush_back\b', $YR)                 # 成员名 -> 压入
$t = [regex]::Replace($t, '\bsize\b', $CC)                      # 成员名 -> 尺寸
# pmr 那两处引用要理清
$t = $t.Replace("using $XLSX = _STD $XLSX<_Ty, polymorphic_allocator<_Ty>>;",
                "using $XLSX = $BZ::$XJ::$XLSX<_Ty, std::pmr::polymorphic_allocator<_Ty>>;")
[System.IO.File]::WriteAllText((Join-Path $ourInc "${XL}_impl"), $t, $utf8)
"第一层 <${XL}_impl>：$(([System.IO.File]::ReadAllLines((Join-Path $ourInc "${XL}_impl"))).Count) 行"

# ---- 第二层：在中文的基础上派生，补回英文名 ----
$layer2 = @"

// ==================== 第二层：在中文的基础上派生，补回英文名 ====================
namespace $BZ {
    template <class _Ty, class _Alloc = std::allocator<_Ty>>
    class $XL : public $XJ::$XLSX<_Ty, _Alloc> {
    public:
        using 基类 = $XJ::$XLSX<_Ty, _Alloc>;
        using 基类::基类;                                  // 继承全部构造函数

        // 英文原名，逐个转发回中文名
        template <class... _A> void push_back(_A&&... _v) { 基类::$YR(static_cast<_A&&>(_v)...); }
        auto size() const { return 基类::$CC(); }
    };
}
"@
[System.IO.File]::AppendAllText((Join-Path $ourInc "${XL}_impl"), $layer2, $utf8)
"加第二层后：$(([System.IO.File]::ReadAllLines((Join-Path $ourInc "${XL}_impl"))).Count) 行"

$inc = @('-std=c++20', "-isystem$ourInc")
function T([string]$label,[string]$body){
    $src = Join-Path $root 't.cpp'
    [System.IO.File]::WriteAllText($src, $body, $utf8)
    $exe = Join-Path $root 't.exe'
    $o = & $cxx @inc -o $exe $src 2>&1
    $c = $LASTEXITCODE
    $run = '-'; if ($c -eq 0) { $run = ("$(& cmd /c "`"$exe`" 2>&1")").Trim() }
    $ne = @($o) | Where-Object { [string]$_ -match 'error:' }
    Write-Host ""
    Write-Host "===== $label"
    Write-Host "  exit=$c  错误=$($ne.Count)  运行输出='$run'"
    if ($c -ne 0) { $ne | Select-Object -First 3 | ForEach-Object { Write-Host ("    " + ([string]$_).Trim()) } }
}
$H = "${XL}_impl"
T 'A) 只引我们的库：中文名 + 英文名同一个对象上都要能用' @"
#include <$H>
#include <cstdio>
int main(){ $BZ::$XL<int> v; v.$YR(1); v.push_back(2); std::printf(`"%d%d`",(int)v.$CC(),(int)v.size()); return 0; }
"@
T 'B) 与微软 std::vector 并存' @"
#include <$H>
#include <vector>
#include <cstdio>
int main(){ $BZ::$XL<int> v; v.$YR(1); v.push_back(2); std::vector<int> w; w.push_back(3);
           std::printf(`"%d%d`",(int)v.size(),(int)w.size()); return 0; }
"@
T 'C) 基类（纯中文那层）单独也能用' @"
#include <$H>
#include <cstdio>
int main(){ $BZ::$XJ::$XLSX<int> b; b.$YR(5); std::printf(`"%d`",(int)b.$CC()); return 0; }
"@
