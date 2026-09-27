# ============================================================================
#  make_zhstdlib2.ps1 -- 步骤 2：乙类（自含实现）头 -> 中文版
#
#  每个头两层（方案 §〇）：
#    第一层  标准::细节::<中文名>实现   —— 抄自微软，成员名全中文
#    第二层  标准::<中文名>             —— 在中文的基础上派生，补回英文原名
#
#  六步配方（方案 §3.1）+ 编译器当改名校对（§3.2 坑②）：
#    1 换守卫  2 搬名域 标准::细节 + 使用 名域 std;   3 类型名   4 成员名
#    5 手工理嵌套名域   6 追加派生层
#
#  ⚠ 三条已经踩过的坑（都写进方案）：
#    · 不能整文件全局字符串替换（会把 #include <xpolymorphic_allocator.h> 改坏）
#    · 成员名会撞借用类型的同名成员 -> 让编译器报行列号，按【字节】偏移改回
#    · 中文标识符不能以数字开头（后置构词：字符16位）
#
#  用法：powershell -File tools\make_zhstdlib2.ps1 -Header typeindex
# ============================================================================
param([string] $Header = 'typeindex')

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx   = Join-Path $root 'build\Release\bin\chinese++.exe'
$vsInc = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\include'
$out   = Join-Path $root 'zhstdlib'
$utf8  = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
#  表：每个头一条。加新头 = 加一条。
# ---------------------------------------------------------------------------
$H = @{
  'mutex' = @{
    zh      = '互斥量'
    types   = [ordered]@{
      '_Mutex_base'            = '_互斥量基类'
      'mutex'                  = '互斥量实现'
      'condition_variable'     = '条件变量实现'
      'condition_variable_any' = '条件变量任意实现'
      'unique_lock'            = '独占锁实现'
      'lock_guard'             = '锁守卫实现'
      'once_flag'              = '一次标志实现'
      'adopt_lock_t'           = '接管锁类型'
      'defer_lock_t'           = '延迟锁类型'
      'try_to_lock_t'          = '尝试锁类型'
      # 本文件自己定义的内部自由函数：被 `_STD X` 限定引用。
      # 普通成员表覆盖不到它们（步 4c 只处理 types+data），必须在这里登记改名，
      # 否则报「namespace 'std' 中没有名为 '_Unlock_locks' 的成员」。
      # 编译器自己的提示就是答案：「你是不是想直接写 '_Try_lock_from_locks'？」
      '_Unlock_locks'          = '_解锁各锁'
      '_Try_lock_from_locks'   = '_从各锁尝试加锁'
    }
    # ⚠ 注意：`mutex` 既是类名，也是 unique_lock 的成员函数名 —— 两者都变「互斥量实现」，
    #   于是 独占锁::互斥量实现() 读起来别扭但不歧义（记为妥协）。
    members = [ordered]@{
      'lock' = '加锁'; 'unlock' = '解锁'; 'try_lock' = '尝试加锁'
      'try_lock_for' = '限时加锁'; 'try_lock_until' = '加锁至时刻'
      'native_handle' = '原生句柄'; 'owns_lock' = '持有锁'
      'release' = '释放'; 'swap' = '交换'
      'adopt_lock' = '接管锁'; 'defer_lock' = '延迟锁'; 'try_to_lock' = '尝试锁'
      'call_once' = '一次调用'
    }
    data    = [ordered]@{}
    # ⚠ 实测教训：不要照【标准文档】的 API 写派生层，要照【微软这个版本实际有的】写。
    #   · native_handle / native_handle_type 在 MSVC 里已被官方删除（GH-3820，
    #     <mutex> 第 75、615 行就写着 "have intentionally been removed"），
    #     照标准写就会生成 基类::原生句柄() -> 没有这个成员。
    #   · once_flag 也**不在** <mutex> 里（grep 原文 0 命中），
    #     照标准写就会生成 类型 一次标志 : 公开 细节::一次标志实现 -> 缺少 类名。
    derive  = @( @('lock','加锁'), @('try_lock','尝试加锁'), @('unlock','解锁') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    # 一个头里有多个对外类 —— 主类由机制生成，其余在这里手写
    extra = @'

名域 标准 {

// 独占锁（std::unique_lock）
模板 <类型名 互斥类型>
类型 独占锁 : 公开 细节::独占锁实现<互斥类型> {
公开:
    使用 基类 = 细节::独占锁实现<互斥类型>;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 lock(参数&&... 值) { 返回 基类::加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock(参数&&... 值) { 返回 基类::尝试加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 unlock(参数&&... 值) { 返回 基类::解锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 owns_lock(参数&&... 值) 常量 { 返回 基类::持有锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 release(参数&&... 值) { 返回 基类::释放(static_cast<参数&&>(值)...); }
};

// 锁守卫（std::lock_guard）
模板 <类型名 互斥类型>
类型 锁守卫 : 公开 细节::锁守卫实现<互斥类型> {
公开:
    使用 基类 = 细节::锁守卫实现<互斥类型>;
    使用 基类::基类;
};

// 自由函数（这两个自由函数是 <mutex> 自己定义的，已随正文搬进 细节）
模板 <类型名 互斥类型> 内联 空型 加锁(互斥类型& 甲, 互斥类型& 乙) { 细节::加锁(甲, 乙); }

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <互斥量>`n整数 主函数(){ 标准::互斥量 甲; 甲.加锁(); 甲.解锁(); 标准::锁守卫<标准::互斥量> 卫(甲); 返回 0; }'),
      @('与微软原头并存','#包含 <互斥量>`n#包含 <mutex>`n整数 主函数(){ 标准::互斥量 甲; 甲.加锁(); std::mutex 乙; 乙.lock(); 乙.unlock(); 返回 0; }'),
      @('英文名与中文名并用 + 独占锁','#包含 <互斥量>`n整数 主函数(){ 标准::互斥量 甲; 标准::独占锁<标准::互斥量> 锁(甲); 布尔 有 = 锁.持有锁(); 布尔 有2 = 锁.owns_lock(); 锁.解锁(); 锁.unlock(); 返回 (整数)(有 || 有2) - 1; }')
    )
  }
  'scoped_allocator' = @{
    zh      = '作用域分配器'
    types   = [ordered]@{ 'scoped_allocator_adaptor' = '作用域分配器适配器实现'
                          '_Scoped_base' = '_作用域基类'
                          '_Scoped_outermost' = '_作用域最外层'
                          '_Scoped_outermost_helper' = '_作用域最外层助手'
                          '_Secret_scoped_allocator_construct_tag' = '_作用域构造内部标号' }
    # ⚠ 不翻 allocator_traits / rebind / enable_if_t 等 std 的名字
    members = [ordered]@{ 'inner_allocator' = '内层分配器'
                          'outer_allocator' = '外层分配器'
                          'select_on_container_copy_construction' = '复制时选择'
                          'construct' = '构造'; 'destroy' = '析构'
                          'max_size' = '最大尺寸'
                          'allocate' = '分配'; 'deallocate' = '释放' }
    data    = [ordered]@{}
    derive  = @( @('inner_allocator','内层分配器'), @('outer_allocator','外层分配器'),
                 @('select_on_container_copy_construction','复制时选择'),
                 @('construct','构造'), @('destroy','析构'),
                 @('max_size','最大尺寸'), @('allocate','分配'), @('deallocate','释放') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 外层, 类型名... 内层>'; args = '<外层, 内层...>' }
    tests = @(
      @('只引中文头','#包含 <作用域分配器>`n整数 主函数(){ 标准::作用域分配器<std::allocator<int>> 甲; 返回 (整数)甲.内层分配器().max_size() > 0 ? 0 : 1; }'),
      @('与微软原头并存','#包含 <作用域分配器>`n#包含 <scoped_allocator>`n整数 主函数(){ 标准::作用域分配器<std::allocator<int>> 甲; std::scoped_allocator_adaptor<std::allocator<int>> 乙; 返回 (整数)(甲.外层分配器() == 乙.outer_allocator()) - 1; }'),
      @('英文名与中文名并用','#包含 <作用域分配器>`n整数 主函数(){ 标准::作用域分配器<std::allocator<int>> 甲; 返回 (整数)甲.内层分配器().max_size() > 0 && 甲.inner_allocator().max_size() > 0 ? 0 : 1; }')
    )
  }
  'stack' = @{
    zh      = '栈'
    types   = [ordered]@{ 'stack' = '栈实现'
                          '_Adaptor_formatter_base' = '_适配器格式化基类' }
    # ⚠ 不翻 uses_allocator / formatter —— 它们是 std 的模板，改名会断
    members = [ordered]@{ 'emplace' = '就地构造'; 'empty' = '为空'; 'pop' = '弹出'
                          'push' = '压入'; 'push_range' = '范围压入'
                          'size' = '尺寸'; 'swap' = '交换'; 'top' = '栈顶' }
    data    = [ordered]@{}
    derive  = @( @('emplace','就地构造'), @('empty','为空'), @('pop','弹出'),
                 @('push','压入'), @('push_range','范围压入'), @('size','尺寸'),
                 @('swap','交换'), @('top','栈顶') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 元素, 类型名 容器 = std::deque<元素>>'; args = '<元素, 容器>' }
    # stack 的 uses_allocator 特化必须挂在【对外那个类型】上，
    # 所以要在 std 里为重发一份（抄来的那份挂在内层实现类型上，对外类型用不上）
    stdExtra = '模板 <类型名 元素, 类型名 容器, 类型名 分配器>
    结构 uses_allocator<标准::栈<元素, 容器>, 分配器> : std::uses_allocator<容器, 分配器>::type {};'
    tests = @(
      @('只引中文头','#包含 <栈>`n整数 主函数(){ 标准::栈<整数> 甲; 甲.压入(1); 返回 (整数)甲.尺寸() - 1; }'),
      @('与微软原头并存','#包含 <栈>`n#包含 <stack>`n整数 主函数(){ 标准::栈<整数> 甲; 甲.压入(1); std::stack<int> 乙; 乙.push(1); 返回 (整数)甲.尺寸() + (整数)乙.size() - 2; }'),
      @('英文名与中文名并用 + 栈顶','#包含 <栈>`n整数 主函数(){ 标准::栈<整数> 甲; 甲.压入(2); 甲.push(3); 返回 甲.栈顶() + 甲.top() - 6; }')
    )
  }
  'typeindex' = @{
    zh      = '类型索引'
    types   = [ordered]@{ 'type_index' = '类型索引实现' }
    members = [ordered]@{ 'hash_code' = '哈希值'; 'name' = '名称' }
    data    = [ordered]@{ '_Tptr' = '_类型指针' }
    # 派生层要补回的英文名（英文 = 中文），用一模板转发，不需要签名
    derive  = @( @('hash_code','哈希值'), @('name','名称') )
    # 额外要在 std 里补的特化（派生类型也需要 std::hash）
    stdHash = $true
    tparam  = @{ decl = ''; args = '' }
    tests = @(
      @('只引中文头','#包含 <类型索引>`n整数 主函数(){ 标准::类型索引 甲(类型标识(整数)); 返回 0; }'),
      @('与微软原头并存','#包含 <类型索引>`n#包含 <typeindex>`n整数 主函数(){ 标准::类型索引 甲(类型标识(整数)); std::type_index 乙(类型标识(整数)); 返回 0; }'),
      @('英文名与中文名并用','#包含 <类型索引>`n整数 主函数(){ 标准::类型索引 甲(类型标识(整数)); 返回 (整数)甲.hash_code() * 0 + (整数)甲.哈希值() * 0 + (整数)甲.name()[0] * 0; }')
    )
  }
  # ---- C++20 并发原语：与别的 std 接口没有类型交互，适合"抄一份 + 派生" ----
  'barrier' = @{
    zh      = '屏障'
    types   = [ordered]@{ 'barrier' = '屏障实现'
                          '_No_completion_function' = '_无完成函数'
                          '_Arrival_token' = '_到达令牌'
                          '_Counter_t' = '_计数器类型'
                          'arrival_token' = '到达令牌' }
    members = [ordered]@{ 'arrive' = '到达'; 'arrive_and_drop' = '到达并退出'
                          'arrive_and_wait' = '到达并等待'; 'wait' = '等待' }
    data    = [ordered]@{}
    derive  = @( @('arrive','到达'), @('arrive_and_drop','到达并退出'),
                 @('arrive_and_wait','到达并等待'), @('wait','等待') )
    deriveTypes = @( @('arrival_token','到达令牌') )
    stdHash = $false
    # barrier 是【类模板】，派生层必须重复模板形参（第一版没给 -> "需要模板实参"）
    tparam = @{ decl = '模板 <类型名 完成函数 = 细节::_无完成函数>'; args = '<完成函数>' }
    tests = @(
      @('只引中文头','#包含 <屏障>`n整数 主函数(){ 标准::屏障<> 甲(3); 甲.到达(); 返回 0; }'),
      @('与微软原头并存','#包含 <屏障>`n#包含 <barrier>`n整数 主函数(){ 标准::屏障<> 甲(3); 甲.到达(); std::barrier<> 乙(3); 乙.arrive(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <屏障>`n整数 主函数(){ 标准::屏障<> 甲(3); 甲.到达(); 甲.arrive(); 返回 0; }')
    )
  }
  'semaphore' = @{
    zh      = '信号量'
    types   = [ordered]@{ 'counting_semaphore' = '计数信号量实现'
                          '_Semaphore_max' = '_信号量最大值'
                          '_Semaphore_least_max_value' = '_信号量最小最大值' }
    members = [ordered]@{ 'acquire' = '获取'; 'try_acquire' = '尝试获取'
                          'try_acquire_for' = '尝试限时获取'
                          'try_acquire_until' = '尝试获取至时刻'
                          'release' = '释放'; 'max' = '最大' }
    data    = [ordered]@{}
    derive  = @( @('acquire','获取'), @('try_acquire','尝试获取'),
                 @('try_acquire_for','尝试限时获取'),
                 @('try_acquire_until','尝试获取至时刻'),
                 @('release','释放'), @('max','最大') )
    stdHash = $false
    # 非类型模板形参（ptrdiff_t）—— 形参名也要中文
    tparam  = @{ decl = '模板 <ptrdiff_t 最小最大值 = 细节::_信号量最大值>'; args = '<最小最大值>' }
    tests = @(
      @('只引中文头','#包含 <信号量>`n整数 主函数(){ 标准::计数信号量<2> 甲(0); 甲.释放(); 返回 0; }'),
      @('与微软原头并存','#包含 <信号量>`n#包含 <semaphore>`n整数 主函数(){ 标准::计数信号量<2> 甲(0); 甲.释放(); std::counting_semaphore<2> 乙(0); 乙.release(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <信号量>`n整数 主函数(){ 标准::计数信号量<2> 甲(0); 甲.释放(); 甲.release(); 返回 0; }')
    )
  }
  'condition_variable' = @{
    zh      = '条件变量'
    # ⚠ std::condition_variable（非 _any）其实定义在 <mutex> 里；这个头只有 _any
    pub     = '条件变量任意'
    types   = [ordered]@{ 'condition_variable_any' = '条件变量任意实现'
                          # 这个头里 `shared_ptr<mutex>` / `_Ptr->_Mymtx()` 必须落到
                          # 【我们自己那份 <互斥量>】的家族里，否则碰到 std 的私有成员
                          # （微软只对真实的 std::condition_variable_any 开友元，见步 0）
                          'mutex'                = '互斥量实现'
                          'condition_variable'   = '条件变量实现'
                          '_Mutex_base'          = '_互斥量基类'
                          # lock_guard / unique_lock 也定义在 <mutex> 里（就是现在我们包含的那份）
                          'lock_guard'           = '锁守卫实现'
                          'unique_lock'          = '独占锁实现'
                          '_Unlock_guard' = '_解锁卫兵'
                          '_Cv_any_notify_all' = '_条件变量任意通知全部' }
    # 已经抄完的头才开这个开关（见步 0 的长注释）
    zhIncludes = @{ 'mutex' = '互斥量' }
    members = [ordered]@{ 'notify_all' = '通知全部'; 'notify_one' = '通知一个'
                          'wait' = '等待'; 'wait_for' = '限时等待'
                          'wait_until' = '等待至时刻'
                          # 跨头成员名：这两个是 <互斥量> 里定下的译名，
                          # 本文件对 独占锁实现 调 .unlock() 必须跟着叫「解锁」，
                          # 否则 error: '独占锁实现<互斥量实现>' 中没有名为 'unlock' 的成员。
                          # ⚠ 这就是方案 §3.6.1 说的"译名必须全库共享"——
                          #   现在还是按头抄一遍，最终要提成一张全局表。
                          'lock' = '加锁'; 'unlock' = '解锁'; 'try_lock' = '尝试加锁' }
    data    = [ordered]@{}
    derive  = @( @('notify_all','通知全部'), @('notify_one','通知一个'),
                 @('wait','等待'), @('wait_for','限时等待'),
                 @('wait_until','等待至时刻') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    tests = @(
      @('只引中文头','#包含 <条件变量>`n整数 主函数(){ 标准::条件变量任意 甲; 甲.通知全部(); 返回 0; }'),
      @('与微软原头并存','#包含 <条件变量>`n#包含 <condition_variable>`n整数 主函数(){ 标准::条件变量任意 甲; 甲.通知全部(); std::condition_variable_any 乙; 乙.notify_all(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <条件变量>`n整数 主函数(){ 标准::条件变量任意 甲; 甲.通知一个(); 甲.notify_one(); 返回 0; }'),
      # 方案 §3.6：<mutex> 里 `friend condition_variable_any;` 与本头的类必须成对改名。
      # 两个头一起引，才能证明友元真的对上了（<互斥量> 里的 条件变量任意实现 是同一个类）。
      @('与互斥量并存（friend 成对）','#包含 <互斥量>`n#包含 <条件变量>`n整数 主函数(){ 标准::互斥量 甲; 标准::条件变量任意 乙; 标准::独占锁<标准::互斥量> 锁(甲); 乙.等待(锁); 乙.通知全部(); 返回 0; }')
    )
  }
  'latch' = @{
    zh      = '门闩'
    types   = [ordered]@{ 'latch' = '门闩实现' }
    members = [ordered]@{ 'count_down' = '递减'; 'try_wait' = '尝试等待'
                          'wait' = '等待'; 'arrive_and_wait' = '到达并等待' }
    data    = [ordered]@{}
    derive  = @( @('count_down','递减'), @('try_wait','尝试等待'),
                 @('wait','等待'), @('arrive_and_wait','到达并等待') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    tests = @(
      @('只引中文头','#包含 <门闩>`n整数 主函数(){ 标准::门闩 甲(1); 甲.递减(); 返回 0; }'),
      @('与微软原头并存','#包含 <门闩>`n#包含 <latch>`n整数 主函数(){ 标准::门闩 甲(1); 甲.递减(); std::latch 乙(1); 乙.count_down(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <门闩>`n整数 主函数(){ 标准::门闩 甲(2); 甲.递减(); 甲.count_down(); 返回 0; }')
    )
  }
}

$spec = $H[$Header]
if (-not $spec) { throw "表里没有 $Header —— 先在 make_zhstdlib2.ps1 的表里加一条" }

$srcPath = Join-Path $vsInc $Header
$text = [System.IO.File]::ReadAllText($srcPath)
$origLines = ([System.IO.File]::ReadAllLines($srcPath)).Count
Write-Host "=== 步骤 2：<$($spec.zh)>（源 <$Header>, $origLines 行）===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
#  步 0：把 `#include <英文头>` 换成我们【已经抄好】的 `#include <汉语头>`
#
#  为什么必须这么做（实测，<condition_variable>）：MSVC 的 <condition_variable> 里
#  `_Ptr->_Mymtx()` 的 `_Ptr` 是 `shared_ptr<mutex>`，而 `mutex::_Mymtx()` 是【私有】的，
#  微软只对【真实的 std::condition_variable_any】开友元。我们那个头第 17 行
#  `#include <mutex>` 拉进来的是微软的真 <mutex>，于是我们的类碰到了人家的私有成员：
#      error: '_Mymtx' 是 'std::_Mutex_base' 的私有成员
#  这是方案 §3.6 那个 friend 问题的【反向形态】：不是"我的 friend 指不到对方"，
#  而是"我引用了别人家的类型，人家的 friend 不认识我"。
#  修法：让它包含【我们自己的】<互斥量> —— 那一份里的 friend 已经跟着改成了
#  `friend 条件变量任意实现;`，两边同处 标准::细节，友元自然对上。
#
#  ⚠ 只对【已经抄完并通过验证】的头开这个开关（否则会 include 到不存在的文件）。
#     所以这是按条目选择的 `zhIncludes` 表，不是全局替换。
# ---------------------------------------------------------------------------
if ($spec.zhIncludes) {
    foreach ($en in @($spec.zhIncludes.Keys)) {
        $zhInc = $spec.zhIncludes[$en]
        $before0 = $text
        $text = $text.Replace("#include <$en>", "#include <$zhInc>")
        if ($text -ne $before0) {
            Write-Host "  步0 包含改名 <$en> -> <$zhInc>"
        } else {
            Write-Host "  步0 ⚠ 未找到 #include <$en>" -ForegroundColor Yellow
        }
    }
}

# 步 1：换守卫
$gm = [regex]::Match($text, '(?m)^#ifndef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\r?\n#define\s+\1\b')
if ($gm.Success) {
    $g = $gm.Groups[1].Value
    $ng = '_ZH_' + ($spec.zh)
    $ng = '_ZH_' + ($Header.ToUpper() -replace '[^A-Z0-9]', '_') + '_'
    $text = $text.Replace("#ifndef $g", "#ifndef $ng").Replace("#define $g", "#define $ng")
    Write-Host "  步1 守卫 $g -> $ng"
}

# 步 2：搬名域
$text = $text.Replace('_STD_BEGIN', "名域 标准 { 名域 细节 {`n使用 名域 std;")
$text = $text.Replace('_STD_END', '} }')
Write-Host "  步2 名域 -> 标准::细节 + 使用 名域 std;"

# 步 3/4：类型名、成员名、数据成员名（按 \b 边界，逐条替换）
$nT = 0; $nM = 0; $nD = 0
foreach ($k in $spec.types.Keys)   { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.types[$k]); $nT += $c } }
foreach ($k in $spec.members.Keys) { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.members[$k]); $nM += $c } }
foreach ($k in $spec.data.Keys)    { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.data[$k]); $nD += $c } }
Write-Host "  步3/4 类型 $nT 处 / 成员 $nM 处 / 数据 $nD 处"

# ---------------------------------------------------------------------------
#  步 4c：把 `_STD <本文件自己定义的东西>` 的限定去掉
#
#  `_STD` 展开成 `std::`。文件里有地方写 `_STD X` 来引用【它自己】定义的 X
#  （例：scoped_allocator 里的 `_STD _Scoped_outermost`）。本文件的内容已经搬进
#  `标准::细节`，X 就不在 `std` 里了 —— 于是报「namespace 'std' 中没有名为 X 的成员」。
#  这与 §3.3 记的 `cstddef` 的 `using _STD max_align_t` 那条"桥"是同一类问题。
#  修法：改名完成后，把 `_STD <改后的名字>` 还原成不带限定的 `<改后的名字>`。
# ---------------------------------------------------------------------------
$nq = 0
# ⚠ 只对【类型】【数据成员】【自由函数】去限定，绝不能对【成员函数名】去限定。
#   反例（实测踩到）：<stack> 里 `using _STD swap;` 是**故意**把 std::swap 拉进来供 ADL 用，
#   它不是"引用自己"。而我那张 members 表里也有 swap->交换，于是步 4c 把
#   `using _STD 交换;` 去限定成 `using 交换;` -> error: 使用 声明要求限定名。
#   判据：`_STD X` 只有在本文件【定义】了 X 时才该去限定。
#   细化（本轮实测）：`using` 开头的 `_STD X` 一律不动；其余位置 types/data/members 都去限定。
function Remove-StdQualifier {
    param([string]$Text, [string]$Name, [ref]$Count)
    $rx = '(?<!using )_STD ' + [regex]::Escape($Name) + '\b'
    $new = [regex]::Replace($Text, $rx, $Name)
    if ($new -ne $Text) { $Count.Value++ }
    return $new
}
foreach ($m in @($spec.types, $spec.data, $spec.members)) {
    foreach ($k in $m.Keys) {
        $text = Remove-StdQualifier -Text $text -Name $m[$k] -Count ([ref]$nq)
    }
}
# 本文件在名域作用域定义的 `_` 开头自由函数：改名后同样要被去限定。
# 不靠人肉登记（漏一个就报一次），直接从生成文本里扫出来。
$scanned = 0
foreach ($mm in [regex]::Matches($text, '(?m)^[^\r\n#]*?\b(_\w+)\s*\(')) {
    $nm = $mm.Groups[1].Value
    $before3 = $text
    $text = Remove-StdQualifier -Text $text -Name $nm -Count ([ref]$scanned)
    if ($text -eq $before3) { continue }
}
Write-Host "  步4c 去限定 `_STD <本文件的实体>`: $nq 个（另扫出内部函数 $scanned 个）"

# 步 6：派生层（在中文的基础上派生，补回英文原名）
$cls = ($spec.types.Values | Select-Object -First 1)   # 实现类名
$origType = ($spec.types.Keys | Select-Object -First 1) # 原本的类型名（供测试用）
# 头名与对外类名不一定相同（例：<条件变量> 里只有 condition_variable_any）
$pub = if ($spec.ContainsKey('pub')) { $spec.pub } else { $spec.zh }
$fwd = @()
foreach ($p in $spec.derive) {
    # 发两个转发：非 const 一个、const 一个。
    # 为什么两个都要：只发非 const 的话，const 对象上调用不到（实测
    # std::hash 特化里 _键.hash_code() 就是 const 引用，直接报"没有匹配的成员函数"）。
    # 两个并存不会歧义：非 const 对象上非 const 版更匹配；const 对象上只有 const 版可用。
    # 转发是模板，惰性实例化 —— 所以给非 const 成员也发一个 const 版是安全的。
    $fwd += ("    模板 <类型名... 参数> 自动 {0}(参数&&... 值) {{ 返回 基类::{1}(static_cast<参数&&>(值)...); }}" -f $p[0], $p[1])
    $fwd += ("    模板 <类型名... 参数> 自动 {0}(参数&&... 值) 常量 {{ 返回 基类::{1}(static_cast<参数&&>(值)...); }}" -f $p[0], $p[1])
}
$fwdT = @()
if ($spec.ContainsKey('deriveTypes')) {
    foreach ($p in $spec.deriveTypes) { $fwdT += ("    使用 {0} = 基类::{1};" -f $p[0], $p[1]) }
}
$hashSpec = if ($spec.stdHash) { @"

// std::hash 的特化必须挂在【对外那个类型】上（派生层之后），所以放在这里
名域 std {
    模板 <>
    结构 hash<标准::$pub> {
        _NODISCARD size_t operator()(常量 标准::$pub& _键) 常量 noexcept {
            返回 _键.hash_code();
        }
    };
}
"@ } else { '' }

# 额外要在 std 里补的特化（除 std::hash 之外的，按头给原始文本）
# 例：<stack> 的 std::uses_allocator / std::formatter 都要认识我们的类型。
if ($spec.ContainsKey('stdExtra')) {
    $hashSpec += "`n`n// 表里给的额外 std 特化 —— 这些 std 模板也必须认识我们的类型`n名域 std {`n$($spec.stdExtra)`n}"
}

$layer = @"


// ============================================================================
//  第二层：在【中文的基础上】派生，把英文原名补回来
//  · 第一层 标准::细节::$cls 是抄自微软的中文实现，成员名全中文
//  · 本层加回英文原名，所以两种名字在【同一个对象】上都能用
//  · 与微软的原类型并存：它是【另一个类型】，不碰 std 里的定义
// ============================================================================
名域 标准 {
$($spec.tparam.decl)
类型 $pub : 公开 细节::$cls$($spec.tparam.args) {
公开:
    使用 基类 = 细节::$cls$($spec.tparam.args);
    使用 基类::基类;

    // 嵌套类型名也要补回英文（数据成员不行 —— 那会改布局）
$($fwdT -join "`n")

    // 英文原名，一模板转发回中文名（不需要写签名，重载也自动跟过去）
$($fwd -join "`n")
};
}$hashSpec
"@
#$text = $text + $layer    # ← 派生层改到"编译器校对之后"再追加，见下
New-Item -ItemType Directory -Force $out | Out-Null
$outPath = Join-Path $out $spec.zh
[System.IO.File]::WriteAllText($outPath, $text, $utf8)
Write-Host ("  输出: {0}  ({1} 行)" -f $outPath, ([System.IO.File]::ReadAllLines($outPath)).Count)

# --- 编译器当改名校对 ---
$probe = Join-Path $env:TEMP ('zh2_' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.cpp')
[System.IO.File]::WriteAllText($probe, "#包含 <$($spec.zh)>`n整数 主函数(){ 返回 0; }`n", $utf8)
$rev = @{}
foreach ($k in $spec.members.Keys) { $rev[$spec.members[$k]] = $k }
foreach ($k in $spec.data.Keys)    { $rev[$spec.data[$k]] = $k }
for ($round = 1; $round -le 8; $round++) {
    $raw = & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -ferror-limit=0 -fsyntax-only `"$probe`" 2>&1"
    $hits = @()
    foreach ($l in @($raw)) {
        if ([string]$l -match "$($spec.zh)`:(\d+):(\d+): error: .*没有名为（成员名） '([^']+)' 的成员") {
            $hits += [pscustomobject]@{ Line=[int]$Matches[1]; Col=[int]$Matches[2]; Name=$Matches[3] }
        }
    }
    if ($hits.Count -eq 0) { Write-Host ("  校对第 {0} 轮: 无同名冲突" -f $round) -ForegroundColor Green; break }
    $lines = [System.IO.File]::ReadAllLines($outPath); $fixed = 0
    $doneLines = @{}
    foreach ($h in ($hits | Sort-Object Line,Col -Descending)) {
        if (-not $rev.ContainsKey($h.Name)) { continue }
        # 同一行一轮只改一处：坐标是按【改之前】那一行算的，改完长度就变了，
        # 同一行再改第二处会用错坐标（这也是坏掉派生层那个 bug 的成因之一）。
        # 剩下的下一轮再来，循环会兜住。
        if ($doneLines.ContainsKey($h.Line)) { continue }
        $idx = $h.Line - 1; $line = $lines[$idx]
        $lb = [System.Text.Encoding]::UTF8.GetBytes($line); $nb = [System.Text.Encoding]::UTF8.GetBytes($h.Name)
        $off = $h.Col - 1
        if ($off -lt 0 -or ($off + $nb.Length) -gt $lb.Length) { continue }
        $ok = $true; for ($i=0; $i -lt $nb.Length; $i++) { if ($lb[$off+$i] -ne $nb[$i]) { $ok=$false; break } }
        if (-not $ok) { continue }
        $ci = [System.Text.Encoding]::UTF8.GetString($lb,0,$off).Length
        $lines[$idx] = $line.Remove($ci,$h.Name.Length).Insert($ci,$rev[$h.Name]); $fixed++
        $doneLines[$h.Line] = $true
    }
    [System.IO.File]::WriteAllLines($outPath, $lines, $utf8)
    Write-Host ("  校对第 {0} 轮: 指出 {1} 处，改回英文 {2} 处" -f $round,$hits.Count,$fixed)
    if ($fixed -eq 0) { break }
}
Remove-Item $probe -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
#  派生层必须在【编译器校对之后】才追加。
#  为什么：校对是按编译器给的【字节坐标】直接改文件，如果派生层已经在那儿，
#  它的中文标识符会被误当冲突位置改坏 —— 实测把「到达令牌」改成了「到」「达」碎片。
# ---------------------------------------------------------------------------
# extra：原样追加在文件最末的代码。用途：一个头里有【多个对外类】时，
# 主类由上面的机制生成，其余类与自由函数在这里手写（如 <mutex> 有 8 个公开类）。
# 这样不必为多类重构整张表，现有条目一行都不用改。
$layerText = $layer
if ($spec.ContainsKey('extra')) { $layerText += "`n" + $spec.extra }
[System.IO.File]::AppendAllText($outPath, $layerText, $utf8)
Write-Host "  步6 派生层 + 英文转发 $($spec.derive.Count) 条$(if ($spec.deriveTypes) { " + 嵌套类型 $($spec.deriveTypes.Count) 条" })$(if ($spec.stdHash) { ' + std::hash 特化' })"

# --- 最终验证：中文名 / 英文名 / 与 std 并存 ---
Write-Host ""
Write-Host "=== 验证 ===" -ForegroundColor Cyan
$t = Join-Path $root 'build\_zh2'
if (Test-Path $t) { Remove-Item -Recurse -Force $t }
New-Item -ItemType Directory -Force $t | Out-Null
$cases = $spec.tests
$pass = 0
foreach ($c in $cases) {
    $src = Join-Path $t 't.cpp'
    [System.IO.File]::WriteAllText($src, $c[1] + "`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -fsyntax-only `"$src`" > `"$t\o.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { Write-Host ("  [ok]   {0}" -f $c[0]); $pass++ }
    else {
        Write-Host ("  [FAIL] {0}" -f $c[0]) -ForegroundColor Yellow
        Get-Content "$t\o.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' } |
            Select-Object -First 3 | ForEach-Object { Write-Host ("         " + ([string]$_).Trim()) }
    }
}
Write-Host ("  {0} / {1}" -f $pass, $cases.Count)
Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
