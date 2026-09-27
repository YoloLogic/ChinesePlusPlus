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
  'shared_mutex' = @{
    zh      = '共享互斥量'
    # ⚠ types 的【第一个】= 派生层的基类（生成器 $cls = types.Values | Select -First 1）
    types   = [ordered]@{
      'shared_mutex'          = '共享互斥量实现'
      'shared_timed_mutex'    = '限时共享互斥量实现'
      'shared_lock'           = '共享锁实现'
      # 跨头类型名：这几个译名是 <互斥量> / <条件变量> 定下的（方案 §3.8.2）
      'mutex'                 = '互斥量实现'
      '_Mutex_base'           = '_互斥量基类'
      'lock_guard'            = '锁守卫实现'
      'unique_lock'           = '独占锁实现'
      'condition_variable'    = '条件变量实现'
      # 三个 tag 类型也定义在 <mutex> 里
      'adopt_lock_t'          = '接管锁类型'
      'defer_lock_t'          = '延迟锁类型'
      'try_to_lock_t'         = '尝试锁类型'
    }
    # 已经抄完的头才开（步 0，见 §3.8.1）
    zhIncludes = @{ 'mutex' = '互斥量'; 'condition_variable' = '条件变量' }
    members = [ordered]@{
      'lock' = '加锁'; 'unlock' = '解锁'; 'try_lock' = '尝试加锁'
      'lock_shared' = '共享加锁'; 'unlock_shared' = '共享解锁'
      'try_lock_shared' = '尝试共享加锁'
      'try_lock_for' = '限时加锁'; 'try_lock_until' = '加锁至时刻'
      'try_lock_shared_for' = '限时共享加锁'; 'try_lock_shared_until' = '共享加锁至时刻'
      'owns_lock' = '持有锁'; 'release' = '释放'; 'swap' = '交换'
    }
    # ⚠ `shared_lock::mutex()` 这个取值函数名和类型名 `mutex` 撞车：
    #   types 表先跑，`mutex` 已被改成 `互斥量实现`，所以它读作 互斥量实现()。
    #   与 <互斥量> 里 `unique_lock::mutex()` 是同一个妥协（方案 §六）。
    data    = [ordered]@{}
    derive  = @( @('lock','加锁'), @('unlock','解锁'), @('try_lock','尝试加锁'),
                 @('lock_shared','共享加锁'), @('unlock_shared','共享解锁'),
                 @('try_lock_shared','尝试共享加锁') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    extra = @'

名域 标准 {

// 限时共享互斥量（std::shared_timed_mutex）
类型 限时共享互斥量 : 公开 细节::限时共享互斥量实现 {
公开:
    使用 基类 = 细节::限时共享互斥量实现;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 lock(参数&&... 值) { 返回 基类::加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 unlock(参数&&... 值) { 返回 基类::解锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock(参数&&... 值) { 返回 基类::尝试加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 lock_shared(参数&&... 值) { 返回 基类::共享加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 unlock_shared(参数&&... 值) { 返回 基类::共享解锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock_shared(参数&&... 值) { 返回 基类::尝试共享加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock_for(参数&&... 值) { 返回 基类::限时加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock_until(参数&&... 值) { 返回 基类::加锁至时刻(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock_shared_for(参数&&... 值) { 返回 基类::限时共享加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock_shared_until(参数&&... 值) { 返回 基类::共享加锁至时刻(static_cast<参数&&>(值)...); }
};

// 共享锁（std::shared_lock）
模板 <类型名 互斥类型>
类型 共享锁 : 公开 细节::共享锁实现<互斥类型> {
公开:
    使用 基类 = 细节::共享锁实现<互斥类型>;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 lock(参数&&... 值) { 返回 基类::加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock(参数&&... 值) { 返回 基类::尝试加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 unlock(参数&&... 值) { 返回 基类::解锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 lock_shared(参数&&... 值) { 返回 基类::共享加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 try_lock_shared(参数&&... 值) { 返回 基类::尝试共享加锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 unlock_shared(参数&&... 值) { 返回 基类::共享解锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 owns_lock(参数&&... 值) 常量 { 返回 基类::持有锁(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 release(参数&&... 值) { 返回 基类::释放(static_cast<参数&&>(值)...); }
};

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <共享互斥量>`n整数 主函数(){ 标准::共享互斥量 甲; 甲.加锁(); 甲.共享加锁(); 甲.共享解锁(); 甲.解锁(); 返回 0; }'),
      @('与微软原头并存','#包含 <共享互斥量>`n#包含 <shared_mutex>`n整数 主函数(){ 标准::共享互斥量 甲; 甲.加锁(); std::shared_mutex 乙; 乙.lock(); 返回 0; }'),
      @('英文名与中文名并用 + 共享锁','#包含 <共享互斥量>`n整数 主函数(){ 标准::共享互斥量 甲; 标准::共享锁<标准::共享互斥量> 锁(甲); 布尔 有 = 锁.持有锁(); 锁.lock_shared(); 锁.unlock_shared(); 返回 (整数)有 - 1; }'),
      @('限时共享互斥量','#包含 <共享互斥量>`n整数 主函数(){ 标准::限时共享互斥量 甲; 甲.加锁(); 甲.共享加锁(); 布尔 好 = 甲.尝试共享加锁(); if (好) 甲.共享解锁(); 甲.解锁(); 返回 0; }')
    )
  }
  'stop_token' = @{
    zh      = '停止令牌'
    # types 第一个 = 派生层基类（= 对外主类型）
    types   = [ordered]@{
      'stop_token'           = '停止令牌实现'
      'stop_source'          = '停止源实现'
      'stop_callback'        = '停止回调实现'
      'nostopstate_t'        = '无停止状态类型'
      '_Stop_state'          = '_停止状态'
      '_Stop_callback_base'  = '_停止回调基类'
    }
    members = [ordered]@{
      'request_stop'   = '请求停止'
      'stop_requested' = '已请求停止'
      'stop_possible'  = '可停止'
      'get_token'      = '取令牌'
      # ⚠ `swap` 故意【不】改名（实测踩到）：
      #   原文 `_STD swap(_State, _Other._State)` 要的是 std::swap（交换内部指针）。
      #   一旦把 swap 改成 交换，步 4c 会把 `_STD 交换(...)` 去限定成 `交换(...)`，
      #   于是它解析到【同名的成员函数】交换(停止令牌实现&)，报
      #     "函数调用使用的实参太多；只应给出单个实参" / "调用非静态成员函数时没有对象实参"。
      #   判据：成员名出现在 `_STD X(...)` 里、而那个 X 本意是 std 的自由函数时，不能改名。
      # 内部件（同头自用，各自独立于公开名）
      '_Request_stop'   = '_请求停止'
      '_Stop_requested' = '_已请求停止'
      '_Stop_possible'  = '_可停止'
    }
    data    = [ordered]@{}
    # ⚠ swap 不放进来：它是类内定义的 friend 自由函数，只能靠 ADL 找到，
    #   `基类::交换` 这种限定查找找不到它（生成器的转发用的是限定查找）。
    #   这与 <mutex>/<条件变量>/<共享互斥量> 的 derive 表一致（都没放 swap）。
    derive  = @( @('stop_requested','已请求停止'), @('stop_possible','可停止') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    extra = @'

名域 标准 {

// 顶层 tag 类型也要能在 标准 里直接写（成员转发机制只管类里的嵌套名）
使用 无停止状态类型 = 细节::无停止状态类型;

// 无停止状态（std::nostopstate）—— 它是个全局常量，不是类成员，所以手写
内联 常量表达式 无停止状态类型 无停止状态{};

// 停止源（std::stop_source）
类型 停止源 : 公开 细节::停止源实现 {
公开:
    使用 基类 = 细节::停止源实现;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 request_stop(参数&&... 值) { 返回 基类::请求停止(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 get_token(参数&&... 值) { 返回 基类::取令牌(static_cast<参数&&>(值)...); }
};

// 停止回调（std::stop_callback）
模板 <类型名 回调类型>
类型 停止回调 : 公开 细节::停止回调实现<回调类型> {
公开:
    使用 基类 = 细节::停止回调实现<回调类型>;
    使用 基类::基类;
};

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <停止令牌>`n整数 主函数(){ 标准::停止源 源; 标准::停止令牌 令 = 源.取令牌(); 布尔 好 = 令.可停止(); 源.请求停止(); 返回 (整数)好 - 1; }'),
      @('与微软原头并存','#包含 <停止令牌>`n#包含 <stop_token>`n整数 主函数(){ 标准::停止源 源; 源.请求停止(); std::stop_source 乙; 乙.request_stop(); 返回 0; }'),
      @('英文名与中文名并用','#包含 <停止令牌>`n整数 主函数(){ 标准::停止源 源; 标准::停止令牌 令 = 源.get_token(); 源.request_stop(); 布尔 好 = 令.stop_requested(); 返回 (整数)好 - 1; }'),
      @('停止回调 + 无停止状态','#包含 <停止令牌>`n结构 回调器 { 空型 operator()() {} };`n整数 主函数(){ 标准::停止源 空源(标准::无停止状态); 标准::停止源 源; 标准::停止回调<回调器> 回(源.取令牌(), 回调器{}); 源.请求停止(); 返回 0; }')
    )
  }
  'thread' = @{
    zh      = '线程'
    # types 第一个 = 派生层基类
    types   = [ordered]@{
      'thread'       = '线程实现'
      'jthread'      = '可停线程实现'
      # 嵌套名域 this_thread 也是标识符，照样改名；派生层里用 名域 本线程 补英文
      'this_thread'  = '本线程'
      # 跨头类型名（<停止令牌> 定下的译名）
      'stop_token'   = '停止令牌实现'
      'stop_source'  = '停止源实现'
    }
    zhIncludes = @{ 'stop_token' = '停止令牌' }
    members = [ordered]@{
      'join' = '汇合'; 'detach' = '分离'; 'joinable' = '可汇合'
      'get_id' = '取标识'; 'native_handle' = '原生句柄'
      'hardware_concurrency' = '硬件并发数'
      'yield' = '让出'
      'sleep_for' = '睡眠时长'; 'sleep_until' = '睡至时刻'
      'get_stop_source' = '取停止源'; 'get_stop_token' = '取停止令牌'
      # 跨头成员名：<停止令牌> 已定 请求停止 / 取令牌（跨头译名检查会强制一致）
      'request_stop' = '请求停止'
      'get_token'    = '取令牌'
    }
    # ⚠ 同样不放 swap（§3.12：类内 friend + `_STD swap` 调用形态，不能改名）
    data    = [ordered]@{}
    derive  = @( @('join','汇合'), @('detach','分离'), @('joinable','可汇合'),
                 @('get_id','取标识'), @('hardware_concurrency','硬件并发数') )
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    extra = @'

名域 标准 {

// 可停线程（std::jthread）
类型 可停线程 : 公开 细节::可停线程实现 {
公开:
    使用 基类 = 细节::可停线程实现;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 join(参数&&... 值) { 返回 基类::汇合(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 detach(参数&&... 值) { 返回 基类::分离(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 joinable(参数&&... 值) 常量 { 返回 基类::可汇合(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 get_id(参数&&... 值) 常量 { 返回 基类::取标识(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 request_stop(参数&&... 值) { 返回 基类::请求停止(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 get_stop_source(参数&&... 值) { 返回 基类::取停止源(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 get_stop_token(参数&&... 值) 常量 { 返回 基类::取停止令牌(static_cast<参数&&>(值)...); }
};

// 本线程（std::this_thread）—— 名域里的自由函数，成员转发机制管不到，手写
名域 本线程 {
    模板 <类型名... 参数> 自动 get_id(参数&&... 值) { 返回 细节::本线程::取标识(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 yield(参数&&... 值) { 返回 细节::本线程::让出(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 sleep_for(参数&&... 值) { 返回 细节::本线程::睡眠时长(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 sleep_until(参数&&... 值) { 返回 细节::本线程::睡至时刻(static_cast<参数&&>(值)...); }
}

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <线程>`n整数 主函数(){ 标准::线程 甲([]{}); 布尔 可 = 甲.可汇合(); 甲.汇合(); 返回 (整数)可 - 1; }'),
      @('与微软原头并存','#包含 <线程>`n#包含 <thread>`n整数 主函数(){ 标准::线程 甲([]{ }); 甲.join(); std::thread 乙([]{ }); 乙.join(); 返回 0; }'),
      @('英文名与中文名并用 + 可停线程','#包含 <线程>`n整数 主函数(){ 标准::线程 甲([]{ }); 布尔 可 = 甲.joinable(); 甲.join(); 标准::可停线程 乙([]{ }); 乙.request_stop(); 乙.join(); 返回 (整数)可 - 1; }'),
      @('本线程名域','#包含 <线程>`n整数 主函数(){ 标准::本线程::让出(); 标准::本线程::yield(); 标准::线程::id 标 = 标准::本线程::取标识(); (空型)标; 返回 0; }')
    )
  }
  'bitset' = @{
    zh      = '位集'
    # types 第一个 = 派生层基类
    # ⚠ 嵌套代理类 `bitset::reference` 【不改名】：`reference` 太通用，
    #   全局 \breference\b 替换不安全（同 §3.13 的 thread::id，§六第 8 条）。
    #   它跟着派生一起继承，所以 标准::位集<8>::reference 照样能写。
    types   = [ordered]@{ 'bitset' = '位集实现' }
    members = [ordered]@{
      'set' = '置位'; 'reset' = '复位'; 'flip' = '翻转'; 'test' = '测试'
      'count' = '计数'; 'size' = '尺寸'
      'all' = '全为真'; 'any' = '有真'; 'none' = '全为假'
      'to_string' = '转字符串'; 'to_ulong' = '转无符号长'; 'to_ullong' = '转无符号长长'
    }
    data    = [ordered]@{}
    derive  = @( @('set','置位'), @('reset','复位'), @('flip','翻转'), @('test','测试'),
                 @('count','计数'), @('size','尺寸'), @('all','全为真'), @('any','有真'),
                 @('none','全为假'), @('to_string','转字符串'),
                 @('to_ulong','转无符号长'), @('to_ullong','转无符号长长') )
    stdHash = $false
    # ⚠ bitset 是【类模板】，且是【非类型参数】模板 <size_t _Bits>。
    #   tparam 漏了的话派生层会写成 `类型 位集 : 公开 细节::位集实现 {`，报
    #   「使用类模板 '细节::位集实现' 需要模板实参」/「缺少类名」/「未声明的标识符 '基类'」。
    tparam  = @{ decl = '模板 <size_t 位数>'; args = '<位数>' }
    # ⚠ 原头里的 hash<bitset<_Bits>> 特化挂在【抄来那层】的类型上（细节::位集实现）。
    #   而对外类型 标准::位集 是【派生出来的另一个类模板】—— 按 §3.13 的判据
    #   （模板参数是不是"对外类型本身"）这里必须【重发一份】，
    #   否则 unordered_set<标准::位集<8>> 找不到 hash。
    stdExtra = '模板 <size_t 位数>
    结构 hash<标准::位集<位数>> : hash<标准::细节::位集实现<位数>> {};'
    tests = @(
      @('只引中文头','#包含 <位集>`n整数 主函数(){ 标准::位集<8> 甲; 甲.置位(1); 布尔 有 = 甲.测试(1); 甲.复位(1); 甲.翻转(); 返回 (有 && 甲.计数() == 8) ? 0 : 1; }'),
      @('与微软原头并存','#包含 <位集>`n#包含 <bitset>`n整数 主函数(){ 标准::位集<8> 甲(""1010""); std::bitset<8> 乙(""1010""); 返回 (整数)甲.计数() - (整数)乙.count(); }'),
      @('英文名与中文名并用 + 转字符串','#包含 <位集>`n整数 主函数(){ 标准::位集<4> 甲; 甲.set(0); 甲.set(1); 自动 串 = 甲.to_string(); 自动 串2 = 甲.转字符串(); 返回 (串.size() == 4 && 串2.size() == 4) ? 0 : 1; }'),
      @('位运算 + std::hash 特化必须认识对外类型','#包含 <位集>`n整数 主函数(){ 标准::位集<8> 甲(""1100""); 标准::位集<8> 乙(""0110""); 自动 丙 = 甲 | 乙; std::hash<标准::位集<8>> 哈; 返回 (丙.计数() == 3 && 哈(甲) == 哈(甲)) ? 0 : 1; }')
    )
  }
  'set' = @{
    zh      = '集合'
    # ⚠ <set> 的 API 几乎【全部继承自借用的 _Tree】（在 <xtree> 里，我们没翻），
    #   所以这个头自己定义的成员只有 ctor / emplace / swap。
    #   -> 中文名不能靠 members 表改名（那些名字根本不在本文件里），
    #      只能在 extra 里【手写中文转发】调基类的英文名。
    #      这是第一种"手写层加中文名（而不是加英文名）"的用法，见方案 §3.16。
    types   = [ordered]@{ 'set' = '集合实现'
                          'multiset' = '多重集合实现'
                          '_Tset_traits' = '_集合特征' }
    members = [ordered]@{ 'emplace' = '就地构造' }
    data    = [ordered]@{}
    derive  = @( @('emplace','就地构造') )
    # 嵌套类型名：iterator 等继承自 _Tree，派生类自动带上英文名；
    # 这里补中文名（deriveTypes 就是往派生类里写 `使用 中文 = 基类::英文;`）
    deriveTypes = @( @('迭代器','iterator'), @('常量迭代器','const_iterator'),
                     @('键类型','key_type'), @('尺寸类型','size_type') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 键, 类型名 比较 = std::less<键>, 类型名 分配器 = std::allocator<键>>'; args = '<键, 比较, 分配器>' }
    extra = @'

名域 标准 {

// 多重集合（std::multiset）
模板 <类型名 键, 类型名 比较 = std::less<键>, 类型名 分配器 = std::allocator<键>>
类型 多重集合 : 公开 细节::多重集合实现<键, 比较, 分配器> {
公开:
    使用 基类 = 细节::多重集合实现<键, 比较, 分配器>;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 插入(参数&&... 值) { 返回 基类::insert(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 擦除(参数&&... 值) { 返回 基类::erase(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 查找(参数&&... 值) { 返回 基类::find(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 计数(参数&&... 值) 常量 { 返回 基类::count(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 尺寸(参数&&... 值) 常量 { 返回 基类::size(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 为空(参数&&... 值) 常量 { 返回 基类::empty(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 清空(参数&&... 值) { 返回 基类::clear(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 开始(参数&&... 值) { 返回 基类::begin(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 结束(参数&&... 值) { 返回 基类::end(static_cast<参数&&>(值)...); }
};

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <集合>`n整数 主函数(){ 标准::集合<整数> 甲; 甲.插入(1); 甲.插入(2); 返回 甲.计数(1) == 1 ? 0 : 1; }'),
      @('与微软原头并存','#包含 <集合>`n#包含 <set>`n整数 主函数(){ 标准::集合<整数> 甲; 甲.insert(1); std::set<int> 乙; 乙.insert(1); 返回 (整数)甲.尺寸() - (整数)乙.size(); }'),
      @('中英并用 + 中文迭代器名','#包含 <集合>`n整数 主函数(){ 标准::集合<整数> 甲; 甲.插入(3); 甲.插入(1); 标准::集合<整数>::迭代器 头 = 甲.开始(); 整数 和 = 0; for (; 头 != 甲.结束(); ++头) { 和 += *头; } 返回 和 - 4; }'),
      @('多重集合','#包含 <集合>`n整数 主函数(){ 标准::多重集合<整数> 甲; 甲.插入(1); 甲.插入(1); 返回 (整数)甲.计数(1) - 2; }')
    )
  }
  'map' = @{
    zh      = '映射'
    types   = [ordered]@{ 'map' = '映射实现'
                          'multimap' = '多重映射实现'
                          '_Tmap_traits' = '_映射特征'
                          'value_compare' = '值比较器' }
    members = [ordered]@{
      # at/insert/... 是 <map> 自己定义的（能改名）
      'at' = '取值'; 'insert' = '插入'
      'insert_or_assign' = '插入或赋值'; 'try_emplace' = '尝试就地构造'
      # emplace 必须与 <栈>/<集合> 一致（跨头译名检查会强制）
      'emplace' = '就地构造'
    }
    data    = [ordered]@{}
    derive  = @( @('at','取值'), @('insert','插入'), @('insert_or_assign','插入或赋值'),
                 @('try_emplace','尝试就地构造'), @('emplace','就地构造') )
    deriveTypes = @( @('迭代器','iterator'), @('常量迭代器','const_iterator'),
                     @('键类型','key_type'), @('映射类型','mapped_type'),
                     @('值类型','value_type'), @('尺寸类型','size_type') )
    # 中文转发：这些 API 在 <xtree> 里（借用），本文件改名改不到（方案 §3.16）
    deriveExtra = @'
    模板 <类型名... 参数> 自动 擦除(参数&&... 值) { 返回 基类::erase(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 查找(参数&&... 值) { 返回 基类::find(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 计数(参数&&... 值) 常量 { 返回 基类::count(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 尺寸(参数&&... 值) 常量 { 返回 基类::size(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 为空(参数&&... 值) 常量 { 返回 基类::empty(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 清空(参数&&... 值) { 返回 基类::clear(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 包含(参数&&... 值) 常量 { 返回 基类::contains(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 开始(参数&&... 值) { 返回 基类::begin(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 结束(参数&&... 值) { 返回 基类::end(static_cast<参数&&>(值)...); }
'@
    stdHash = $false
    # ⚠ 模板参数名【不能和类名同名】：参数叫 映射 会遮蔽类模板 映射，类型 映射 : ... 报
    #   「使用类模板 '映射' 需要模板实参」。故参数叫 映射值。
    tparam  = @{ decl = '模板 <类型名 键, 类型名 映射值, 类型名 比较 = std::less<键>, 类型名 分配器 = std::allocator<std::pair<常量 键, 映射值>>>'; args = '<键, 映射值, 比较, 分配器>' }
    extra = @'

名域 标准 {

// 多重映射（std::multimap）
模板 <类型名 键, 类型名 映射值, 类型名 比较 = std::less<键>,
      类型名 分配器 = std::allocator<std::pair<常量 键, 映射值>>>
类型 多重映射 : 公开 细节::多重映射实现<键, 映射值, 比较, 分配器> {
公开:
    使用 基类 = 细节::多重映射实现<键, 映射值, 比较, 分配器>;
    使用 基类::基类;
    模板 <类型名... 参数> 自动 插入(参数&&... 值) { 返回 基类::插入(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 擦除(参数&&... 值) { 返回 基类::erase(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 查找(参数&&... 值) { 返回 基类::find(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 计数(参数&&... 值) 常量 { 返回 基类::count(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 尺寸(参数&&... 值) 常量 { 返回 基类::size(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 为空(参数&&... 值) 常量 { 返回 基类::empty(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 清空(参数&&... 值) { 返回 基类::clear(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 开始(参数&&... 值) { 返回 基类::begin(static_cast<参数&&>(值)...); }
    模板 <类型名... 参数> 自动 结束(参数&&... 值) { 返回 基类::end(static_cast<参数&&>(值)...); }
};

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <映射>`n整数 主函数(){ 标准::映射<整数, 整数> 甲; 甲.插入({1, 2}); 甲[3] = 4; 返回 甲.取值(1) + 甲.尺寸() - 3; }'),
      @('与微软原头并存','#包含 <映射>`n#包含 <map>`n整数 主函数(){ 标准::映射<整数, 整数> 甲; 甲[1] = 2; std::map<int, int> 乙; 乙[1] = 2; 返回 (整数)甲.尺寸() - (整数)乙.size(); }'),
      @('中英并用 + 中文迭代器','#包含 <映射>`n整数 主函数(){ 标准::映射<整数, 整数> 甲; 甲.insert({1, 10}); 甲.insert({2, 20}); 标准::映射<整数, 整数>::迭代器 头 = 甲.开始(); 整数 和 = 0; for (; 头 != 甲.结束(); ++头) { 和 += 头->second; } 返回 和 - 30; }'),
      @('多重映射 + 就地构造','#包含 <映射>`n整数 主函数(){ 标准::多重映射<整数, 整数> 甲; 甲.插入({1, 1}); 甲.插入({1, 2}); 标准::映射<整数, 整数> 乙; 乙.try_emplace(5, 6); 返回 (整数)甲.计数(1) + (整数)乙.尺寸() - 3; }')
    )
  }
  'optional' = @{
    zh      = '可选'
    types   = [ordered]@{ 'optional' = '可选实现'
                          'nullopt_t' = '空值类型' }
    # 步 0b：把【真 <optional>】也包含进来 —— 为了让 std::bad_optional_access 真的存在。
    # 抄来的那份异常类定义要删掉（dropTypes），否则 _Throw_bad_optional_access()
    # 抛的是我们抄的那个类，用户 catch (std::bad_optional_access&) 永远抓不到。
    # 值类型 optional 可以抄+派生（能有中文成员名），异常类型只能别名 —— 铁律 4。
    realInclude = @('optional')
    dropTypes   = @('bad_optional_access')
    members = [ordered]@{
      'has_value' = '有值'; 'value' = '取值'; 'value_or' = '取值或'
      'reset' = '重置'; 'emplace' = '就地构造'
      'and_then' = '且则'; 'transform' = '变换'; 'or_else' = '或则'
      # ⚠ swap 照旧不改名（§3.12）
    }
    data    = [ordered]@{}
    derive  = @( @('has_value','有值'), @('value','取值'), @('value_or','取值或'),
                 @('reset','重置'), @('emplace','就地构造'),
                 @('and_then','且则'), @('transform','变换'), @('or_else','或则') )
    deriveTypes = @( @('值类型','value_type') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 值>'; args = '<值>' }
    extra = @'

名域 标准 {

// 坏可选访问异常（std::bad_optional_access）—— 只能是 std 的那个（铁律 4）
使用 坏可选访问 = std::bad_optional_access;

// 顶层 tag 类型也要能在 标准 里写
使用 空值类型 = 细节::空值类型;

// 无值（std::nullopt）—— 全局常量，成员转发管不到，手写
// ⚠ MSVC 的 nullopt_t 取的是嵌套的 _Tag，不是 int（我照 cppreference 写 {42} 是错的）：
//     struct nullopt_t { struct _Tag {}; constexpr explicit nullopt_t(_Tag) {} };
内联 常量表达式 空值类型 无值{细节::空值类型::_Tag{}};

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <可选>`n整数 主函数(){ 标准::可选<整数> 甲; 布尔 有 = 甲.有值(); 甲 = 5; 返回 (有 ? 1 : 0) + 甲.取值() - 5; }'),
      @('异常必须是同一个类型（与 <optional> 并存）','#包含 <可选>`n#包含 <optional>`n静态断言(std::is_same<标准::坏可选访问, std::bad_optional_access>::value, "");`n整数 主函数(){ 标准::可选<整数> 甲; 尝试 { (空型)甲.取值(); } 捕获 (常量 std::bad_optional_access&) { std::optional<int> 乙; 乙 = 3; 返回 乙.value() - 3; } 返回 1; }'),
      @('无值 / 就地构造 / 取值或','#包含 <可选>`n整数 主函数(){ 标准::可选<整数> 甲(标准::无值); 甲.就地构造(7); 整数 值 = 甲.取值或(0); 甲.重置(); 返回 (整数)甲.有值() + 值 - 7; }'),
      @('英文名与中文名并用','#包含 <可选>`n整数 主函数(){ 标准::可选<整数> 甲(9); 布尔 有 = 甲.has_value(); 整数 值 = 甲.value(); 返回 (有 ? 值 : 0) - 9; }')
    )
  }
  'any' = @{
    zh      = '任意'
    types   = [ordered]@{ 'any' = '任意实现' }
    # 步 0b：真头 + 丢掉抄来的异常类（铁律 4，见 §3.18）
    realInclude = @('any')
    dropTypes   = @('bad_any_cast')
    members = [ordered]@{
      'reset' = '重置'; 'has_value' = '有值'
      # ⚠ `类型` 是关键词（class），所以 type() 不能叫「类型」
      'type' = '所属类型'; 'emplace' = '就地构造'
      # 自由函数也在这里改名：抄来后它们落在 细节::，靠 extra 里的
      # `使用 细节::中文名;` 引进 标准（using 声明比重写转发保真：
      # 重载全带上、返回引用也不丢 —— 泛型转发用 auto 会把 T& 退化成 T）
      'any_cast' = '任意转换'; 'make_any' = '造任意'
      # ⚠ swap 照旧不改名（§3.12）
    }
    data    = [ordered]@{}
    derive  = @( @('reset','重置'), @('has_value','有值'),
                 @('type','所属类型'), @('emplace','就地构造') )
    deriveExtra = @'
    // 让【抄来那层】的自由函数返回值能直接用：
    // make_any 返回 细节::任意实现，而对外类型是派生出来的 标准::任意。
    // 派生类没有"从基类回来"的路，所以手写一个接管构造。
    任意(细节::任意实现&& 内) noexcept : 基类(static_cast<细节::任意实现&&>(内)) {}
'@
    stdHash = $false
    tparam  = @{ decl = ''; args = '' }
    extra = @'

名域 标准 {

// 坏任意转换异常（std::bad_any_cast）—— 只能是 std 的那个（铁律 4）
使用 坏任意转换 = std::bad_any_cast;

// 自由函数：抄来后落在 细节::，这里用 using 声明引进 标准::
// （比重写转发保真：重载全带上、返回引用也不丢）
使用 细节::任意转换;
使用 细节::造任意;

}  // 名域 标准
'@
    tests = @(
      @('只引中文头','#包含 <任意>`n整数 主函数(){ 标准::任意 甲 = 5; 布尔 有 = 甲.有值(); 整数 值 = 标准::任意转换<整数>(甲); 返回 (有 ? 值 : 0) - 5; }'),
      @('异常必须是同一个类型（与 <any> 并存）','#包含 <任意>`n#包含 <any>`n静态断言(std::is_same<标准::坏任意转换, std::bad_any_cast>::value, "");`n整数 主函数(){ 标准::任意 甲 = 1.5; 尝试 { (空型)标准::任意转换<整数>(甲); } 捕获 (常量 std::bad_any_cast&) { std::any 乙 = 2; 返回 (整数)std::any_cast<int>(乙) - 2; } 返回 1; }'),
      @('造任意 / 所属类型 / 接管构造','#包含 <任意>`n整数 主函数(){ 标准::任意 甲 = 标准::造任意<整数>(7); 常量 std::type_info& 信 = 甲.所属类型(); 整数 值 = 标准::任意转换<整数>(甲); 甲.重置(); 返回 (整数)甲.有值() + 值 + (信 == typeid(整数) ? 0 : 1) - 7; }'),
      @('英文名与中文名并用','#包含 <任意>`n整数 主函数(){ 标准::任意 甲 = 3; 布尔 有 = 甲.has_value(); 整数 值 = 标准::任意转换<整数>(甲); 返回 (有 ? 值 : 0) - 3; }')
    )
  }
  'deque' = @{
    zh      = '双端队列'
    types   = [ordered]@{ 'deque' = '双端队列实现' }
    # 迭代器类是【本文件自己定义的】（不像 set/map 借用 _Tree），
    # 故意不改名：它们是内部件，跟着派生一起继承即可（§2.2.1 的"内部件暂不翻"）。
    members = [ordered]@{
      'size' = '尺寸'; 'empty' = '为空'; 'max_size' = '最大尺寸'
      'begin' = '开始'; 'end' = '结束'
      'cbegin' = '常量开始'; 'cend' = '常量结束'
      'rbegin' = '反向开始'; 'rend' = '反向结束'
      'crbegin' = '常量反向开始'; 'crend' = '常量反向结束'
      'at' = '取值'; 'front' = '前'; 'back' = '后'
      'push_back' = '尾插'; 'push_front' = '头插'
      'pop_back' = '尾删'; 'pop_front' = '头删'
      'emplace' = '就地构造'; 'emplace_back' = '尾部就地构造'; 'emplace_front' = '头部就地构造'
      'insert' = '插入'; 'erase' = '擦除'; 'assign' = '赋值'
      'resize' = '调整尺寸'; 'shrink_to_fit' = '收缩至适应'
      'clear' = '清空'; 'get_allocator' = '取分配器'
      'append_range' = '追加范围'; 'prepend_range' = '前置范围'
      'assign_range' = '范围赋值'; 'insert_range' = '范围插入'
      # ⚠ swap 照旧不改名（§3.12）
    }
    data    = [ordered]@{}
    derive  = @( @('size','尺寸'), @('empty','为空'), @('max_size','最大尺寸'),
                 @('begin','开始'), @('end','结束'),
                 @('at','取值'), @('front','前'), @('back','后'),
                 @('push_back','尾插'), @('push_front','头插'),
                 @('pop_back','尾删'), @('pop_front','头删'),
                 @('emplace','就地构造'), @('emplace_back','尾部就地构造'),
                 @('emplace_front','头部就地构造'),
                 @('insert','插入'), @('erase','擦除'), @('assign','赋值'),
                 @('resize','调整尺寸'), @('shrink_to_fit','收缩至适应'),
                 @('clear','清空'), @('get_allocator','取分配器') )
    deriveTypes = @( @('迭代器','iterator'), @('常量迭代器','const_iterator'),
                     @('反向迭代器','reverse_iterator'), @('常量反向迭代器','const_reverse_iterator'),
                     @('值类型','value_type'), @('尺寸类型','size_type') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 元素, 类型名 分配器 = std::allocator<元素>>'; args = '<元素, 分配器>' }
    tests = @(
      @('只引中文头','#包含 <双端队列>`n整数 主函数(){ 标准::双端队列<整数> 甲; 甲.尾插(1); 甲.头插(0); 甲.尾部就地构造(2); 返回 甲.取值(0) + (整数)甲.尺寸() - 3; }'),
      @('与微软原头并存','#包含 <双端队列>`n#包含 <deque>`n整数 主函数(){ 标准::双端队列<整数> 甲; 甲.push_back(1); std::deque<int> 乙; 乙.push_back(1); 返回 (整数)甲.尺寸() - (整数)乙.size(); }'),
      @('中英并用 + 中文迭代器名','#包含 <双端队列>`n整数 主函数(){ 标准::双端队列<整数> 甲; 甲.尾插(3); 甲.头插(1); 标准::双端队列<整数>::迭代器 头 = 甲.开始(); 整数 和 = 0; for (; 头 != 甲.结束(); ++头) { 和 += *头; } 返回 和 - 4; }'),
      @('擦除 / 插入 / 前后','#包含 <双端队列>`n整数 主函数(){ 标准::双端队列<整数> 甲; 甲.尾插(1); 甲.尾插(2); 甲.尾插(3); 甲.擦除(甲.开始()); 甲.插入(甲.开始(), 9); 返回 甲.前() + 甲.后() - 12; }')
    )
  }
  'list' = @{
    zh      = '链表'
    types   = [ordered]@{ 'list' = '链表实现' }
    members = [ordered]@{
      'size' = '尺寸'; 'empty' = '为空'; 'max_size' = '最大尺寸'
      'begin' = '开始'; 'end' = '结束'
      'cbegin' = '常量开始'; 'cend' = '常量结束'
      'rbegin' = '反向开始'; 'rend' = '反向结束'
      'crbegin' = '常量反向开始'; 'crend' = '常量反向结束'
      'front' = '前'; 'back' = '后'
      'push_back' = '尾插'; 'push_front' = '头插'
      'pop_back' = '尾删'; 'pop_front' = '头删'
      'emplace' = '就地构造'; 'emplace_back' = '尾部就地构造'; 'emplace_front' = '头部就地构造'
      'insert' = '插入'; 'erase' = '擦除'; 'assign' = '赋值'
      'resize' = '调整尺寸'; 'shrink_to_fit' = '收缩至适应'
      'clear' = '清空'; 'get_allocator' = '取分配器'
      'append_range' = '追加范围'; 'prepend_range' = '前置范围'
      'assign_range' = '范围赋值'; 'insert_range' = '范围插入'
      'sort' = '排序'; 'merge' = '归并'; 'splice' = '接合'
      'remove' = '移除'; 'remove_if' = '按条件移除'
      'unique' = '去重'; 'reverse' = '反转'
      # ⚠ swap 照旧不改名（§3.12）
    }
    data    = [ordered]@{}
    derive  = @( @('size','尺寸'), @('empty','为空'), @('max_size','最大尺寸'),
                 @('begin','开始'), @('end','结束'),
                 @('front','前'), @('back','后'),
                 @('push_back','尾插'), @('push_front','头插'),
                 @('pop_back','尾删'), @('pop_front','头删'),
                 @('emplace','就地构造'), @('emplace_back','尾部就地构造'),
                 @('emplace_front','头部就地构造'),
                 @('insert','插入'), @('erase','擦除'), @('assign','赋值'),
                 @('resize','调整尺寸'), @('shrink_to_fit','收缩至适应'),
                 @('clear','清空'), @('get_allocator','取分配器'),
                 @('sort','排序'), @('merge','归并'), @('splice','接合'),
                 @('remove','移除'), @('remove_if','按条件移除'),
                 @('unique','去重'), @('reverse','反转') )
    deriveTypes = @( @('迭代器','iterator'), @('常量迭代器','const_iterator'),
                     @('反向迭代器','reverse_iterator'), @('常量反向迭代器','const_reverse_iterator'),
                     @('值类型','value_type'), @('尺寸类型','size_type') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 元素, 类型名 分配器 = std::allocator<元素>>'; args = '<元素, 分配器>' }
    tests = @(
      @('只引中文头','#包含 <链表>`n整数 主函数(){ 标准::链表<整数> 甲; 甲.尾插(1); 甲.头插(0); 甲.尾部就地构造(2); 返回 甲.前() + (整数)甲.尺寸() - 3; }'),
      @('与微软原头并存','#包含 <链表>`n#包含 <list>`n整数 主函数(){ 标准::链表<整数> 甲; 甲.push_back(1); std::list<int> 乙; 乙.push_back(1); 返回 (整数)甲.尺寸() - (整数)乙.size(); }'),
      @('排序 / 去重 / 反转','#包含 <链表>`n整数 主函数(){ 标准::链表<整数> 甲; 甲.尾插(3); 甲.尾插(1); 甲.尾插(1); 甲.尾插(2); 甲.排序(); 甲.去重(); 甲.反转(); 返回 甲.前() + 甲.后() - 4; }'),
      @('中英并用 + 迭代器','#包含 <链表>`n整数 主函数(){ 标准::链表<整数> 甲; 甲.尾插(1); 甲.尾插(2); 标准::链表<整数>::迭代器 头 = 甲.开始(); 整数 和 = 0; for (; 头 != 甲.结束(); ++头) { 和 += *头; } 甲.erase(甲.begin()); 返回 和 + (整数)甲.尺寸() - 4; }')
    )
  }
  'vector' = @{
    zh      = '向量'
    types   = [ordered]@{ 'vector' = '向量实现' }
    # 迭代器类（_Vector_iterator / _Vb_iterator 等）都是本文件内部件，故意不改名。
    # vector<bool> 特化也定义在本文件里，同一个 types 改名会一起覆盖 ——
    # 于是 细节::向量实现<bool, 分配器> 自动指到那个特化，派生层不用特殊处理。
    members = [ordered]@{
      'size' = '尺寸'; 'empty' = '为空'; 'max_size' = '最大尺寸'
      'capacity' = '容量'; 'reserve' = '预留'; 'data' = '数据'
      'begin' = '开始'; 'end' = '结束'
      'cbegin' = '常量开始'; 'cend' = '常量结束'
      'rbegin' = '反向开始'; 'rend' = '反向结束'
      'crbegin' = '常量反向开始'; 'crend' = '常量反向结束'
      'at' = '取值'; 'front' = '前'; 'back' = '后'
      'push_back' = '尾插'; 'pop_back' = '尾删'
      'emplace' = '就地构造'; 'emplace_back' = '尾部就地构造'
      'insert' = '插入'; 'erase' = '擦除'; 'assign' = '赋值'
      'resize' = '调整尺寸'; 'shrink_to_fit' = '收缩至适应'
      'clear' = '清空'; 'get_allocator' = '取分配器'
      'append_range' = '追加范围'; 'assign_range' = '范围赋值'; 'insert_range' = '范围插入'
      # ⚠ swap 照旧不改名（§3.12）
    }
    data    = [ordered]@{}
    derive  = @( @('size','尺寸'), @('empty','为空'), @('max_size','最大尺寸'),
                 @('capacity','容量'), @('reserve','预留'), @('data','数据'),
                 @('begin','开始'), @('end','结束'),
                 @('at','取值'), @('front','前'), @('back','后'),
                 @('push_back','尾插'), @('pop_back','尾删'),
                 @('emplace','就地构造'), @('emplace_back','尾部就地构造'),
                 @('insert','插入'), @('erase','擦除'), @('assign','赋值'),
                 @('resize','调整尺寸'), @('shrink_to_fit','收缩至适应'),
                 @('clear','清空'), @('get_allocator','取分配器') )
    deriveTypes = @( @('迭代器','iterator'), @('常量迭代器','const_iterator'),
                     @('反向迭代器','reverse_iterator'), @('常量反向迭代器','const_reverse_iterator'),
                     @('值类型','value_type'), @('尺寸类型','size_type'),
                     @('引用','reference'), @('常量引用','const_reference') )
    stdHash = $false
    tparam  = @{ decl = '模板 <类型名 元素, 类型名 分配器 = std::allocator<元素>>'; args = '<元素, 分配器>' }
    tests = @(
      @('只引中文头','#包含 <向量>`n整数 主函数(){ 标准::向量<整数> 表; 表.尾插(1); 表.尾插(2); 表.尾部就地构造(3); 返回 表.前() + (整数)表.尺寸() - 4; }'),
      @('与微软原头并存','#包含 <向量>`n#包含 <vector>`n整数 主函数(){ 标准::向量<整数> 表; 表.push_back(1); std::vector<int> 乙; 乙.push_back(1); 返回 (整数)表.尺寸() - (整数)乙.size(); }'),
      @('中英并用 + 容量 / 预留 / 下标','#包含 <向量>`n整数 主函数(){ 标准::向量<整数> 表(3, 7); 表.reserve(10); 表[0] = 1; 整数 和 = 表[0] + 表.at(1); 布尔 够 = 表.容量() >= 10; 返回 和 + (够 ? 0 : 1) - 8; }'),
      @('迭代器 + vector<bool> 特化','#包含 <向量>`n整数 主函数(){ 标准::向量<bool> 位(3, true); 位.尾插(false); 整数 数 = 0; for (标准::向量<bool>::迭代器 头 = 位.开始(); 头 != 位.结束(); ++头) { if (*头) { ++数; } } 返回 数 - 3; }')
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

# ---------------------------------------------------------------------------
#  跨头译名一致性检查（方案 §3.6.1 / §3.8.2，为什么要有它）
#
#  现实：译名目前按头各抄一遍（"共享表"还是过渡形态）。同一个英文名出现在多个条目里时，
#  只要有人在一处改了译名、别处忘了改，就会在【很后面】才以"某某里没有名为某某的成员"
#  的形式报出来 —— 实测已经连续踩了三例（<mutex> -> <condition_variable> -> <shared_mutex>）。
#
#  与其靠人记得同步，不如让机器开口：同一个英文名（同一类：types / members）
#  在任意两个条目里的中文译名必须【一模一样】。
#
#  ⚠ 确实有"同名不同义"的合法情形，允许在 $ZH_NAME_EXCEPTIONS 里登记豁免，
#     但豁免要写理由 —— 默认是"必须一致"。
# ---------------------------------------------------------------------------
$ZH_NAME_EXCEPTIONS = @{
    # 登记必须写理由 —— 默认是"同一个英文名必须同一个译名"。
    'members/reset' = 'bitset::reset 是"把某一位清零"（复位）；optional::reset 是"销毁所存的值"（重置）。同名不同义，允许两个译名。'
}
$zhSeen  = @{}
$zhClash = @()
foreach ($en in ($H.Keys | Sort-Object)) {
    foreach ($kind in @('types', 'members', 'data')) {
        if (-not $H[$en].ContainsKey($kind)) { continue }
        foreach ($k in $H[$en][$kind].Keys) {
            $zh = $H[$en][$kind][$k]
            $id = "$kind/$k"
            if ($ZH_NAME_EXCEPTIONS.ContainsKey($id)) { continue }
            if (-not $zhSeen.ContainsKey($id)) {
                $zhSeen[$id] = @{ zh = $zh; owners = @($en) }
            } elseif ($zhSeen[$id].zh -ne $zh) {
                $zhClash += ("  [$kind] '{0}': {1} 译作 '{2}'，但 {3} 译作 '{4}'" -f `
                    $k, ($zhSeen[$id].owners -join '/'), $zhSeen[$id].zh, $en, $zh)
            } else {
                if ($zhSeen[$id].owners -notcontains $en) { $zhSeen[$id].owners += $en }
            }
        }
    }
}
$shared = @($zhSeen.Values | Where-Object { $_.owners.Count -gt 1 })
Write-Host ("跨头译名检查: 共 {0} 个英文名，其中 {1} 个跨了多个头" -f $zhSeen.Count, $shared.Count)
if ($zhClash.Count) {
    Write-Host "❌ 跨头译名不一致（同一个英文名、两个译名）:" -ForegroundColor Red
    $zhClash | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host '  修法：统一成同一个译名；若确实同名不同义，到 $ZH_NAME_EXCEPTIONS 登记并写理由。' -ForegroundColor Yellow
    throw "跨头译名不一致，先修表再生成"
}

# ---------------------------------------------------------------------------
#  关键词表检查：中文名绝不能是关键词（实测踩到，且极难从报错看出是命名问题）
#
#  <bitset> 里我把 flip 译作「取反」，而关键词表里：
#      ZH_OPERATOR_KEYWORD(取反, tilde)   // 取反 = compl = ~
#  于是 `取反()` 被词法成 `~()`，编译器报的是
#      error: '~' 之后需要给出类名来指明析构函数
#  —— 报的是"析构函数"，跟命名八竿子打不着，看半天看不出来。
#
#  判据：ChineseKeywords.def 里的中文词一律不能当标识符（方案 §2.2 第一步就是查它，
#        但"我记得查"不算数 —— 这里改成机器查）。
# ---------------------------------------------------------------------------
$kwFile = Join-Path $root 'LLVM-main\clang\include\clang\Basic\ChineseKeywords.def'
$kwList = @{}
if (Test-Path $kwFile) {
    foreach ($line in [System.IO.File]::ReadAllLines($kwFile)) {
        if ($line -notmatch 'KEYWORD') { continue }
        # ZH_KEYWORD(英文, 中文, FLAGS)     —— 中文是第 2 个参数
        foreach ($m in [regex]::Matches($line, 'ZH_KEYWORD\s*\(\s*[^,]+,\s*([^,]+),')) {
            $kwList[$m.Groups[1].Value.Trim()] = $line.Trim()
        }
        # ZH_OPERATOR_KEYWORD(中文, 英文)   —— 中文是第 1 个参数
        foreach ($m in [regex]::Matches($line, 'ZH_OPERATOR_KEYWORD\s*\(\s*([^,]+),')) {
            $kwList[$m.Groups[1].Value.Trim()] = $line.Trim()
        }
    }
}
$kwBad = @(); $kwChecked = 0
foreach ($en in ($H.Keys | Sort-Object)) {
    $names = @($H[$en].zh)
    if ($H[$en].ContainsKey('pub')) { $names += $H[$en].pub }
    foreach ($kind in @('types', 'members', 'data')) {
        if ($H[$en].ContainsKey($kind)) { $names += @($H[$en][$kind].Values) }
    }
    foreach ($n in $names) {
        $kwChecked++
        if ($kwList.ContainsKey($n)) { $kwBad += ("  [{0}] '{1}' 是关键词：{2}" -f $en, $n, $kwList[$n]) }
    }
}
Write-Host ("关键词表检查: 表里 {0} 个关键词，查了本表 {1} 个中文名" -f $kwList.Count, $kwChecked)
if ($kwBad.Count) {
    Write-Host "❌ 有中文名撞上关键词（会词法成运算符/语句，报错完全不像命名问题）:" -ForegroundColor Red
    $kwBad | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw "中文名撞关键词，先改名再生成"
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
# ---------------------------------------------------------------------------
#  步 0b：真头包含（realInclude）+ 丢掉抄来的异常类（dropTypes）
#
#  为什么需要（<optional> 是第一个用户）：
#    一个头里常常【混着两类东西】：
#      · 值类型（std::optional）                 -> 可以抄+派生，能有中文成员名
#      · 异常类型（std::bad_optional_access）    -> 身份参与语义，铁律 4 要求必须是 std 的那个
#    整个头都抄的话，_Throw_bad_optional_access() 抛的是【我们抄来那个类】，
#    用户写 catch (std::bad_optional_access&) 永远抓不到。
#
#  办法两步：
#    realInclude  把【微软原头】也包含进来 -> 真的 std::bad_optional_access 存在了
#    dropTypes    把抄来那份【异常类的定义删掉】-> 本文件里的 bad_optional_access
#                 就靠 `使用 名域 std;` 解析到真的那个，异常自然就是同一个类型
#
#  ⚠ dropTypes 只适合"简单异常类"。删除用花括号配对实现，
#     不处理字符串/注释里的花括号 —— 对异常类足够，别拿它删大东西。
# ---------------------------------------------------------------------------
function Remove-ClassDef {
    param([string]$Text, [string]$Name, [ref]$Count)
    $rx = [regex]('(?m)^[^\r\n]*\b(?:class|struct)\s+' + [regex]::Escape($Name) + '\b[^\r\n]*\{')
    $m = $rx.Match($Text)
    if (-not $m.Success) { return $Text }
    $i = $Text.IndexOf('{', $m.Index)
    $depth = 0; $j = $i
    while ($j -lt $Text.Length) {
        $ch = $Text[$j]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { break } }
        $j++
    }
    if ($j -ge $Text.Length) { return $Text }
    $end = $j + 1
    while ($end -lt $Text.Length -and ($Text[$end] -eq ';' -or $Text[$end] -eq ' ' -or $Text[$end] -eq "`r" -or $Text[$end] -eq "`n")) { $end++ }
    $Count.Value++
    $note = "// [dropTypes] 这里删掉了抄来的 " + $Name + " 定义。`n" +
            "// 它的身份必须是 std 的那个（铁律 4：捕获按类型匹配），所以改用真头的 std::" + $Name + "。`n"
    return $Text.Substring(0, $m.Index) + $note + $Text.Substring($end)
}


if ($spec.dropTypes) {
    foreach ($dn in @($spec.dropTypes)) {
        if ($spec.types -and $spec.types.Contains($dn)) {
            throw "dropTypes 与 types 冲突：'$dn' 既被删又被改名 —— 删掉就不该再登记改名"
        }
        $nDrop = 0
        $text = Remove-ClassDef -Text $text -Name $dn -Count ([ref]$nDrop)
        if ($nDrop -eq 0) {
            Write-Host "  步0b ⚠ dropTypes 没找到类定义 '$dn'" -ForegroundColor Yellow
        } else {
            Write-Host "  步0b 丢掉抄来的类定义 '$dn'（改用真头的 std::$dn）"
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

# ---------------------------------------------------------------------------
#  步 2b：pmr 嵌套名域（实测踩到，<set> 是第一个带它的头）
#
#  MSVC 很多容器头末尾有一段：
#      namespace pmr {
#          using set = _STD set<_Kty, _Pr, polymorphic_allocator<_Kty>>;
#      }
#  搬进 细节 之后，`polymorphic_allocator` 就找不到了一一 它本来靠
#  "在 std::pmr 里面" 这个位置找到同名的 std::pmr::polymorphic_allocator：
#      error: 使用了未声明的标识符 'polymorphic_allocator'；
#             你是不是想写 'std::pmr::polymorphic_allocator'？
#  而 `使用 名域 std;` 只把 std 的名字引进 细节，引不进 std::pmr 的【嵌套】名字。
#
#  修法：在 `namespace pmr {` 后面补一句 `使用 名域 std::pmr;`。
#  pmr 名域本身暂不翻（方案 §六第 9 条），但里面的名字必须能找到。
# ---------------------------------------------------------------------------
$nPmr = 0
if ($text -match '(?m)^namespace pmr \{') {
    $text = [regex]::Replace($text, '(?m)^(namespace pmr \{)',
        "`$1`n    使用 名域 std::pmr;   // pmr 暂不翻，但里面的名字要靠它找到（步 2b）")
    $nPmr = 1
    Write-Host '  步2b pmr 名域：补 使用 名域 std::pmr;'
}

# 步 3/4：类型名、成员名、数据成员名（按 \b 边界，逐条替换）
$nT = 0; $nM = 0; $nD = 0
foreach ($k in $spec.types.Keys)   { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.types[$k]); $nT += $c } }
foreach ($k in $spec.members.Keys) { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.members[$k]); $nM += $c } }
foreach ($k in $spec.data.Keys)    { $c = ([regex]::Matches($text, "\b$([regex]::Escape($k))\b")).Count; if ($c) { $text = [regex]::Replace($text, "\b$([regex]::Escape($k))\b", $spec.data[$k]); $nD += $c } }
Write-Host "  步3/4 类型 $nT 处 / 成员 $nM 处 / 数据 $nD 处"
# ⚠ realInclude 必须插在【改名之后】：否则 `#include <optional>` 里的 optional
#   会被类型改名改成 `#include <可选实现>` -> fatal error: 找不到文件 '可选实现'。
#   （dropTypes 相反，必须在改名【之前】，因为要匹配英文类名。）
if ($spec.realInclude) {
    $pos = $text.IndexOf('_STD_BEGIN')
    if ($pos -lt 0) { $pos = 0 }
    $inc = (@($spec.realInclude) | ForEach-Object { "#include <$_>" }) -join "`n"
    $text = $text.Substring(0, $pos) + $inc + "`n" + $text.Substring($pos)
    Write-Host ("  步0b 真头包含（改名后插）: {0}" -f (@($spec.realInclude) -join ', '))
}

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

    // 表里给的额外成员（deriveExtra）—— 【中文】转发，用来给"继承自借用基类"的
    // API 补中文名（那些名字不在本文件里，members 表改不到，见方案 §3.16）
$($spec.deriveExtra)
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
# ---------------------------------------------------------------------------
#  ⚠ 派生层必须插在【包含守卫的 #endif 之前】，不能追加到文件最末。
#
#  为什么（<shared_mutex> 实测踩到，一个【潜伏了很久】的 bug）：
#  MSVC 公开头的最末一行就是守卫的 `#endif // _XXX_`。原先把派生层 Append 在它之后，
#  于是「守卫守得住正文，守不住派生层」—— 同一个汉语头被包含两次时，
#  正文被守卫跳过，派生层却被编译第二遍：
#      error: 重定义（名字） '互斥量' / '独占锁' / '锁守卫'
#  单头测试永远照不出来；<共享互斥量> 同时包含 <互斥量> 与 <条件变量>，
#  而 <条件变量> 自己又包含 <互斥量> —— 同一头进两次，才把这个坑炸出来。
#  规则：**凡是我们往头文件里加东西，都要问一句"它在守卫里面吗"。**
# ---------------------------------------------------------------------------
$cur = [System.IO.File]::ReadAllText($outPath)
$endifs = [regex]::Matches($cur, '(?m)^[ \t]*#endif\b')
if ($endifs.Count -gt 0) {
    $pos = $endifs[$endifs.Count - 1].Index      # 最后一个 #endif = 包含守卫那一个
    # 插到它前面（保留原文一切字节不变，只做插入）
    $cur = $cur.Substring(0, $pos) + $layerText.TrimStart("`r", "`n") + "`r`n`r`n" + $cur.Substring($pos)
    [System.IO.File]::WriteAllText($outPath, $cur, $utf8)
} else {
    Write-Host "  ⚠ 没找到守卫 #endif，派生层只能追加在文件末" -ForegroundColor Yellow
    [System.IO.File]::AppendAllText($outPath, $layerText, $utf8)
}
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
