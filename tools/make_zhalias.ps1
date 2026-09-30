# ============================================================================
#  make_zhalias.ps1 -- 「只能别名」的 C++ 头 -> 中文别名层
#
#  为什么这些头不能抄（方案铁律 4：类型身份参与语义的只能用别名）：
#    numbers          全是变量模板（常量），不是类
#    typeinfo         RTTI —— typeid() 返回 std::type_info 的引用
#    initializer_list 花括号初始化由编译器生成 std::initializer_list
#    ratio            std::chrono 的算术依赖它的类型身份
#    tuple            结构化绑定走 std::tuple_size / std::get 的特化
#    type_traits      全是 traits 检测
#    pair             有【公开数据成员】first/second（派生补不回英文名，会改布局）
#
#  机制（同 make_zhc.ps1 的三种，再加"常量"）：
#    常量  -> 内联 常量 类型 中文名 = std::原名;
#    类型  -> 使用 中文名 = std::原名;
#    函数  -> 模板 <类型名... 参数> 声明类型(自动) 中文名(参数&&... 值) { 返回 std::原名(...); }
#             ⚠ 返回类型必须用 声明类型(自动)（= decltype(auto)）而不是 自动：
#               std::get / std::front 之类是【引用返回】，`自动` 会按值推导掉，
#               `标准::取<0>(元组) = 值;` 就编不过 = 「原本的英语/中文用法退化」。
#               改于 §16.52（同 make_zhstdlib2.ps1 的派生层转发器）。
#
#  用法：powershell -File tools\make_zhalias.ps1 -Header numbers
# ============================================================================
param([string] $Header = 'numbers', [switch] $ExportJson)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$cxx  = Join-Path $root 'build\Release\bin\chinese++.exe'
$out  = Join-Path $root 'zhstdlib'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 表：条目 = @('常量','中文名','std::原名','类型')
#            @('类型','中文名','std::原名')
#            @('函数','中文名','std::原名')      —— 通用一模板转发
#            @('原样','<整行代码>')              —— 原样发出（成员要转发成自由函数时用）
$H = [ordered]@{
# §17.19.38 <algorithm>（11100 行）：全是函数 —— 不是"抄一份"，是中文门面转发到 std（公开层转发同型）
'algorithm' = @{ zh = '算法'; src = 'algorithm';
  reason = '算法头没有需要保身份的类型（都按迭代器模板推导），故走中文名转发；不含 ranges 版本（那要命名空间别名）。';
  a = @(
    @('原样','模板 <类型名 迭代> 空型 排序(迭代 首, 迭代 尾) { std::sort(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 比较> 空型 排序(迭代 首, 迭代 尾, 比较 丙) { std::sort(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代> 空型 稳定排序(迭代 首, 迭代 尾) { std::stable_sort(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 比较> 空型 稳定排序(迭代 首, 迭代 尾, 比较 丙) { std::stable_sort(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代> 空型 部分排序(迭代 首, 迭代 中, 迭代 尾) { std::partial_sort(首, 中, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 比较> 空型 部分排序(迭代 首, 迭代 中, 迭代 尾, 比较 丁) { std::partial_sort(首, 中, 尾, 丁); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代> 输出迭代 部分排序复制(迭代 首, 迭代 尾, 输出迭代 出, 输出迭代 出尾) { 返回 std::partial_sort_copy(首, 尾, 出, 出尾); }'),
    @('原样','模板 <类型名 迭代> 空型 定位第N小(迭代 首, 迭代 第n, 迭代 尾) { std::nth_element(首, 第n, 尾); }'),
    @('原样','模板 <类型名 迭代> 布尔 已排序(迭代 首, 迭代 尾) { 返回 std::is_sorted(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 比较> 布尔 已排序(迭代 首, 迭代 尾, 比较 丙) { 返回 std::is_sorted(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代> 迭代 已排序终点(迭代 首, 迭代 尾) { 返回 std::is_sorted_until(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 迭代 下界(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::lower_bound(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 迭代 上界(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::upper_bound(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 声明类型(自动) 相等区间(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::equal_range(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 布尔 折半查找(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::binary_search(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2, 类型名 输出迭代> 输出迭代 归并(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2, 输出迭代 出) { 返回 std::merge(首1, 尾1, 首2, 尾2, 出); }'),
    @('原样','模板 <类型名 迭代> 空型 原地归并(迭代 首, 迭代 中, 迭代 尾) { std::inplace_merge(首, 中, 尾); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 布尔 含子集(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2) { 返回 std::includes(首1, 尾1, 首2, 尾2); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2, 类型名 输出迭代> 输出迭代 并集(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2, 输出迭代 出) { 返回 std::set_union(首1, 尾1, 首2, 尾2, 出); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2, 类型名 输出迭代> 输出迭代 交集(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2, 输出迭代 出) { 返回 std::set_intersection(首1, 尾1, 首2, 尾2, 出); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2, 类型名 输出迭代> 输出迭代 差集(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2, 输出迭代 出) { 返回 std::set_difference(首1, 尾1, 首2, 尾2, 出); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2, 类型名 输出迭代> 输出迭代 对称差集(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2, 输出迭代 出) { 返回 std::set_symmetric_difference(首1, 尾1, 首2, 尾2, 出); }'),
    @('原样','模板 <类型名 迭代> 空型 建堆(迭代 首, 迭代 尾) { std::make_heap(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 空型 压入堆(迭代 首, 迭代 尾) { std::push_heap(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 空型 弹出堆(迭代 首, 迭代 尾) { std::pop_heap(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 空型 堆排序(迭代 首, 迭代 尾) { std::sort_heap(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 布尔 是堆(迭代 首, 迭代 尾) { 返回 std::is_heap(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 迭代 是堆终点(迭代 首, 迭代 尾) { 返回 std::is_heap_until(首, 尾); }'),
    @('原样','模板 <类型名 值类型> const 值类型& 最小值(const 值类型& 甲, const 值类型& 乙) { 返回 std::min(甲, 乙); }'),
    @('原样','模板 <类型名 值类型> const 值类型& 最大值(const 值类型& 甲, const 值类型& 乙) { 返回 std::max(甲, 乙); }'),
    @('原样','模板 <类型名 值类型> 声明类型(自动) 最小最大对(const 值类型& 甲, const 值类型& 乙) { 返回 std::minmax(甲, 乙); }'),
    @('原样','模板 <类型名 迭代> 迭代 最小元素(迭代 首, 迭代 尾) { 返回 std::min_element(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 迭代 最大元素(迭代 首, 迭代 尾) { 返回 std::max_element(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 声明类型(自动) 最小最大元素(迭代 首, 迭代 尾) { 返回 std::minmax_element(首, 尾); }'),
    @('原样','模板 <类型名 值类型> const 值类型& 夹取(const 值类型& 值, const 值类型& 低, const 值类型& 高) { 返回 std::clamp(值, 低, 高); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 布尔 区间相等(迭代1 首1, 迭代1 尾1, 迭代2 首2) { 返回 std::equal(首1, 尾1, 首2); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 声明类型(自动) 首个不匹配(迭代1 首1, 迭代1 尾1, 迭代2 首2) { 返回 std::mismatch(首1, 尾1, 首2); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 布尔 字典序比较(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2) { 返回 std::lexicographical_compare(首1, 尾1, 首2, 尾2); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 布尔 是排列(迭代1 首1, 迭代1 尾1, 迭代2 首2) { 返回 std::is_permutation(首1, 尾1, 首2); }'),
    @('原样','模板 <类型名 迭代> 布尔 下一排列(迭代 首, 迭代 尾) { 返回 std::next_permutation(首, 尾); }'),
    @('原样','模板 <类型名 迭代> 布尔 上一排列(迭代 首, 迭代 尾) { 返回 std::prev_permutation(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 迭代 查找(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::find(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 迭代 查找若(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::find_if(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 迭代 查找若非(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::find_if_not(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代> 迭代 查找相邻相等(迭代 首, 迭代 尾) { 返回 std::adjacent_find(首, 尾); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 迭代1 查找子序列(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2) { 返回 std::search(首1, 尾1, 首2, 尾2); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 迭代1 查找末尾(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2) { 返回 std::find_end(首1, 尾1, 首2, 尾2); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 迭代1 查找首个属于(迭代1 首1, 迭代1 尾1, 迭代2 首2, 迭代2 尾2) { 返回 std::find_first_of(首1, 尾1, 首2, 尾2); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 迭代 查找连续(迭代 首, 迭代 尾, std::size_t 个数, const 值类型& 值) { 返回 std::search_n(首, 尾, 个数, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 声明类型(自动) 计数(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::count(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 声明类型(自动) 计数若(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::count_if(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代> 输出迭代 复制区间(迭代 首, 迭代 尾, 输出迭代 出) { 返回 std::copy(首, 尾, 出); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代, 类型名 谓词> 输出迭代 复制若(迭代 首, 迭代 尾, 输出迭代 出, 谓词 丁) { 返回 std::copy_if(首, 尾, 出, 丁); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代> 输出迭代 移动区间(迭代 首, 迭代 尾, 输出迭代 出) { 返回 std::move(首, 尾, 出); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 空型 填充(迭代 首, 迭代 尾, const 值类型& 值) { std::fill(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 大小类型, 类型名 值类型> 迭代 填充个(迭代 首, 大小类型 个数, const 值类型& 值) { 返回 std::fill_n(首, 个数, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代, 类型名 一元操作> 输出迭代 变换(迭代 首, 迭代 尾, 输出迭代 出, 一元操作 丁) { 返回 std::transform(首, 尾, 出, 丁); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代, 类型名 生成器> 输出迭代 生成(迭代 首, 迭代 尾, 生成器 丙) { 返回 std::generate(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 大小类型, 类型名 生成器> 迭代 生成个(迭代 首, 大小类型 个数, 生成器 丙) { 返回 std::generate_n(首, 个数, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 迭代 移除元素(迭代 首, 迭代 尾, const 值类型& 值) { 返回 std::remove(首, 尾, 值); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 迭代 移除若(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::remove_if(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 值类型> 空型 替换(迭代 首, 迭代 尾, const 值类型& 旧值, const 值类型& 新值) { std::replace(首, 尾, 旧值, 新值); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词, 类型名 值类型> 空型 替换若(迭代 首, 迭代 尾, 谓词 丙, const 值类型& 新值) { std::replace_if(首, 尾, 丙, 新值); }'),
    @('原样','模板 <类型名 类型1, 类型名 类型2> 空型 交换值(类型1& 甲, 类型2& 乙) { std::swap(甲, 乙); }'),
    @('原样','模板 <类型名 迭代1, 类型名 迭代2> 迭代2 交换区间(迭代1 首1, 迭代1 尾1, 迭代2 首2) { 返回 std::swap_ranges(首1, 尾1, 首2); }'),
    @('原样','模板 <类型名 迭代> 空型 反转(迭代 首, 迭代 尾) { std::reverse(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代> 输出迭代 反转复制(迭代 首, 迭代 尾, 输出迭代 出) { 返回 std::reverse_copy(首, 尾, 出); }'),
    @('原样','模板 <类型名 迭代> 迭代 旋转(迭代 首, 迭代 中, 迭代 尾) { 返回 std::rotate(首, 中, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代> 输出迭代 旋转复制(迭代 首, 迭代 中, 迭代 尾, 输出迭代 出) { 返回 std::rotate_copy(首, 中, 尾, 出); }'),
    @('原样','模板 <类型名 迭代> 迭代 去重(迭代 首, 迭代 尾) { 返回 std::unique(首, 尾); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代> 输出迭代 去重复制(迭代 首, 迭代 尾, 输出迭代 出) { 返回 std::unique_copy(首, 尾, 出); }'),
    @('原样','模板 <类型名 随机迭代, 类型名 引擎> 空型 洗牌(随机迭代 首, 随机迭代 尾, 引擎& 丙) { std::shuffle(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 输出迭代, 类型名 引擎> 输出迭代 抽样(迭代 首, 迭代 尾, 输出迭代 出, std::ptrdiff_t 个数, 引擎& 戊) { 返回 std::sample(首, 尾, 出, 个数, 戊); }'),
    @('原样','模板 <类型名 迭代, 类型名 函数> 函数 逐元素(迭代 首, 迭代 尾, 函数 丙) { 返回 std::for_each(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 布尔 全部满足(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::all_of(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 布尔 任一满足(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::any_of(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 布尔 无一满足(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::none_of(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 迭代 分组(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::partition(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 迭代 稳定分组(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::stable_partition(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 迭代 分组点(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::partition_point(首, 尾, 丙); }'),
    @('原样','模板 <类型名 迭代, 类型名 谓词> 布尔 已分组(迭代 首, 迭代 尾, 谓词 丙) { 返回 std::is_partitioned(首, 尾, 丙); }')
  )
  tests = @(
    @('只引中文头','#包含 <算法>`n#包含 <向量>`n整数 主函数(){ 标准::向量<整数> 甲{3, 1, 2}; 标准::排序(甲.开始(), 甲.结束()); 返回 标准::已排序(甲.开始(), 甲.结束()) 并且 甲.前() == 1 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <算法>`n#包含 <algorithm>`n#包含 <vector>`n整数 主函数(){ std::vector<整数> 甲{3, 1, 2}; 标准::排序(甲.begin(), 甲.end()); 布尔 乙 = 标准::折半查找(甲.begin(), 甲.end(), 2); 布尔 丙 = std::binary_search(甲.begin(), 甲.end(), 2); 返回 (乙 == 丙) ? 0 : 1; }')
  )
}

# §17.19.36 <filesystem> / <format>：路径与格式化器 —— 铁律③
'filesystem' = @{ zh = '文件系统'; src = 'filesystem';
  reason = '铁律③：路径/目录迭代器/文件时间点参与语义（按类型重载、与 chrono 互操作）。';
  a = @(
    @('原样','使用 路径 = std::filesystem::path;'),
    @('原样','使用 文件系统异常 = std::filesystem::filesystem_error;'),
    @('原样','使用 目录项 = std::filesystem::directory_entry;'),
    @('原样','使用 目录迭代器 = std::filesystem::directory_iterator;'),
    @('原样','使用 递归目录迭代器 = std::filesystem::recursive_directory_iterator;'),
    @('原样','使用 文件状态 = std::filesystem::file_status;'),
    @('原样','使用 空间信息 = std::filesystem::space_info;'),
    @('原样','使用 文件类型 = std::filesystem::file_type;'),
    @('原样','使用 权限集 = std::filesystem::perms;'),
    @('原样','使用 复制选项 = std::filesystem::copy_options;'),
    @('原样','使用 目录选项 = std::filesystem::directory_options;'),
    @('原样','使用 权限选项 = std::filesystem::perm_options;'),
    @('原样','使用 文件时间点 = std::filesystem::file_time_type;'),
    @('原样','布尔 存在(const std::filesystem::path& 甲) { 返回 std::filesystem::exists(甲); }'),
    @('原样','布尔 存在(const std::filesystem::file_status& 甲) 不抛出 { 返回 std::filesystem::exists(甲); }'),
    @('原样','布尔 是目录(const std::filesystem::path& 甲) { 返回 std::filesystem::is_directory(甲); }'),
    @('原样','布尔 是普通文件(const std::filesystem::path& 甲) { 返回 std::filesystem::is_regular_file(甲); }'),
    @('原样','布尔 是符号链接(const std::filesystem::path& 甲) { 返回 std::filesystem::is_symlink(甲); }'),
    @('原样','布尔 是空文件(const std::filesystem::path& 甲) { 返回 std::filesystem::is_empty(甲); }'),
    @('原样','声明类型(自动) 文件大小(const std::filesystem::path& 甲) { 返回 std::filesystem::file_size(甲); }'),
    @('原样','布尔 移除(const std::filesystem::path& 甲) { 返回 std::filesystem::remove(甲); }'),
    @('原样','声明类型(自动) 移除全部(const std::filesystem::path& 甲) { 返回 std::filesystem::remove_all(甲); }'),
    @('原样','布尔 创建目录(const std::filesystem::path& 甲) { 返回 std::filesystem::create_directory(甲); }'),
    @('原样','布尔 创建目录树(const std::filesystem::path& 甲) { 返回 std::filesystem::create_directories(甲); }'),
    @('原样','空型 复制(const std::filesystem::path& 甲, const std::filesystem::path& 乙, std::filesystem::copy_options 丙 = std::filesystem::copy_options::none) { std::filesystem::copy(甲, 乙, 丙); }'),
    @('原样','布尔 复制文件(const std::filesystem::path& 甲, const std::filesystem::path& 乙, std::filesystem::copy_options 丙 = std::filesystem::copy_options::none) { 返回 std::filesystem::copy_file(甲, 乙, 丙); }'),
    @('原样','空型 重命名(const std::filesystem::path& 甲, const std::filesystem::path& 乙) { std::filesystem::rename(甲, 乙); }'),
    @('原样','声明类型(自动) 绝对路径(const std::filesystem::path& 甲) { 返回 std::filesystem::absolute(甲); }'),
    @('原样','声明类型(自动) 规范路径(const std::filesystem::path& 甲) { 返回 std::filesystem::canonical(甲); }'),
    @('原样','声明类型(自动) 弱规范路径(const std::filesystem::path& 甲) { 返回 std::filesystem::weakly_canonical(甲); }'),
    @('原样','声明类型(自动) 相对路径(const std::filesystem::path& 甲) { 返回 std::filesystem::relative(甲); }'),
    @('原样','声明类型(自动) 当前路径() { 返回 std::filesystem::current_path(); }'),
    @('原样','空型 当前路径(const std::filesystem::path& 甲) { std::filesystem::current_path(甲); }'),
    @('原样','声明类型(自动) 临时目录路径() { 返回 std::filesystem::temp_directory_path(); }'),
    @('原样','布尔 等价路径(const std::filesystem::path& 甲, const std::filesystem::path& 乙) { 返回 std::filesystem::equivalent(甲, 乙); }'),
    @('原样','声明类型(自动) 取文件状态(const std::filesystem::path& 甲) { 返回 std::filesystem::status(甲); }'),
    @('原样','声明类型(自动) 取符号链接状态(const std::filesystem::path& 甲) { 返回 std::filesystem::symlink_status(甲); }'),
    @('原样','空型 置权限(const std::filesystem::path& 甲, std::filesystem::perms 乙, std::filesystem::perm_options 丙 = std::filesystem::perm_options::replace) { std::filesystem::permissions(甲, 乙, 丙); }'),
    @('原样','声明类型(自动) 最后写入时间(const std::filesystem::path& 甲) { 返回 std::filesystem::last_write_time(甲); }'),
    @('原样','空型 最后写入时间(const std::filesystem::path& 甲, 标准::文件时间点 乙) { std::filesystem::last_write_time(甲, 乙); }'),
    @('原样','声明类型(自动) 空间(const std::filesystem::path& 甲) { 返回 std::filesystem::space(甲); }'),
    @('常量','覆盖已存在','std::filesystem::copy_options::overwrite_existing','std::filesystem::copy_options'),
    @('常量','递归复制','std::filesystem::copy_options::recursive','std::filesystem::copy_options'),
    @('常量','跳过权限拒绝','std::filesystem::directory_options::skip_permission_denied','std::filesystem::directory_options')
  )
  tests = @(
    @('只引中文头','#包含 <文件系统>`n整数 主函数(){ 标准::路径 甲{"."}; 布尔 乙 = 标准::存在(甲); 标准::路径 丙 = 标准::当前路径(); 返回 (乙 并且 丙.string().size() > 0) ? 0 : 1; }'),
    @('与微软原头并存','#包含 <文件系统>`n#包含 <filesystem>`n整数 主函数(){ 标准::路径 甲{"."}; std::filesystem::path 乙 = 甲; 标准::空间信息 丙 = 标准::空间(甲); std::filesystem::space_info 丁 = 丙; 返回 (丁.capacity > 0) ? 0 : 1; }')
  )
}
'format' = @{ zh = '格式化文本'; src = 'format';
  reason = '铁律③：formatter 是用户扩展点（用户特化 std::formatter<T>），身份必须与 std 同一。';
  a = @(
    @('原样','模板 <类型名 值类型, 类型名 字符类型 = 字符> 使用 格式化器 = std::formatter<值类型, 字符类型>;'),
    @('原样','使用 格式化异常 = std::format_error;'),
    @('原样','模板 <类型名 输出迭代器, 类型名 字符类型 = 字符> 使用 格式上下文 = std::basic_format_context<输出迭代器, 字符类型>;'),
    @('原样','模板 <类型名 字符类型> 使用 格式解析上下文 = std::basic_format_parse_context<字符类型>;'),
    @('原样','使用 格式参数 = std::format_args;'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 格式(std::format_string<参数...> 甲, 参数&&... 乙) { 返回 std::format(甲, static_cast<参数&&>(乙)...); }'),
    @('原样','模板 <类型名 输出迭代器, 类型名... 参数> 声明类型(自动) 格式化到(输出迭代器 甲, std::format_string<参数...> 乙, 参数&&... 丙) { 返回 std::format_to(甲, 乙, static_cast<参数&&>(丙)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 格式化尺寸(std::format_string<参数...> 甲, 参数&&... 乙) { 返回 std::formatted_size(甲, static_cast<参数&&>(乙)...); }'),
    @('原样','模板 <类型名 字符类型> 声明类型(自动) 格式化参数版(std::basic_string_view<字符类型> 甲, std::format_args 乙) { 返回 std::vformat(甲, 乙); }')
  )
  tests = @(
    @('只引中文头','#包含 <格式化文本>`n整数 主函数(){ 自动 甲 = 标准::格式("中文 {} {}", 1, 2); 返回 甲.empty() ? 1 : 0; }'),
    @('与微软原头并存','#包含 <格式化文本>`n#包含 <format>`n整数 主函数(){ 标准::格式化器<整数> 甲; std::formatter<整数> 乙; (空型)甲; (空型)乙; 返回 0; }')
  )
}

# §17.19.35 <random> / <regex>：引擎与分布、正则类型 —— 铁律③，只能别名
'random' = @{ zh = '随机'; src = 'random';
  reason = '铁律③：引擎/分布类型参与语义（按类型重载、模板实参推导、分布要求 ResultType 精确匹配）。';
  a = @(
    @('原样','使用 最小标准随机0 = std::minstd_rand0;'),
    @('原样','使用 最小标准随机 = std::minstd_rand;'),
    @('原样','使用 梅森旋转19937 = std::mt19937;'),
    @('原样','使用 梅森旋转19937_64 = std::mt19937_64;'),
    @('原样','使用 兰勒克斯24基 = std::ranlux24_base;'),
    @('原样','使用 兰勒克斯48基 = std::ranlux48_base;'),
    @('原样','使用 兰勒克斯24 = std::ranlux24;'),
    @('原样','使用 兰勒克斯48 = std::ranlux48;'),
    @('原样','使用 克努特乙 = std::knuth_b;'),
    @('原样','使用 默认随机引擎 = std::default_random_engine;'),
    @('原样','使用 随机设备 = std::random_device;'),
    @('原样','使用 种子序列 = std::seed_seq;'),
    @('原样','模板 <类型名 结果类型, 结果类型 甲, 结果类型 乙, 结果类型 丙> 使用 线性同余引擎 = std::linear_congruential_engine<结果类型, 甲, 乙, 丙>;'),
    @('原样','模板 <类型名 结果类型, std::size_t 甲, std::size_t 乙, std::size_t 丙, std::size_t 丁, 结果类型 戊, std::size_t 己, 结果类型 庚, std::size_t 辛, 结果类型 壬, std::size_t 癸, 结果类型 子, std::size_t 丑, 结果类型 寅> 使用 梅森旋转引擎 = std::mersenne_twister_engine<结果类型, 甲, 乙, 丙, 丁, 戊, 己, 庚, 辛, 壬, 癸, 子, 丑, 寅>;'),
    @('原样','模板 <类型名 结果类型, std::size_t 甲, std::size_t 乙, std::size_t 丙> 使用 带进位减法引擎 = std::subtract_with_carry_engine<结果类型, 甲, 乙, 丙>;'),
    @('原样','模板 <类型名 引擎, std::size_t 甲, std::size_t 乙> 使用 丢弃块引擎 = std::discard_block_engine<引擎, 甲, 乙>;'),
    @('原样','模板 <类型名 引擎, std::size_t 甲, 类型名 结果类型> 使用 独立位引擎 = std::independent_bits_engine<引擎, 甲, 结果类型>;'),
    @('原样','模板 <类型名 引擎, std::size_t 甲> 使用 乱序引擎 = std::shuffle_order_engine<引擎, 甲>;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 均匀整数分布 = std::uniform_int_distribution<整数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 均匀实数分布 = std::uniform_real_distribution<实数类型>;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 伯努利分布 = std::bernoulli_distribution;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 二项分布 = std::binomial_distribution<整数类型>;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 几何分布 = std::geometric_distribution<整数类型>;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 负二项分布 = std::negative_binomial_distribution<整数类型>;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 泊松分布 = std::poisson_distribution<整数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 指数分布 = std::exponential_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 伽马分布 = std::gamma_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 韦布尔分布 = std::weibull_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 极值分布 = std::extreme_value_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 正态分布 = std::normal_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 对数正态分布 = std::lognormal_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 卡方分布 = std::chi_squared_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 柯西分布 = std::cauchy_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 费歇尔F分布 = std::fisher_f_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 学生t分布 = std::student_t_distribution<实数类型>;'),
    @('原样','模板 <类型名 整数类型 = 整数> 使用 离散分布 = std::discrete_distribution<整数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 分段常数分布 = std::piecewise_constant_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型 = 双精度> 使用 分段线性分布 = std::piecewise_linear_distribution<实数类型>;'),
    @('原样','模板 <类型名 实数类型, std::size_t 位数, 类型名 引擎> 声明类型(自动) 生成规范数(引擎& 甲) { 返回 std::generate_canonical<实数类型, 位数>(甲); }')
  )
  tests = @(
    @('只引中文头','#包含 <随机>`n整数 主函数(){ 标准::梅森旋转19937 甲{12345}; 标准::均匀整数分布<整数> 乙{1, 6}; 整数 丙 = 乙(甲); 返回 (丙 >= 1 并且 丙 <= 6) ? 0 : 1; }'),
    @('与微软原头并存','#包含 <随机>`n#包含 <random>`n整数 主函数(){ 标准::默认随机引擎 甲{1}; std::default_random_engine 乙{1}; 标准::正态分布<> 丙{0.0, 1.0}; std::normal_distribution<> 丁{0.0, 1.0}; (空型)丙; (空型)丁; 返回 甲() == 乙() ? 0 : 1; }')
  )
}
'regex' = @{ zh = '正则表达式'; src = 'regex';
  reason = '铁律③：正则与匹配结果类型参与语义（用户按类型重载、迭代器类型写死在签名里）。';
  a = @(
    @('原样','模板 <类型名 字符类型, 类型名 特征 = std::regex_traits<字符类型>> 使用 基本正则 = std::basic_regex<字符类型, 特征>;'),
    @('原样','使用 正则 = std::regex;'),
    @('原样','使用 宽正则 = std::wregex;'),
    @('原样','模板 <类型名 字符类型> 使用 正则特征 = std::regex_traits<字符类型>;'),
    @('原样','使用 正则异常 = std::regex_error;'),
    @('原样','模板 <类型名 双向迭代器> 使用 子匹配 = std::sub_match<双向迭代器>;'),
    @('原样','模板 <类型名 双向迭代器, 类型名 分配器 = std::allocator<std::sub_match<双向迭代器>>> 使用 匹配结果 = std::match_results<双向迭代器, 分配器>;'),
    @('原样','使用 字符匹配结果 = std::cmatch;'),
    @('原样','使用 宽字符匹配结果 = std::wcmatch;'),
    @('原样','使用 串匹配结果 = std::smatch;'),
    @('原样','使用 宽串匹配结果 = std::wsmatch;'),
    @('原样','模板 <类型名 双向迭代器, 类型名 字符类型, 类型名 特征 = std::regex_traits<字符类型>> 使用 正则迭代器 = std::regex_iterator<双向迭代器, 字符类型, 特征>;'),
    @('原样','使用 字符正则迭代器 = std::cregex_iterator;'),
    @('原样','使用 串正则迭代器 = std::sregex_iterator;'),
    @('原样','模板 <类型名 双向迭代器, 类型名 字符类型, 类型名 特征 = std::regex_traits<字符类型>> 使用 正则词元迭代器 = std::regex_token_iterator<双向迭代器, 字符类型, 特征>;'),
    @('原样','使用 字符正则词元迭代器 = std::cregex_token_iterator;'),
    @('原样','使用 串正则词元迭代器 = std::sregex_token_iterator;'),
    @('原样','模板 <类型名 字符类型, 类型名 特征> 布尔 正则匹配(const std::basic_string<字符类型, 特征>& 甲, const std::basic_regex<字符类型, 特征>& 乙, std::regex_constants::match_flag_type 丙 = std::regex_constants::match_default) { 返回 std::regex_match(甲, 乙, 丙); }'),
    @('原样','模板 <类型名 字符类型, 类型名 特征, 类型名 结果, 类型名 结果分配器> 布尔 正则匹配(const std::basic_string<字符类型, 特征>& 甲, std::match_results<结果, 结果分配器>& 乙, const std::basic_regex<字符类型, 特征>& 丙, std::regex_constants::match_flag_type 丁 = std::regex_constants::match_default) { 返回 std::regex_match(甲, 乙, 丙, 丁); }'),
    @('原样','模板 <类型名 字符类型, 类型名 特征> 布尔 正则查找(const std::basic_string<字符类型, 特征>& 甲, const std::basic_regex<字符类型, 特征>& 乙, std::regex_constants::match_flag_type 丙 = std::regex_constants::match_default) { 返回 std::regex_search(甲, 乙, 丙); }'),
    @('原样','模板 <类型名 字符类型, 类型名 特征, 类型名 结果, 类型名 结果分配器> 布尔 正则查找(const std::basic_string<字符类型, 特征>& 甲, std::match_results<结果, 结果分配器>& 乙, const std::basic_regex<字符类型, 特征>& 丙, std::regex_constants::match_flag_type 丁 = std::regex_constants::match_default) { 返回 std::regex_search(甲, 乙, 丙, 丁); }'),
    @('原样','模板 <类型名 字符类型, 类型名 特征, 类型名 替换类型> 声明类型(自动) 正则替换(const std::basic_string<字符类型, 特征>& 甲, const std::basic_regex<字符类型, 特征>& 乙, 替换类型&& 丙, std::regex_constants::match_flag_type 丁 = std::regex_constants::match_default) { 返回 std::regex_replace(甲, 乙, static_cast<替换类型&&>(丙), 丁); }'),
    @('常量','匹配默认','std::regex_constants::match_default','std::regex_constants::match_flag_type'),
    @('常量','匹配连续','std::regex_constants::match_continuous','std::regex_constants::match_flag_type'),
    @('常量','匹配任一处','std::regex_constants::match_any','std::regex_constants::match_flag_type'),
    @('常量','格式默认','std::regex_constants::format_default','std::regex_constants::match_flag_type'),
    @('常量','格式不拷贝','std::regex_constants::format_no_copy','std::regex_constants::match_flag_type'),
    @('常量','只替换首次','std::regex_constants::format_first_only','std::regex_constants::match_flag_type'),
    @('常量','忽略大小写','std::regex_constants::icase','std::regex_constants::syntax_option_type'),
    @('常量','不捕获','std::regex_constants::nosubs','std::regex_constants::syntax_option_type'),
    @('常量','优化正则','std::regex_constants::optimize','std::regex_constants::syntax_option_type'),
    @('常量','基本语法','std::regex_constants::basic','std::regex_constants::syntax_option_type'),
    @('常量','扩展语法','std::regex_constants::extended','std::regex_constants::syntax_option_type'),
    @('常量','脚本语法','std::regex_constants::ECMAScript','std::regex_constants::syntax_option_type')
  )
  tests = @(
    @('只引中文头','#包含 <正则表达式>`n#包含 <string>`n整数 主函数(){ std::string 甲 = "abc123"; 标准::正则 乙{"[0-9]+"}; 标准::串匹配结果 丙; 布尔 丁 = 标准::正则查找(甲, 丙, 乙); 返回 (丁 并且 丙.size() == 1) ? 0 : 1; }'),
    @('与微软原头并存','#包含 <正则表达式>`n#包含 <regex>`n整数 主函数(){ 标准::正则 甲{"a"}; std::regex 乙 = 甲; 标准::串 丙{"a"}; 布尔 丁 = 标准::正则匹配(丙, 乙); 返回 丁 ? 0 : 1; }')
  )
}

# §17.19.34 C++23 四个头：条件壳 #如果 _HAS_CXX23（中文名与英文名同生共死，不假装 C++20 下存在）
'expected' = @{ zh = '预期'; src = 'expected';
  reason = '铁律③：expected/unexpected 身份参与语义（用户按类型重载 + 模板实参推导）。C++23 头，故整块进条件壳。';
  a = @(
    @('原样','#如果 _HAS_CXX23'),
    @('原样','模板 <类型名 值类型, 类型名 错误类型> 使用 预期 = std::expected<值类型, 错误类型>;'),
    @('原样','模板 <类型名 错误类型> 使用 非预期值 = std::unexpected<错误类型>;'),
    @('原样','使用 非预期标记 = std::unexpect_t;'),
    @('常量','非预期','std::unexpect','std::unexpect_t'),
    @('原样','模板 <类型名 错误类型> 使用 预期访问异常 = std::bad_expected_access<错误类型>;'),
    @('原样','#结束如果')
  )
  tests = @(
    @('只引中文头','#包含 <预期>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::预期<整数, 整数> 甲{7}; 返回 甲.has_value() ? 0 : 1; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果'),
    @('与微软原头并存','#包含 <预期>`n#包含 <expected>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::非预期值<整数> 甲{3}; std::unexpected<整数> 乙 = 甲; 返回 乙.value() == 3 ? 0 : 1; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果')
  )
}
'mdspan' = @{ zh = '多维视图'; src = 'mdspan';
  reason = '铁律③：mdspan/extents 是模板，实参由用户写死并参与推导。C++23 头，整块进条件壳。';
  a = @(
    @('原样','#如果 _HAS_CXX23'),
    @('原样','模板 <类型名 下标类型, std::size_t... 各维> 使用 各维范围 = std::extents<下标类型, 各维...>;'),
    @('原样','模板 <类型名 下标类型, std::size_t 维数> 使用 动态各维范围 = std::dextents<下标类型, 维数>;'),
    @('原样','模板 <类型名 元素, 类型名 范围, 类型名 布局 = std::layout_right, 类型名 访问器 = std::default_accessor<元素>> 使用 多维视图 = std::mdspan<元素, 范围, 布局, 访问器>;'),
    @('原样','使用 左布局 = std::layout_left;'),
    @('原样','使用 右布局 = std::layout_right;'),
    @('原样','使用 跨步布局 = std::layout_stride;'),
    @('原样','模板 <类型名 元素> 使用 默认访问器 = std::default_accessor<元素>;'),
    @('原样','#结束如果')
  )
  tests = @(
    @('只引中文头','#包含 <多维视图>`n#如果 _HAS_CXX23`n整数 主函数(){ 整数 数据[6]{}; 标准::多维视图<整数, 标准::各维范围<std::size_t, 2, 3>> 甲(数据); (空型)甲; 返回 0; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果'),
    @('与微软原头并存','#包含 <多维视图>`n#包含 <mdspan>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::动态各维范围<std::size_t, 2> 甲{2, 3}; std::dextents<std::size_t, 2> 乙{2, 3}; 返回 甲.extent(0) == 乙.extent(0) ? 0 : 1; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果')
  )
}
'print' = @{ zh = '打印'; src = 'print';
  reason = '铁律③ 不适用（全是函数），但同样要中文门面；C++23 头，整块进条件壳（转发到 std::print）。';
  a = @(
    @('原样','#如果 _HAS_CXX23'),
    @('原样','模板 <类型名... 参数> 空型 打印(std::format_string<参数...> 格式, 参数&&... 甲) { std::print(格式, static_cast<参数&&>(甲)...); }'),
    @('原样','模板 <类型名... 参数> 空型 打印行(std::format_string<参数...> 格式, 参数&&... 甲) { std::println(格式, static_cast<参数&&>(甲)...); }'),
    @('原样','模板 <类型名... 参数> 空型 打印到文件(std::FILE* 甲, std::format_string<参数...> 格式, 参数&&... 乙) { std::print(甲, 格式, static_cast<参数&&>(乙)...); }'),
    @('原样','#结束如果')
  )
  tests = @(
    @('只引中文头','#包含 <打印>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::打印行("中文打印 {}`n", 7); 返回 0; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果'),
    @('与微软原头并存','#包含 <打印>`n#包含 <print>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::打印("并存 {}`n", 1); std::print("原头 {}`n", 2); 返回 0; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果')
  )
}
'stacktrace' = @{ zh = '调用栈'; src = 'stacktrace';
  reason = '铁律③：stacktrace 类型被用户按类型接收/重载。C++23 头，整块进条件壳。';
  a = @(
    @('原样','#如果 _HAS_CXX23'),
    @('原样','使用 调用栈 = std::stacktrace;'),
    @('原样','模板 <类型名 分配器> 使用 基本调用栈 = std::basic_stacktrace<分配器>;'),
    @('原样','使用 栈帧 = std::stacktrace_entry;'),
    @('原样','#结束如果')
  )
  tests = @(
    @('只引中文头','#包含 <调用栈>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::调用栈 甲 = 标准::调用栈::current(); 返回 甲.empty() ? 1 : 0; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果'),
    @('与微软原头并存','#包含 <调用栈>`n#包含 <stacktrace>`n#如果 _HAS_CXX23`n整数 主函数(){ 标准::栈帧 甲 = *标准::调用栈::current().begin(); std::stacktrace_entry 乙 = 甲; (空型)乙; 返回 0; }`n#否则`n整数 主函数(){ 返回 0; }`n#结束如果')
  )
}

# §17.19.33 <chrono>（时间）：时长/时间点/日历/时区的身份参与语义（模板参数被用户代码推导）—— 只能别名
'chrono' = @{ zh = '时间'; src = 'chrono';
  reason = '铁律③：时长/时间点/日历类的身份参与语义（用户按类型重载、模板实参推导、时钟概念约束）。';
  a = @(
    @('原样','模板 <类型名 表示, 类型名 周期 = std::ratio<1>> 使用 时长 = std::chrono::duration<表示, 周期>;'),
    @('原样','模板 <类型名 时钟, 类型名 时长类型 = 类型名 时钟::duration> 使用 时间点 = std::chrono::time_point<时钟, 时长类型>;'),
    @('原样','模板 <类型名 值类型> 使用 视为浮点 = std::chrono::treat_as_floating_point<值类型>;'),
    @('原样','模板 <类型名 表示> 使用 时长取值 = std::chrono::duration_values<表示>;'),
    @('原样','模板 <类型名 甲, 类型名 乙> 使用 时钟时间转换 = std::chrono::clock_time_conversion<甲, 乙>;'),
    @('原样','模板 <类型名 值类型> 使用 是时钟 = std::chrono::is_clock<值类型>;'),
    @('原样','使用 系统时钟 = std::chrono::system_clock;'),
    @('原样','使用 稳定时钟 = std::chrono::steady_clock;'),
    @('原样','使用 高精度时钟 = std::chrono::high_resolution_clock;'),
    @('原样','使用 世界协调时钟 = std::chrono::utc_clock;'),
    @('原样','使用 国际原子时钟 = std::chrono::tai_clock;'),
    @('原样','使用 全球定位时钟 = std::chrono::gps_clock;'),
    @('原样','使用 文件时钟 = std::chrono::file_clock;'),
    @('原样','使用 本地时间类型 = std::chrono::local_t;'),
    @('原样','模板 <类型名 目标时长, 类型名 表示, 类型名 周期> 声明类型(自动) 时长转换(const std::chrono::duration<表示, 周期>& 甲) { 返回 std::chrono::duration_cast<目标时长>(甲); }'),
    @('原样','模板 <类型名 目标时间点, 类型名 时钟, 类型名 时长类型> 声明类型(自动) 时间点转换(const std::chrono::time_point<时钟, 时长类型>& 甲) { 返回 std::chrono::time_point_cast<目标时间点>(甲); }'),
    @('原样','模板 <类型名 目标时钟, 类型名 源时钟, 类型名 时长类型> 声明类型(自动) 时钟转换(const std::chrono::time_point<源时钟, 时长类型>& 甲) { 返回 std::chrono::clock_cast<目标时钟>(甲); }'),
    @('原样','模板 <类型名 目标时长, 类型名 表示, 类型名 周期> 声明类型(自动) 时长下取整(const std::chrono::duration<表示, 周期>& 甲) { 返回 std::chrono::floor<目标时长>(甲); }'),
    @('原样','模板 <类型名 目标时长, 类型名 表示, 类型名 周期> 声明类型(自动) 时长上取整(const std::chrono::duration<表示, 周期>& 甲) { 返回 std::chrono::ceil<目标时长>(甲); }'),
    @('原样','模板 <类型名 目标时长, 类型名 表示, 类型名 周期> 声明类型(自动) 时长四舍五入(const std::chrono::duration<表示, 周期>& 甲) { 返回 std::chrono::round<目标时长>(甲); }'),
    @('原样','模板 <类型名 时长类型> 声明类型(自动) 时长绝对值(const 时长类型& 甲) { 返回 std::chrono::abs(甲); }'),
    @('原样','使用 日 = std::chrono::day;'),
    @('原样','使用 月 = std::chrono::month;'),
    @('原样','使用 年 = std::chrono::year;'),
    @('原样','使用 星期 = std::chrono::weekday;'),
    @('原样','使用 最后标记 = std::chrono::last_spec;'),
    @('常量','最后','std::chrono::last','std::chrono::last_spec'),
    @('原样','使用 带序星期 = std::chrono::weekday_indexed;'),
    @('原样','使用 末星期 = std::chrono::weekday_last;'),
    @('原样','使用 月日 = std::chrono::month_day;'),
    @('原样','使用 月末日 = std::chrono::month_day_last;'),
    @('原样','使用 月星期 = std::chrono::month_weekday;'),
    @('原样','使用 月末星期 = std::chrono::month_weekday_last;'),
    @('原样','使用 年月 = std::chrono::year_month;'),
    @('原样','使用 年月日 = std::chrono::year_month_day;'),
    @('原样','使用 年月末日 = std::chrono::year_month_day_last;'),
    @('原样','使用 年月星期 = std::chrono::year_month_weekday;'),
    @('原样','使用 年月末星期 = std::chrono::year_month_weekday_last;'),
    @('原样','使用 时分秒 = std::chrono::hh_mm_ss<std::chrono::seconds>;'),
    @('原样','使用 时区 = std::chrono::time_zone;'),
    @('原样','使用 时区链接 = std::chrono::time_zone_link;'),
    @('原样','使用 带时区时间 = std::chrono::zoned_time<std::chrono::seconds>;'),
    @('原样','使用 时区库 = std::chrono::tzdb;'),
    @('原样','使用 时区库表 = std::chrono::tzdb_list;'),
    @('原样','使用 闰秒 = std::chrono::leap_second;'),
    @('原样','使用 闰秒信息 = std::chrono::leap_second_info;'),
    @('原样','使用 系统时间信息 = std::chrono::sys_info;'),
    @('原样','使用 本地时间信息 = std::chrono::local_info;'),
    @('原样','使用 不存在本地时间 = std::chrono::nonexistent_local_time;'),
    @('原样','使用 有歧义本地时间 = std::chrono::ambiguous_local_time;'),
    @('原样','使用 择时 = std::chrono::choose;'),
    @('常量','最早','std::chrono::choose::earliest','std::chrono::choose'),
    @('常量','最晚','std::chrono::choose::latest','std::chrono::choose'),
    @('原样','声明类型(自动) 当前时区() { 返回 std::chrono::current_zone(); }'),
    @('原样','声明类型(自动) 查找时区(const char* 甲) { 返回 std::chrono::locate_zone(甲); }'),
    @('原样','声明类型(自动) 取时区库() { 返回 std::chrono::get_tzdb(); }'),
    @('原样','声明类型(自动) 取时区库表() { 返回 std::chrono::get_tzdb_list(); }'),
    @('原样','模板 <类型名 时长类型> 声明类型(自动) 取闰秒信息(const std::chrono::utc_time<时长类型>& 甲) { 返回 std::chrono::get_leap_second_info(甲); }'),
    @('原样','模板 <类型名 时长类型> 声明类型(自动) 造带时区时间(const std::chrono::time_zone* 甲, const std::chrono::sys_time<时长类型>& 乙) { 返回 std::chrono::zoned_time<时长类型>(甲, 乙); }')
  )
  tests = @(
    @('只引中文头','#包含 <时间>`n整数 主函数(){ 标准::时长<整数, std::ratio<1>> 甲{3}; 标准::时长<长整型, std::milli> 乙 = 标准::时长转换<标准::时长<长整型, std::milli>>(甲); 自动 丙 = 标准::时间点<标准::系统时钟>{}; (空型)丙; 返回 乙.count() == 3000 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <时间>`n#包含 <chrono>`n整数 主函数(){ 标准::年月日 甲{标准::年{2026}, 标准::月{2}, 标准::日{14}}; std::chrono::year_month_day 乙 = 甲; 返回 乙.ok() ? 0 : 1; }')
  )
}

# §17.19.32 <functional>（函数对象）：类型身份参与语义（调用运算符 + 继承 std 的基类），只能别名
'functional' = @{ zh = '函数对象'; src = 'functional';
  reason = '铁律③：function/reference_wrapper/各算术函数对象的身份参与语义（用户继承 + 重载解析按类型）。';
  #  欠账（§17.19.32）：move_only_function 是 C++23、unary_function/binary_function 是 C++17 已删除；
  #  别名轨道没有条件壳，本条目暂不收纳 —— 消除路径：等别名轨道支持 #if _HAS_CXX23 条件块后补回。
  a = @(
    @('原样','模板 <类型名 值类型 = 空型> 使用 加 = std::plus<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 减 = std::minus<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 乘 = std::multiplies<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 除 = std::divides<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 取余 = std::modulus<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 取负 = std::negate<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 等于 = std::equal_to<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 不相等 = std::not_equal_to<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 大于 = std::greater<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 小于 = std::less<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 大于等于 = std::greater_equal<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 小于等于 = std::less_equal<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 逻辑与 = std::logical_and<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 逻辑或 = std::logical_or<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 逻辑非 = std::logical_not<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 按位与 = std::bit_and<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 按位或 = std::bit_or<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 按位异或 = std::bit_xor<值类型>;'),
    @('原样','模板 <类型名 值类型 = 空型> 使用 按位非 = std::bit_not<值类型>;'),
    @('原样','模板 <类型名 签名> 使用 函数包装 = std::function<签名>;'),
    @('原样','使用 函数调用异常 = std::bad_function_call;'),
    @('原样','模板 <类型名 值类型> 使用 引用包装 = std::reference_wrapper<值类型>;'),
    @('原样','模板 <类型名 值类型> 声明类型(自动) 引用化(值类型& 甲) 不抛出 { 返回 std::ref(甲); }'),
    @('原样','模板 <类型名 值类型> 声明类型(自动) 常量引用化(const 值类型& 甲) 不抛出 { 返回 std::cref(甲); }'),
    @('原样','模板 <类型名 函数, 类型名... 参数> 声明类型(自动) 绑定(函数&& 甲, 参数&&... 乙) { 返回 std::bind(static_cast<函数&&>(甲), static_cast<参数&&>(乙)...); }'),
    @('原样','模板 <类型名 值类型> 使用 是绑定表达式 = std::is_bind_expression<值类型>;'),
    @('原样','模板 <类型名 值类型> 使用 是占位符 = std::is_placeholder<值类型>;'),
    @('原样','模板 <类型名 成员函数> 声明类型(自动) 成员函数包装(成员函数 甲) 不抛出 { 返回 std::mem_fn(甲); }'),
    @('原样','模板 <类型名 函数> 声明类型(自动) 否定包装(函数&& 甲) { 返回 std::not_fn(static_cast<函数&&>(甲)); }'),
    @('原样','模板 <类型名 函数, 类型名... 参数> 声明类型(自动) 调用(函数&& 甲, 参数&&... 乙) { 返回 std::invoke(static_cast<函数&&>(甲), static_cast<参数&&>(乙)...); }'),
    @('原样','使用 恒等 = std::identity;'),
    @('原样','模板 <类型名 值类型> 使用 散列器 = std::hash<值类型>;'),
    @('原样','模板 <类型名 元素, 类型名 谓词> 使用 默认查找器 = std::default_searcher<元素, 谓词>;'),
    @('原样','模板 <类型名 元素, 类型名 散列, 类型名 相等> 使用 博耶摩尔查找器 = std::boyer_moore_searcher<元素, 散列, 相等>;'),
    @('原样','模板 <类型名 元素, 类型名 散列, 类型名 相等> 使用 博耶摩尔霍斯普尔查找器 = std::boyer_moore_horspool_searcher<元素, 散列, 相等>;')
  )
  tests = @(
    @('只引中文头','#包含 <函数对象>`n整数 主函数(){ 标准::函数包装<整数(整数)> 甲 = [](整数 值) { 返回 值 + 1; }; 返回 甲(6) == 7 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <函数对象>`n#包含 <functional>`n整数 主函数(){ 标准::小于<> 甲; std::less<> 乙; 返回 甲(1, 2) == 乙(1, 2) ? 0 : 1; }')
  )
}
# §17.19.31 <future>（未来）：类型身份参与语义（future 与 promise 共享状态）—— 只能别名
'future' = @{ zh = '未来'; src = 'future';
  reason = '铁律③：future/shared_future/promise/packaged_task 的身份参与语义（共享状态 + 线程交接）。';
  a = @(
    @('原样','模板 <类型名 结果类型> 使用 未来 = std::future<结果类型>;'),
    @('原样','模板 <类型名 结果类型> 使用 共享未来 = std::shared_future<结果类型>;'),
    @('原样','模板 <类型名 结果类型> 使用 承诺 = std::promise<结果类型>;'),
    @('原样','模板 <类型名 签名> 使用 打包任务 = std::packaged_task<签名>;'),
    @('原样','使用 未来状态 = std::future_status;'),
    @('原样','内联 常量表达式 自动 就绪 = std::future_status::ready;'),
    @('原样','内联 常量表达式 自动 未来超时 = std::future_status::timeout;'),
    @('原样','内联 常量表达式 自动 未来延迟 = std::future_status::deferred;'),
    @('原样','使用 启动方式 = std::launch;'),
    @('原样','内联 常量表达式 自动 异步启动 = std::launch::async;'),
    @('原样','内联 常量表达式 自动 延迟启动 = std::launch::deferred;'),
    @('原样','使用 未来错误码 = std::future_errc;'),
    @('原样','使用 未来异常 = std::future_error;'),
    @('原样','模板 <类型名 函数, 类型名... 参数> 声明类型(自动) 异步(函数&& 甲, 参数&&... 乙) { 返回 std::async(static_cast<函数&&>(甲), static_cast<参数&&>(乙)...); }')
  )
  tests = @(
    @('只引中文头','#包含 <未来>`n整数 主函数(){ 标准::承诺<整数> 甲; 自动 乙 = 甲.取未来(); 甲.设置值(7); 返回 乙.取() == 7 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <未来>`n#包含 <future>`n静态断言(std::is_same<标准::未来<整数>, std::future<整数>>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.31 <locale>（本地化）：facet 类型身份参与语义（用户继承 facet + locale 按类型取用）
'locale' = @{ zh = '本地化'; src = 'locale';
  reason = '铁律③：facet 的类型身份决定 locale 取用哪一个；抄一份改名会让 locale 找不到它。';
  a = @(
    @('原样','使用 本地化 = std::locale;'),
    @('原样','使用 字符分类 = std::ctype<字符>;'),
    @('原样','使用 具名字符分类 = std::ctype_byname<字符>;'),
    @('原样','使用 排序规则 = std::collate<字符>;'),
    @('原样','使用 具名排序规则 = std::collate_byname<字符>;'),
    @('原样','使用 数值标点 = std::numpunct<字符>;'),
    @('原样','使用 具名数值标点 = std::numpunct_byname<字符>;'),
    @('原样','使用 货币标点 = std::moneypunct<字符>;'),
    @('原样','使用 货币取值 = std::money_get<字符>;'),
    @('原样','使用 货币放值 = std::money_put<字符>;'),
    @('原样','使用 时间取值 = std::time_get<字符>;'),
    @('原样','使用 时间放值 = std::time_put<字符>;'),
    @('原样','使用 消息目录 = std::messages<字符>;'),
    @('原样','使用 编码转换面 = std::codecvt<字符, 字符, std::mbstate_t>;'),
    @('原样','使用 具名编码转换面 = std::codecvt_byname<字符, 字符, std::mbstate_t>;'),
    @('原样','模板 <类型名 面> 声明类型(自动) 取面(const 本地化& 甲) { 返回 std::use_facet<面>(甲); }'),
    @('原样','模板 <类型名 面> 布尔 有面(const 本地化& 甲) 不抛出 { 返回 std::has_facet<面>(甲); }')
  )
  tests = @(
    @('只引中文头','#包含 <本地化>`n整数 主函数(){ 标准::本地化 甲; 返回 标准::有面<标准::数值标点>(甲) ? 0 : 1; }'),
    @('与微软原头并存','#包含 <本地化>`n#包含 <locale>`n静态断言(std::is_same<标准::本地化, std::locale>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.29 <strstream>（弃用的串流）—— 铁律③：类型身份参与语义，只能别名
'strstream' = @{ zh = '串流'; src = 'strstream';
  reason = '铁律③ + C++17 起弃用：strstreambuf/istrstream 都是 std 的类，派生/改名会与 std 的继承链脱钩。';
  a = @(
    @('原样','使用 串流缓冲 = std::strstreambuf;'),
    @('原样','使用 输入串流 = std::istrstream;'),
    @('原样','使用 输出串流 = std::ostrstream;'),
    @('原样','使用 输入输出串流 = std::strstream;')
  )
  tests = @(
    @('只引中文头','#包含 <串流>`n整数 主函数(){ 标准::输入输出串流 甲; 甲 << 7; 返回 0; }'),
    @('与微软原头并存','#包含 <串流>`n#包含 <strstream>`n静态断言(std::is_same<标准::串流缓冲, std::strstreambuf>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.29 <codecvt>（弃用的编码转换）
'codecvt' = @{ zh = '编码转换'; src = 'codecvt';
  reason = '铁律③：codecvt_utf8 等是 std 的 facet 模板，locale 按类型身份取用。';
  a = @(
    @('原样','使用 编码转换模式 = std::codecvt_mode;'),
    @('原样','内联 常量表达式 自动 编码小端 = std::little_endian;'),
    @('原样','内联 常量表达式 自动 消费头部 = std::consume_header;'),
    @('原样','内联 常量表达式 自动 生成头部 = std::generate_header;'),
    @('原样','模板 <类型名 元素, unsigned long 最大码位 = 0x10ffff, 编码转换模式 模式 = 编码转换模式(0)> 使用 编码转换UTF8 = std::codecvt_utf8<元素, 最大码位, 模式>;'),
    @('原样','模板 <类型名 元素, unsigned long 最大码位 = 0x10ffff, 编码转换模式 模式 = 编码转换模式(0)> 使用 编码转换UTF16 = std::codecvt_utf16<元素, 最大码位, 模式>;'),
    @('原样','模板 <类型名 元素, unsigned long 最大码位 = 0x10ffff, 编码转换模式 模式 = 编码转换模式(0)> 使用 编码转换UTF8至UTF16 = std::codecvt_utf8_utf16<元素, 最大码位, 模式>;')
  )
  tests = @(
    @('只引中文头','#包含 <编码转换>`n整数 主函数(){ 标准::编码转换模式 模式 = 标准::小端; 返回 模式 == 标准::小端 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <编码转换>`n#包含 <codecvt>`n静态断言(std::is_same<标准::编码转换模式, std::codecvt_mode>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.29 <execution>（执行策略）：公开面只有策略类型与四个对象，并行算法本体在 <算法>/<数值算法> 里
'execution' = @{ zh = '执行策略'; src = 'execution';
  reason = '铁律③：策略类型身份参与语义（并行算法按它的类型重载）。';
  a = @(
    @('原样','模板 <类型名 策略类型> 使用 是执行策略 = std::is_execution_policy<策略类型>;'),
    @('原样','使用 顺序策略 = std::execution::sequenced_policy;'),
    @('原样','使用 并行策略 = std::execution::parallel_policy;'),
    @('原样','使用 并行无序策略 = std::execution::parallel_unsequenced_policy;'),
    @('原样','使用 无序执行策略 = std::execution::unsequenced_policy;'),
    @('原样','内联 常量 自动& 顺序执行 = std::execution::seq;'),
    @('原样','内联 常量 自动& 并行执行 = std::execution::par;'),
    @('原样','内联 常量 自动& 并行无序执行 = std::execution::par_unseq;'),
    @('原样','内联 常量 自动& 无序执行 = std::execution::unseq;')
  )
  tests = @(
    @('只引中文头','#包含 <执行策略>`n整数 主函数(){ 返回 标准::是执行策略<标准::顺序策略>::value ? 0 : 1; }'),
    @('与微软原头并存','#包含 <执行策略>`n#包含 <execution>`n整数 主函数(){ std::execution::sequenced_policy 甲 = 标准::顺序执行; (空型)甲; 返回 0; }')
  )
}
# §17.19.28 <fstream>（文件流）：家族薄壳
'fstream' = @{ zh = '文件流'; src = 'fstream';
  reason = '铁律③：basic_filebuf/basic_ifstream 等身份参与语义（与 std 流互操作）；正文是成员函数。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','#ifndef _ZH_文件流名字'),
    @('原样','#define _ZH_文件流名字'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础文件缓冲 = std::basic_filebuf<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入文件流 = std::basic_ifstream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出文件流 = std::basic_ofstream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入输出文件流 = std::basic_fstream<元素, 特征>;'),
    @('原样','使用 文件缓冲 = std::filebuf;'),
    @('原样','使用 输入文件流 = std::ifstream;'),
    @('原样','使用 输出文件流 = std::ofstream;'),
    @('原样','使用 输入输出文件流 = std::fstream;'),
    @('原样','使用 宽文件缓冲 = std::wfilebuf;'),
    @('原样','使用 宽输入文件流 = std::wifstream;'),
    @('原样','使用 宽输出文件流 = std::wofstream;'),
    @('原样','使用 宽输入输出文件流 = std::wfstream;'),
    @('原样','#endif // _ZH_文件流名字')
  )
  tests = @(
    @('只引中文头','#包含 <文件流>`n整数 主函数(){ 标准::输入输出文件流 甲; 返回 甲.是打开() ? 1 : 0; }'),
    @('与微软原头并存','#包含 <文件流>`n#包含 <fstream>`n静态断言(std::is_same<标准::输入文件流, std::ifstream>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.28 <syncstream>（同步流）
'syncstream' = @{ zh = '同步流'; src = 'syncstream';
  reason = '铁律③：basic_syncbuf/basic_osyncstream 身份参与语义。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','#ifndef _ZH_同步流名字'),
    @('原样','#define _ZH_同步流名字'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>, 类型名 分配器 = std::allocator<元素>> 使用 基础同步缓冲 = std::basic_syncbuf<元素, 特征, 分配器>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>, 类型名 分配器 = std::allocator<元素>> 使用 基础输出同步流 = std::basic_osyncstream<元素, 特征, 分配器>;'),
    @('原样','使用 同步缓冲 = std::syncbuf;'),
    @('原样','使用 输出同步流 = std::osyncstream;'),
    @('原样','使用 宽同步缓冲 = std::wsyncbuf;'),
    @('原样','使用 宽输出同步流 = std::wosyncstream;'),
    @('原样','#endif // _ZH_同步流名字')
  )
  tests = @(
    @('只引中文头','#包含 <同步流>`n整数 主函数(){ 标准::输出同步流 甲(标准::标准输出流); 甲 << ""同步""; 返回 0; }'),
    @('与微软原头并存','#包含 <同步流>`n#包含 <syncstream>`n静态断言(std::is_same<标准::同步缓冲, std::syncbuf>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.28 <spanstream>（跨度流）
# §17.19.26 <istream>（输入流）：家族薄壳（共享类型块 + 本头独有名字）
'istream' = @{ zh = '输入流'; src = 'istream';
  reason = '铁律③：basic_istream 身份参与语义；<istream> 的正文是成员函数（别名轨道拿不到中文成员名，见 §六第 18 条）。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入输出流 = std::basic_iostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流状态 = std::basic_ios<元素, 特征>;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 输入输出流 = std::iostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','使用 输入输出状态 = std::ios;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','#ifndef _ZH_输入流名字'),
    @('原样','#define _ZH_输入流名字'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 吃掉空白(参数&&... 值) { 返回 std::ws(static_cast<参数&&>(值)...); }'),
    @('原样','#endif // _ZH_输入流名字')
  )
  tests = @(
    @('只引中文头','#包含 <输入流>`n#包含 <字符串流>`n整数 主函数(){ 标准::输入字符串流 甲("  42"); 整数 值 = 0; 甲 >> 标准::吃掉空白 >> 值; 返回 值 == 42 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <输入流>`n#包含 <istream>`n静态断言(std::is_same<标准::输入流, std::istream>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.26 <ostream>（输出流）
'ostream' = @{ zh = '输出流'; src = 'ostream';
  reason = '铁律③：basic_ostream 身份参与语义；endl/ends/flush 是 CRT 契约名（_MRTIMP2）-> 只能转发。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入输出流 = std::basic_iostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流状态 = std::basic_ios<元素, 特征>;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 输入输出流 = std::iostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','使用 输入输出状态 = std::ios;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','#ifndef _ZH_输出流名字'),
    @('原样','#define _ZH_输出流名字'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 行尾流冲刷(参数&&... 值) { 返回 std::endl(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 加终止符(参数&&... 值) { 返回 std::ends(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 流冲刷(参数&&... 值) { 返回 std::flush(static_cast<参数&&>(值)...); }'),
    @('原样','#endif // _ZH_输出流名字')
  )
  tests = @(
    @('只引中文头','#包含 <输出流>`n#包含 <字符串流>`n整数 主函数(){ 标准::输出字符串流 甲; 甲 << 7 << 标准::流冲刷; 返回 甲.字符串() == "7" ? 0 : 1; }'),
    @('与微软原头并存','#包含 <输出流>`n#包含 <ostream>`n静态断言(std::is_same<标准::输出流, std::ostream>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.26 <iostream>（输入输出流）：四个标准流对象用【引用】给出中文名（对象不能 using 别名）
'iostream' = @{ zh = '输入输出流'; src = 'iostream';
  reason = '铁律③：cin/cout/cerr/clog 是 std 的对象，只能引用/别名，不能另起一份。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入输出流 = std::basic_iostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流状态 = std::basic_ios<元素, 特征>;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 输入输出流 = std::iostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','使用 输入输出状态 = std::ios;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','#ifndef _ZH_标准流对象'),
    @('原样','#define _ZH_标准流对象'),
    @('原样','内联 自动& 标准输入流 = std::cin;'),
    @('原样','内联 自动& 标准输出流 = std::cout;'),
    @('原样','内联 自动& 标准错误流 = std::cerr;'),
    @('原样','内联 自动& 标准日志流 = std::clog;'),
    @('原样','内联 自动& 宽标准输入流 = std::wcin;'),
    @('原样','内联 自动& 宽标准输出流 = std::wcout;'),
    @('原样','内联 自动& 宽标准错误流 = std::wcerr;'),
    @('原样','内联 自动& 宽标准日志流 = std::wclog;'),
    @('原样','#endif // _ZH_标准流对象')
  )
  tests = @(
    @('只引中文头','#包含 <输入输出流>`n整数 主函数(){ 标准::标准输出流 << ""甲""; 返回 0; }'),
    @('与微软原头并存','#包含 <输入输出流>`n#包含 <iostream>`n整数 主函数(){ std::cout << ""乙""; 标准::标准输出流 << ""丙""; 返回 0; }')
  )
}
# §17.19.26 <streambuf>（流缓冲）
'streambuf' = @{ zh = '流缓冲'; src = 'streambuf';
  reason = '铁律③：basic_streambuf 身份参与语义（流都从它派生）。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入输出流 = std::basic_iostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流状态 = std::basic_ios<元素, 特征>;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 输入输出流 = std::iostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','使用 输入输出状态 = std::ios;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','使用 宽流缓冲 = std::wstreambuf;')
  )
  tests = @(
    @('只引中文头','#包含 <流缓冲>`n整数 主函数(){ 标准::流缓冲* 针 = 空指针; 返回 针 == 空指针 ? 0 : 1; }'),
    @('与微软原头并存','#包含 <流缓冲>`n#包含 <streambuf>`n静态断言(std::is_same<标准::流缓冲, std::streambuf>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.25 <ios>（输入输出状态）：操纵器是 CRT 契约名（_MRTIMP2）-> 转发到 std；类型名走共享别名（#ifndef 一主一从）。
'ios' = @{ zh = '输入输出状态'; src = 'ios';
  reason = '铁律③：ios_base/basic_ios 身份参与语义（流的状态位、locale 绑定都挂在它上面）；操纵器（boolalpha 等）是 CRT 提供的（_MRTIMP2），改名会链不上（§17.19.24 实测）。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流状态 = std::basic_ios<元素, 特征>;'),
    @('原样','使用 输入输出状态 = std::ios;'),
    @('原样','使用 输入输出基类 = std::ios_base;'),
    @('原样','#endif // _ZH_流类型名'),
    @('原样','#ifndef _ZH_流操纵器'),
    @('原样','#define _ZH_流操纵器'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 布尔文本(参数&&... 值) { 返回 std::boolalpha(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 非布尔文本(参数&&... 值) { 返回 std::noboolalpha(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 显示基数(参数&&... 值) { 返回 std::showbase(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 不显示基数(参数&&... 值) { 返回 std::noshowbase(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 显示正号(参数&&... 值) { 返回 std::showpos(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 不显示正号(参数&&... 值) { 返回 std::noshowpos(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 跳过空白(参数&&... 值) { 返回 std::skipws(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 不跳过空白(参数&&... 值) { 返回 std::noskipws(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 大写输出(参数&&... 值) { 返回 std::uppercase(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 非大写输出(参数&&... 值) { 返回 std::nouppercase(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 左对齐(参数&&... 值) { 返回 std::left(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 右对齐(参数&&... 值) { 返回 std::right(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 置十进制(参数&&... 值) { 返回 std::dec(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 置十六进制(参数&&... 值) { 返回 std::hex(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 八进制(参数&&... 值) { 返回 std::oct(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 置定点(参数&&... 值) { 返回 std::fixed(static_cast<参数&&>(值)...); }'),
    @('原样','模板 <类型名... 参数> 声明类型(自动) 科学计数(参数&&... 值) { 返回 std::scientific(static_cast<参数&&>(值)...); }'),
    @('原样','#endif // _ZH_流操纵器')
  )
  tests = @(
    @('只引中文头','#包含 <输入输出状态>`n#包含 <字符串流>`n整数 主函数(){ 标准::输出字符串流 甲; 甲 << 标准::置十六进制 << 255; 返回 甲.字符串() == "ff" ? 0 : 1; }'),
    @('与微软原头并存','#包含 <输入输出状态>`n#包含 <ios>`n#包含 <字符串流>`n整数 主函数(){ 标准::输出字符串流 甲; std::ostringstream 乙; 甲 << 标准::置十六进制 << 255; 乙 << std::hex << 255; 返回 甲.字符串().尺寸() == 乙.str().size() ? 0 : 1; }'),
    @('类型身份与 std 一致（铁律③）','#包含 <输入输出状态>`n静态断言(std::is_same<标准::输入输出状态, std::ios>::value, "");`n整数 主函数(){ 返回 0; }')
  )
}
# §17.19.25 <iosfwd>（输入输出前置）：纯前置声明 —— 类型身份必须指向 std（铁律③/④），只能别名。
#   它也是 iostream 家族的【地基】：先把这一族的中文名在这里定死，
#   <ios>/<istream>/<ostream>/<iostream>/<streambuf> 等后续薄壳直接复用，避免"两个副本"。
'iosfwd' = @{ zh = '输入输出前置'; src = 'iosfwd';
  reason = '铁律③：这里只有前置声明，类型必须就是 std 那一个（用户拿它当形参、与 std 流互操作）；抄一份改名会让同一类型出现两个身份。';
  a = @(
    @('原样','#ifndef _ZH_流类型名'),
    @('原样','#define _ZH_流类型名'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入流 = std::basic_istream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输出流 = std::basic_ostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础输入输出流 = std::basic_iostream<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流缓冲 = std::basic_streambuf<元素, 特征>;'),
    @('原样','模板 <类型名 元素, 类型名 特征 = std::char_traits<元素>> 使用 基础流状态 = std::basic_ios<元素, 特征>;'),
    @('原样','模板 <类型名 状态类型> 使用 文件位置 = std::fpos<状态类型>;'),
    @('原样','使用 流位置 = std::streampos;'),
    @('原样','使用 流偏移 = std::streamoff;'),
    @('原样','使用 流尺寸 = std::streamsize;'),
    @('原样','使用 宽流位置 = std::wstreampos;'),
    @('原样','使用 输入流 = std::istream;'),
    @('原样','使用 输出流 = std::ostream;'),
    @('原样','使用 输入输出流 = std::iostream;'),
    @('原样','使用 流缓冲 = std::streambuf;'),
    @('原样','使用 输入输出状态 = std::ios;'),
    @('原样','#endif // _ZH_流类型名')
  )
  tests = @(
    @('只引中文头 + 必须是同一个类型（铁律③）','#包含 <输入输出前置>`n静态断言(std::is_same<标准::输入流, std::istream>::value, "");`n静态断言(std::is_same<标准::流尺寸, std::streamsize>::value, "");`n整数 主函数(){ 返回 0; }'),
    @('与微软原头并存','#包含 <输入输出前置>`n#包含 <iosfwd>`n整数 主函数(){ 标准::流偏移 甲 = 0; std::streamoff 乙 = 甲; return 乙 == 0 ? 0 : 1; }'),
    @('基础模板能当前置类型用','#包含 <输入输出前置>`n整数 主函数(){ 标准::基础输入流<字符>* 针 = 空指针; 返回 针 == 空指针 ? 0 : 1; }')
  )
}
  # §17.27.34/35：std::pmr 是【互操作面】—— memory_resource 身份参与语义（用户继承 + 跨 std/pmr 边界），
  #   pmr 的自由函数是互操作入口。按铁律③【只能别名】，不抄正文。
  'memory_resource' = @{ zh = '内存资源'; src = 'memory_resource';
    reason = '铁律③：memory_resource 身份参与语义，抄一份改名会让同一批符号在我们与真头里签名不一致（§17.27.34 实测：类型冲突）。'; a = @(
      @('原样','使用 内存资源 = std::pmr::memory_resource;'),
      @('原样','使用 内存资源指针 = std::pmr::memory_resource*;'),
      @('原样','模板 <类型名 某类型> 使用 多态分配器 = std::pmr::polymorphic_allocator<某类型>;'),
      @('原样','内联 内存资源指针 取默认资源() noexcept { 返回 std::pmr::get_default_resource(); }'),
      @('原样','内联 内存资源指针 新建删除资源() noexcept { 返回 std::pmr::new_delete_resource(); }'),
      @('原样','内联 内存资源指针 空内存资源() noexcept { 返回 std::pmr::null_memory_resource(); }'),
      @('原样','内联 内存资源指针 设默认资源(内存资源指针 新默认) noexcept { 返回 std::pmr::set_default_resource(新默认); }')
  )
    tests = @(
      @('只引中文头（别名可用）','#包含 <内存资源>`n整数 主函数(){ 标准::内存资源指针 资 = 标准::取默认资源(); 标准::多态分配器<整数> 分; (空型)分; 返回 资 ? 0 : 1; }'),
      @('与 <memory_resource> 并存','#包含 <内存资源>`n#包含 <memory_resource>`n整数 主函数(){ std::pmr::memory_resource* 甲 = 标准::空内存资源(); 标准::内存资源指针 乙 = std::pmr::get_default_resource(); 返回 (整数)(甲 == 乙) - 1; }')
    )
  }
  'coroutine' = @{ zh = '协程'; src = 'coroutine'; a = @(
      # 只能别名（铁律 4）：co_await / co_return 由【编译器】转写，
      # 它要的是 std::coroutine_traits / std::coroutine_handle 本身，换类型就断。
      @('原样','模板 <类型名 承诺 = 空型> 使用 协程句柄 = std::coroutine_handle<承诺>;'),
      @('原样','模板 <类型名 结果, 类型名... 参数> 使用 协程特征 = std::coroutine_traits<结果, 参数...>;'),
      @('原样','使用 始终挂起 = std::suspend_always;'),
      @('原样','使用 从不挂起 = std::suspend_never;'),
      # 成员改不了名 -> 中文自由函数
      @('原样','模板 <类型名 承诺> 内联 布尔 已完成(协程句柄<承诺> 柄) noexcept { 返回 柄.done(); }'),
      @('原样','模板 <类型名 承诺> 内联 空型 恢复(协程句柄<承诺> 柄) { 柄.resume(); }'),
      @('原样','模板 <类型名 承诺> 内联 空型 销毁(协程句柄<承诺> 柄) { 柄.destroy(); }'),
      @('原样','模板 <类型名 承诺> 内联 承诺& 取承诺(协程句柄<承诺> 柄) { 返回 柄.promise(); }'),
      @('原样','模板 <类型名 承诺> 内联 空型* 地址(协程句柄<承诺> 柄) noexcept { 返回 柄.address(); }'),
      @('原样','内联 协程句柄<> 空协程() noexcept { 返回 std::noop_coroutine(); }')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <协程>`n静态断言(std::is_same<标准::协程句柄<>, std::coroutine_handle<>>::value, "");`n整数 主函数(){ 标准::协程句柄<> 柄 = 标准::空协程(); 返回 标准::已完成(柄) ? 0 : 1; }'),
      @('与 <coroutine> 并存','#包含 <协程>`n#包含 <coroutine>`n整数 主函数(){ std::coroutine_handle<> 甲 = 标准::空协程(); 标准::协程句柄<> 乙 = std::noop_coroutine(); 返回 (整数)(甲 == 乙) - 1; }'),
      @('挂起类型 / 恢复 / 地址','#包含 <协程>`n整数 主函数(){ 标准::协程句柄<> 柄 = 标准::空协程(); 空型* 址 = 标准::地址(柄); 标准::恢复(柄); 标准::始终挂起 甲; 标准::从不挂起 乙; (空型)甲; (空型)乙; 返回 址 == 空指针 ? 0 : 0; }')
    )
  }
  'new' = @{ zh = '新建'; src = 'new'; a = @(
      # 异常类型只能别名（铁律 4：捕获按类型匹配）
      @('原样','使用 分配失败 = std::bad_alloc;'),
      @('原样','使用 数组长度分配失败 = std::bad_array_new_length;'),
      # nothrow 家族
      @('原样','使用 分配失败时类型 = std::nothrow_t;'),
      @('原样','内联 常量 分配失败时类型 分配失败时不抛出 = std::nothrow;'),
      # new_handler 家族
      @('原样','使用 分配失败处理函数 = std::new_handler;'),
      @('原样','内联 分配失败处理函数 设分配失败处理函数(分配失败处理函数 处理) noexcept { 返回 std::set_new_handler(处理); }'),
      @('原样','内联 分配失败处理函数 取分配失败处理函数() noexcept { 返回 std::get_new_handler(); }'),
      # 自由函数
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型* 洁净(某类型* 指针) noexcept { 返回 std::launder(指针); }')
  )
    tests = @(
      @('只引中文头 + 异常必须是同一类型（铁律 4）','#包含 <新建>`n静态断言(std::is_same<标准::分配失败, std::bad_alloc>::value, "");`n静态断言(std::is_same<标准::数组长度分配失败, std::bad_array_new_length>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('与 <new> 并存 + 不抛出','#包含 <新建>`n#包含 <new>`n整数 主函数(){ 整数* 甲 = 新建(std::nothrow) 整数; 整数* 乙 = 新建(标准::分配失败时不抛出) 整数; 删除 甲; 删除 乙; 返回 0; }'),
      @('洁净 / new_handler','#包含 <新建>`n整数 主函数(){ 整数 存储; 整数* 甲 = 标准::洁净(&存储); 标准::分配失败处理函数 旧 = 标准::设分配失败处理函数(空指针); 标准::设分配失败处理函数(旧); 返回 0; }')
    )
  }
  'exception' = @{ zh = '异常'; src = 'exception'; a = @(
      # 只能别名（铁律 4）：异常类型的【身份】参与语义 —— 捕获是按类型匹配的。
      # 抄一份再派生等于造了第二个异常体系：catch (std::exception&) 抓不到它。
      @('原样','使用 异常 = std::exception;'),
      @('原样','使用 坏异常 = std::bad_exception;'),
      @('原样','使用 变体访问失败 = std::bad_variant_access;'),
      @('原样','使用 异常指针 = std::exception_ptr;'),
      @('原样','使用 嵌套异常 = std::nested_exception;'),
      @('原样','使用 终止处理 = std::terminate_handler;'),
      # ⚠ 分配失败 / 数组长度分配失败 已经在 <新建> 里别名过了，这里【不能】再声明：
      #   汉语别名都落在同一个 标准 里，同名二次声明就是重定义（方案 §3.14）。
      @('函数','当前异常','current_exception'),
      @('函数','造异常指针','make_exception_ptr'),
      @('函数','重抛异常','rethrow_exception'),
      @('函数','抛出并嵌套','throw_with_nested'),
      @('函数','若有嵌套则重抛','rethrow_if_nested'),
      @('函数','终止','terminate'),
      @('函数','取终止函数','get_terminate'),
      @('函数','设置终止函数','set_terminate'),
      @('函数','有未捕获异常','uncaught_exception'),
      @('函数','未捕获异常数','uncaught_exceptions')
  )
    tests = @(
      @('只引中文头 + 异常必须是同一类型（铁律 4）','#包含 <异常>`n静态断言(std::is_same<标准::异常, std::exception>::value, "");`n整数 主函数(){ 尝试 { 抛出 标准::异常(); } 捕获 (常量 标准::异常&) { 返回 0; } 返回 1; }'),
      @('与 <exception> 并存','#包含 <异常>`n#包含 <exception>`n整数 主函数(){ 标准::异常指针 甲 = 标准::当前异常(); std::exception_ptr 乙 = 标准::当前异常(); 布尔 无 = (甲 == 空指针) && (乙 == nullptr); 返回 (整数)无 - 1; }'),
      @('终止 / 未捕获异常数','#包含 <异常>`n整数 主函数(){ 标准::终止处理 旧 = 标准::取终止函数(); 标准::设置终止函数(旧); 整数 数 = 标准::未捕获异常数(); 布尔 有 = 标准::有未捕获异常(); (空型)有; 返回 数; }')
    )
  }
  'system_error' = @{ zh = '系统错误'; src = 'system_error'; a = @(
      # 只能别名（铁律 4）：错误【类别】是 DLL 里的单例，错误码要和返回
      # std::error_code 的英文接口（如 <filesystem>）互通 —— 换类型就断。
      @('原样','使用 错误类别 = std::error_category;'),
      @('原样','使用 错误码 = std::error_code;'),
      @('原样','使用 错误条件 = std::error_condition;'),
      @('原样','使用 系统错误 = std::system_error;'),
      # ⚠ `枚举` 是关键词，所以 errc 不能叫「错误枚举」
      @('原样','使用 错误码值 = std::errc;'),
      @('原样','使用 输入输出错误码 = std::io_errc;'),
      @('函数','造错误码','make_error_code'),
      @('函数','造错误条件','make_error_condition'),
      @('函数','通用类别','generic_category'),
      @('函数','系统类别','system_category'),
      @('函数','输入输出类别','iostream_category')
      # ⚠ 别名层只管【类型名 + 自由函数】，成员名（.value()/.message()）仍是英文 ——
      #   这是别名轨道与抄+派生轨道的分工（方案铁律 4 那一半）。
      #   枚举量（std::errc::invalid_argument 等）也仍是英文，记为妥协。
      # ⚠ 本头还定义了 std::is_error_code_enum / is_error_condition_enum 的特化，
      #   那些是 std 里的模板特化，别名后仍指向真实类型，不需要重发。
  )
    tests = @(
      @('只引中文头 + 错误码必须是同一类型（铁律 4）','#包含 <系统错误>`n静态断言(std::is_same<标准::错误码, std::error_code>::value, "");`n整数 主函数(){ 标准::错误码 码 = 标准::造错误码(标准::错误码值::no_such_file_or_directory); 返回 码.value() == 0 ? 1 : 0; }'),
      @('与 <system_error> 并存','#包含 <系统错误>`n#包含 <system_error>`n整数 主函数(){ 标准::错误码 甲 = 标准::造错误码(std::errc::invalid_argument); std::error_code 乙 = 甲; 标准::错误条件 丙 = 标准::造错误条件(std::errc::invalid_argument); 返回 乙.value() == 丙.value() ? 0 : 1; }'),
      @('系统错误异常 + 三种类别','#包含 <系统错误>`n整数 主函数(){ 标准::错误类别& 类 = 标准::通用类别(); 标准::错误类别& 类2 = 标准::系统类别(); 标准::错误类别& 类3 = 标准::输入输出类别(); 布尔 同 = (&类 != &类2) && (&类2 != &类3); 尝试 { 抛出 标准::系统错误(标准::错误码值::invalid_argument); } 捕获 (常量 标准::系统错误& 错) { 返回 同 ? 错.code().value() : 1; } 返回 1; }')
    )
  }
  'stdexcept' = @{ zh = '标准异常'; src = 'stdexcept'; a = @(
      # 只能别名（铁律 4）：整条异常继承链的身份参与语义 —— 捕获按类型匹配。
      # 抄一份派生就等于造了一条平行继承链，catch (std::logic_error&) 抓不到。
      @('原样','使用 逻辑错误 = std::logic_error;'),
      @('原样','使用 定义域错误 = std::domain_error;'),
      @('原样','使用 无效实参 = std::invalid_argument;'),
      @('原样','使用 长度错误 = std::length_error;'),
      @('原样','使用 越界错误 = std::out_of_range;'),
      @('原样','使用 运行时错误 = std::runtime_error;'),
      @('原样','使用 上溢错误 = std::overflow_error;'),
      @('原样','使用 下溢错误 = std::underflow_error;'),
      @('原样','使用 范围错误 = std::range_error;')
      # ⚠ 别名层只覆盖类型名：what() 仍是英文成员名（别名轨道的固有边界，见方案 §六第 18 条）
  )
    tests = @(
      @('只引中文头 + 继承链必须是同一条（铁律 4）','#包含 <标准异常>`n静态断言(std::is_same<标准::越界错误, std::out_of_range>::value, "");`n静态断言(std::is_base_of<标准::逻辑错误, 标准::越界错误>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('与 <stdexcept> 并存 + 中文捕获英文异常','#包含 <标准异常>`n#包含 <stdexcept>`n整数 主函数(){ 尝试 { 抛出 std::out_of_range(""x""); } 捕获 (常量 标准::越界错误& 错) { 返回 错.what() == 空指针 ? 1 : 0; } 返回 1; }'),
      @('九种异常都能构造','#包含 <标准异常>`n整数 主函数(){ 标准::逻辑错误 甲(""a""); 标准::定义域错误 乙(""b""); 标准::无效实参 丙(""c""); 标准::长度错误 丁(""d""); 标准::越界错误 戊(""e""); 标准::运行时错误 己(""f""); 标准::上溢错误 庚(""g""); 标准::下溢错误 辛(""h""); 标准::范围错误 壬(""i""); 返回 0; }')
    )
  }
  'array' = @{ zh = '数组'; src = 'array'; reason = 'std::array 是【聚合】，且结构化绑定走 std::tuple_size / tuple_element 的【特化】；抄一份再派生会同时丢掉聚合性（花括号初始化）和结构化绑定。'; a = @(
      # 只能别名（铁律 4）：std::array 是【聚合】，而且结构化绑定走
      # std::tuple_size / tuple_element 的【特化】。
      # 抄一份再派生会同时丢掉聚合性（花括号初始化）与结构化绑定 ——
      # 所以这个头【没有】中文成员名，这是别名轨道的固有代价（§六第 18 条）。
      @('原样','模板 <类型名 元素, size_t 尺寸> 使用 数组 = std::array<元素, 尺寸>;'),
      # get<I>(array)：与 <元组> 里的 取 是【重载】（参数类型不同），可以同名共存
      @('原样','模板 <size_t 下标, 类型名 元素, size_t 尺寸> 内联 自动& 取(std::array<元素, 尺寸>& 组) noexcept { 返回 std::get<下标>(组); }'),
      @('原样','模板 <size_t 下标, 类型名 元素, size_t 尺寸> 内联 常量 自动& 取(常量 std::array<元素, 尺寸>& 组) noexcept { 返回 std::get<下标>(组); }'),
      # to_array
      @('原样','模板 <类型名 元素, size_t 尺寸> 内联 常量表达式 自动 转数组(元素 (&甲)[尺寸]) { 返回 std::to_array(甲); }'),
      @('原样','模板 <类型名 元素, size_t 尺寸> 内联 常量表达式 自动 转数组(元素 (&&甲)[尺寸]) { 返回 std::to_array(static_cast<元素 (&&)[尺寸]>(甲)); }')
  )
    tests = @(
      @('只引中文头 + 必须是同一个类型（铁律 4）','#包含 <数组>`n静态断言(std::is_same<标准::数组<整数, 3>, std::array<int, 3>>::value, "");`n整数 主函数(){ 标准::数组<整数, 3> 甲{1, 2, 3}; 整数 乙 = 标准::取<1>(甲); 返回 乙 + (整数)甲.size() - 5; }'),
      @('结构化绑定必须能用（这就是不能用抄+派生的理由）','#包含 <数组>`n整数 主函数(){ 标准::数组<整数, 2> 甲{4, 5}; 自动 [甲0, 甲1] = 甲; 返回 甲0 + 甲1 - 9; }'),
      @('转数组 + 与 <array> 并存','#包含 <数组>`n#包含 <array>`n整数 主函数(){ 整数 原[3] = {1, 2, 3}; 自动 甲 = 标准::转数组(原); std::array<int, 3> 乙 = 甲; 返回 (整数)乙[0] + (整数)甲[2] - 4; }')
    )
  }
  'concepts' = @{ zh = '概念'; src = 'concepts'; a = @(
      # ⚠ 命名必须与 <类型特征> 区分开：那边是 traits 用 `是…类型`，
      #   这边是 concepts 用 `…于` / `可…` / `…型`。两者一起 #包含 不能重名（见方案 §2.2.1）。
      @('原样','模板 <类型名 甲, 类型名 乙> 概念 相同于 = std::same_as<甲, 乙>;'),
      @('原样','模板 <类型名 派生, 类型名 基> 概念 派生自 = std::derived_from<派生, 基>;'),
      @('原样','模板 <类型名 从, 类型名 到> 概念 可转换到 = std::convertible_to<从, 到>;'),
      @('原样','模板 <类型名 甲, 类型名 乙> 概念 公共于 = std::common_with<甲, 乙>;'),
      @('原样','模板 <类型名 某类型> 概念 整数型 = std::integral<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 有符号整数型 = std::signed_integral<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 无符号整数型 = std::unsigned_integral<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 浮点型 = std::floating_point<某类型>;'),
      @('原样','模板 <类型名 某类型, 类型名 从> 概念 可赋值自 = std::assignable_from<某类型, 从>;'),
      @('原样','模板 <类型名 某类型> 概念 可交换 = std::swappable<某类型>;'),
      @('原样','模板 <类型名 甲, 类型名 乙> 概念 可与交换 = std::swappable_with<甲, 乙>;'),
      @('原样','模板 <类型名 某类型> 概念 可析构 = std::destructible<某类型>;'),
      @('原样','模板 <类型名 某类型, 类型名... 参数> 概念 可构造自 = std::constructible_from<某类型, 参数...>;'),
      @('原样','模板 <类型名 某类型> 概念 可默认初始化 = std::default_initializable<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 可移动构造 = std::move_constructible<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 可复制构造 = std::copy_constructible<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 可相等比较 = std::equality_comparable<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 全序 = std::totally_ordered<某类型>;'),
      @('原样','模板 <类型名 函数, 类型名... 参数> 概念 可调用 = std::invocable<函数, 参数...>;'),
      @('原样','模板 <类型名 函数, 类型名... 参数> 概念 谓词 = std::predicate<函数, 参数...>;'),
      @('原样','模板 <类型名 某类型> 概念 正规 = std::regular<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 半正规 = std::semiregular<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 可移动 = std::movable<某类型>;'),
      @('原样','模板 <类型名 某类型> 概念 可复制 = std::copyable<某类型>;')
  )
    tests = @(
      @('只引中文头','#包含 <概念>`n静态断言(标准::整数型<整数>, "");`n静态断言(标准::浮点型<双精度>, "");`n静态断言(!标准::整数型<双精度>, "");`n整数 主函数(){ 返回 0; }'),
      @('与 <concepts> 并存','#包含 <概念>`n#包含 <concepts>`n静态断言(标准::整数型<整数> == std::integral<int>, "");`n整数 主函数(){ 返回 0; }'),
      @('与 <类型特征> 并存（不重名，关键）','#包含 <概念>`n#包含 <类型特征>`n模板 <类型名 某类型> 要求 标准::整数型<某类型> 整数 取(某类型 值){ 返回 (整数)值; }`n整数 主函数(){ 静态断言(标准::是整数类型<整数>::value, ""); 返回 取(5) - 5; }')
    )
  }
  'bit' = @{ zh = '位'; src = 'bit'; a = @(
      # 枚举类型与枚举值：类型别名 + 常量承载枚举值
      @('原样','使用 字节序 = std::endian;'),
      @('原样','内联 常量表达式 字节序 小端 = std::endian::little;'),
      @('原样','内联 常量表达式 字节序 大端 = std::endian::big;'),
      @('原样','内联 常量表达式 字节序 本机 = std::endian::native;'),
      # 自由函数：一模板转发
      @('原样','模板 <类型名 到, 类型名 从> 内联 常量表达式 到 位转换(常量 从& 值) noexcept { 返回 std::bit_cast<到>(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 布尔 只有一位(某类型 值) noexcept { 返回 std::has_single_bit(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型 下取整幂(某类型 值) noexcept { 返回 std::bit_floor(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型 上取整幂(某类型 值) noexcept { 返回 std::bit_ceil(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 整数 位宽(某类型 值) noexcept { 返回 (整数)std::bit_width(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型 循环左移(某类型 值, 整数 位) noexcept { 返回 std::rotl(值, 位); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型 循环右移(某类型 值, 整数 位) noexcept { 返回 std::rotr(值, 位); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 整数 左零位数(某类型 值) noexcept { 返回 (整数)std::countl_zero(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 整数 左一位数(某类型 值) noexcept { 返回 (整数)std::countl_one(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 整数 右零位数(某类型 值) noexcept { 返回 (整数)std::countr_zero(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 整数 右一位数(某类型 值) noexcept { 返回 (整数)std::countr_one(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 整数 一位个数(某类型 值) noexcept { 返回 (整数)std::popcount(值); }')
  )
    tests = @(
      @('只引中文头','#包含 <位>`n静态断言(标准::一位个数(7u) == 3, "");`n静态断言(标准::只有一位(8u), "");`n整数 主函数(){ 返回 标准::位宽(8u) - 4; }'),
      @('与 <bit> 并存','#包含 <位>`n#包含 <bit>`n整数 主函数(){ 返回 (整数)std::popcount(7u) + 标准::一位个数(7u) - 6; }'),
      @('位转换 / 字节序 / 循环移位','#包含 <位>`n整数 主函数(){ 单精度 甲 = 1.0f; 无符号整数 乙 = 标准::位转换<无符号整数>(甲); 布尔 丙 = (标准::本机 == std::endian::native); 返回 (整数)(标准::循环左移(乙, 1) != 乙) + (整数)丙 - 1; }')
    )
  }
  'tuple' = @{ zh = '元组'; src = 'tuple'; a = @(
      # 只能别名（铁律 4）：【结构化绑定】走 std::tuple_size / std::tuple_element /
      # std::get 对【那个类型】的特化，换类型就断。
      @('原样','模板 <类型名... 元素> 使用 元组 = std::tuple<元素...>;'),
      @('原样','模板 <类型名... 元素> 内联 自动 造元组(元素&&... 值) { 返回 std::make_tuple(static_cast<元素&&>(值)...); }'),
      @('原样','模板 <size_t 下标, 类型名... 元素> 内联 自动& 取(std::tuple<元素...>& 组) noexcept { 返回 std::get<下标>(组); }'),
      @('原样','模板 <size_t 下标, 类型名... 元素> 内联 常量 自动& 取(常量 std::tuple<元素...>& 组) noexcept { 返回 std::get<下标>(组); }'),
      @('原样','模板 <类型名 元组类型> 内联 常量表达式 size_t 元组大小 = std::tuple_size<元组类型>::value;'),
      @('原样','模板 <size_t 下标, 类型名 元组类型> 使用 元组元素类型 = std::tuple_element_t<下标, 元组类型>;'),
      @('原样','模板 <类型名... 元素> 内联 自动 前接(元素&&... 值) { 返回 std::tuple_cat(static_cast<元素&&>(值)...); }')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <元组>`n静态断言(std::is_same<标准::元组<整数, 双精度>, std::tuple<int, double>>::value, "");`n整数 主函数(){ 自动 组 = 标准::造元组(1, 2); 返回 标准::取<0>(组) - 1; }'),
      @('结构化绑定直接可用（关键）','#包含 <元组>`n整数 主函数(){ 标准::元组<整数, 整数> 组{1, 2}; 自动 [甲, 乙] = 组; 返回 甲 + 乙 - 3; }'),
      @('元组大小 / 元素类型 / 前接','#包含 <元组>`n静态断言(标准::元组大小<标准::元组<整数, 双精度>> == 2, "");`n静态断言(std::is_same<标准::元组元素类型<1, 标准::元组<整数, 双精度>>, 双精度>::value, "");`n整数 主函数(){ 自动 组 = 标准::前接(标准::造元组(1), 标准::造元组(2)); 返回 标准::取<1>(组) - 2; }')
    )
  }
  'type_traits' = @{ zh = '类型特征'; src = 'type_traits'; a = @(
      # 只能别名（铁律 4）：traits 的结果按【类型身份】算，换类型就断。
      # 范围说明（必须的妥协）：这里只做【高频子集】，不是全部几百个 —— 见方案 §六。
      @('原样','使用 真类型 = std::true_type;'),
      @('原样','使用 假类型 = std::false_type;'),
      @('原样','模板 <类型名 甲, 类型名 乙> 使用 是相同类型 = std::is_same<甲, 乙>;'),
      @('原样','模板 <类型名 某类型> 使用 是整数类型 = std::is_integral<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是浮点类型 = std::is_floating_point<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是算术类型 = std::is_arithmetic<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是指针类型 = std::is_pointer<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是引用类型 = std::is_reference<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是常量类型 = std::is_const<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是空型   = std::is_void<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 是类类型 = std::is_class<某类型>;'),
      @('原样','模板 <类型名 基, 类型名 派生> 使用 是基类 = std::is_base_of<基, 派生>;'),
      @('原样','模板 <类型名 从, 类型名 到> 使用 是可转换 = std::is_convertible<从, 到>;'),
      @('原样','模板 <类型名 某类型> 使用 是可平凡复制 = std::is_trivially_copyable<某类型>;'),
      @('原样','模板 <布尔 条件, 类型名 某类型 = 空型> 使用 启用如果 = std::enable_if<条件, 某类型>;'),
      @('原样','模板 <布尔 条件, 类型名 真型, 类型名 假型> 使用 条件类型 = std::conditional<条件, 真型, 假型>;'),
      @('原样','模板 <类型名 某类型> 使用 移除引用 = std::remove_reference<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 移除常量 = std::remove_const<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 移除指针 = std::remove_pointer<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 退化     = std::decay<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 加常量   = std::add_const<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 加左值引用 = std::add_lvalue_reference<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 加右值引用 = std::add_rvalue_reference<某类型>;'),
      @('原样','模板 <类型名 某类型> 使用 底层类型 = std::underlying_type<某类型>;'),
      @('原样','模板 <类型名... 参数> 使用 公共类型 = std::common_type<参数...>;'),
      @('原样','模板 <类型名... 参数> 使用 空型标记 = std::void_t<参数...>;'),
      @('原样','模板 <类型名 某类型, 某类型 值> 使用 整数常量 = std::integral_constant<某类型, 值>;')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <类型特征>`n静态断言(std::is_same<标准::是相同类型<整数, 整数>, std::is_same<int, int>>::value, "");`n静态断言(标准::是整数类型<整数>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('traits 结果与 std 一致','#包含 <类型特征>`n静态断言(标准::是浮点类型<双精度>::value, "");`n静态断言(!标准::是引用类型<整数>::value, "");`n静态断言(std::is_same<标准::移除引用<整数&>, 整数>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('enable_if / conditional / 启用如果','#包含 <类型特征>`n模板 <类型名 某类型> 标准::启用如果<标准::是整数类型<某类型>::value, 整数> 取(某类型 值){ 返回 (整数)值; }`n整数 主函数(){ 返回 取(7) - 7; }')
    )
  }
  'utility' = @{ zh = '工具'; src = 'utility'; a = @(
      # pair 有【公开数据成员】first/second —— 派生补不回英文名（会改布局），
      # 所以只能别名：类型是同一个，成员照旧是 first/second（改名就断）。
      @('原样','模板 <类型名 甲, 类型名 乙> 使用 对 = std::pair<甲, 乙>;'),
      # 成员名改不了 -> 中文自由函数
      @('原样','模板 <类型名 甲, 类型名 乙> 内联 自动& 第一(std::pair<甲, 乙>& 对) noexcept { 返回 对.first; }'),
      @('原样','模板 <类型名 甲, 类型名 乙> 内联 常量 自动& 第一(常量 std::pair<甲, 乙>& 对) noexcept { 返回 对.first; }'),
      @('原样','模板 <类型名 甲, 类型名 乙> 内联 自动& 第二(std::pair<甲, 乙>& 对) noexcept { 返回 对.second; }'),
      @('原样','模板 <类型名 甲, 类型名 乙> 内联 常量 自动& 第二(常量 std::pair<甲, 乙>& 对) noexcept { 返回 对.second; }'),
      # 自由函数：转发到 std 的同名函数（都是模板，泛型转发即可）
      @('原样','模板 <类型名 甲, 类型名 乙> 内联 自动 造对(甲&& 一, 乙&& 二) { 返回 std::make_pair(static_cast<甲&&>(一), static_cast<乙&&>(二)); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型&& 移动(某类型&& 值) noexcept { 返回 static_cast<某类型&&>(值); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 某类型&& 转发(std::remove_reference<某类型>::type&& 值) noexcept { 返回 static_cast<某类型&&>(值); }'),
      @('原样','模板 <类型名 某类型> 内联 空型 交换(某类型& 甲, 某类型& 乙) { std::swap(甲, 乙); }'),
      @('原样','模板 <类型名 某类型, 类型名 别的> 内联 某类型 交换并返回(某类型& 对象, 别的&& 新值) { 返回 std::exchange(对象, static_cast<别的&&>(新值)); }'),
      @('原样','模板 <类型名 某类型> 内联 常量表达式 常量 某类型& 视为常量(某类型& 值) noexcept { 返回 值; }'),
      @('原样','模板 <类型名 某类型, 某类型... 值> 使用 整数序列 = std::integer_sequence<某类型, 值...>;')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <工具>`n静态断言(std::is_same<标准::对<整数, 双精度>, std::pair<int, double>>::value, "");`n整数 主函数(){ 标准::对<整数, 整数> 甲{1, 2}; 返回 标准::第一(甲) - 1; }'),
      @('成员仍是英文名（只能别名，改名就断）','#包含 <工具>`n整数 主函数(){ 标准::对<整数, 整数> 甲{1, 2}; 返回 甲.first + 甲.second - 3; }'),
      @('移动 / 转发 / 交换 / 视为常量 / 交换并返回','#包含 <工具>`n整数 收(整数&& 值){ 返回 值; }`n整数 主函数(){ 整数 甲 = 1, 乙 = 2; 标准::交换(甲, 乙); 常量 整数& 丙 = 标准::视为常量(甲); 整数 丁 = 标准::移动(甲); 整数 戊 = 标准::交换并返回(乙, 9); 返回 收(标准::转发<整数>(丁)) + 丙 + 戊 - 13; }')
    )
  }
  'initializer_list' = @{ zh = '初始化列表'; src = 'initializer_list'; a = @(
      # 必须同一类型：花括号初始化 {1,2,3} 由【编译器】生成 std::initializer_list，
      # 换类型就断（铁律 4）
      @('原样','模板 <类型名 元素>
    使用 初始化列表 = std::initializer_list<元素>;'),
      # 成员改不了名（类型是 std 的）-> 中文自由函数。
      # 形参就写 初始化列表<元素>，于是传 std::initializer_list 也照样收（同一类型）。
      @('原样','模板 <类型名 元素> 内联 自动 开始(初始化列表<元素> 表) noexcept { 返回 表.begin(); }'),
      @('原样','模板 <类型名 元素> 内联 自动 结束(初始化列表<元素> 表) noexcept { 返回 表.end(); }'),
      @('原样','模板 <类型名 元素> 内联 自动 尺寸(初始化列表<元素> 表) noexcept { 返回 表.size(); }')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <初始化列表>`n静态断言(std::is_same<标准::初始化列表<整数>, std::initializer_list<int>>::value, "");`n整数 主函数(){ 标准::初始化列表<整数> 表{1, 2, 3}; 返回 (整数)标准::尺寸(表) - 3; }'),
      @('中文自由函数也收 std 的对象','#包含 <初始化列表>`n#包含 <initializer_list>`n整数 主函数(){ std::initializer_list<int> 乙{1, 2}; 常量 int* 首 = 标准::开始(乙); 返回 (整数)标准::尺寸(乙) + (整数)*首 - 3; }'),
      @('花括号直接传进中文形参','#包含 <初始化列表>`n空型 收(标准::初始化列表<整数> 表){ (空型)表; }`n整数 主函数(){ 收({1, 2, 3}); 返回 0; }')
    )
  }
  'ratio' = @{ zh = '比'; src = 'ratio'; a = @(
      # 必须同一类型：std::chrono 的算术依赖 ratio 的类型身份（铁律 4）
      @('原样','模板 <整数 分子, 整数 分母 = 1>
    使用 比 = std::ratio<分子, 分母>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相加 = std::ratio_add<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相减 = std::ratio_subtract<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相乘 = std::ratio_multiply<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相除 = std::ratio_divide<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比相等 = std::ratio_equal<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比不等 = std::ratio_not_equal<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比小于 = std::ratio_less<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比小于等于 = std::ratio_less_equal<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比大于 = std::ratio_greater<比甲, 比乙>;'),
      @('原样','模板 <类型名 比甲, 类型名 比乙> 使用 比大于等于 = std::ratio_greater_equal<比甲, 比乙>;'),
      # SI 词头（中文标准词头）
      @('原样','使用 阿托 = std::atto;   使用 飞托 = std::femto;  使用 皮可 = std::pico;'),
      @('原样','使用 纳诺 = std::nano;   使用 微   = std::micro;  使用 毫   = std::milli;'),
      @('原样','使用 厘   = std::centi;  使用 分   = std::deci;   使用 十   = std::deca;'),
      @('原样','使用 百   = std::hecto;  使用 千   = std::kilo;   使用 兆   = std::mega;'),
      @('原样','使用 吉   = std::giga;   使用 太   = std::tera;   使用 拍   = std::peta;'),
      @('原样','使用 艾   = std::exa;')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <比>`n静态断言(std::is_same<标准::比<1, 2>, std::ratio<1, 2>>::value, "");`n整数 主函数(){ 返回 (整数)标准::比<1, 2>::num - 1; }'),
      @('与 <ratio> 并存 + SI 词头同类型','#包含 <比>`n#包含 <ratio>`n静态断言(std::is_same<标准::千, std::kilo>::value, "");`n静态断言(std::is_same<标准::毫, std::milli>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('比相加 与 std::ratio_add 同类型','#包含 <比>`n静态断言(std::is_same<标准::比相加<标准::比<1, 2>, 标准::比<1, 3>>, std::ratio_add<std::ratio<1, 2>, std::ratio<1, 3>>>::value, "");`n整数 主函数(){ 返回 0; }')
    )
  }
  'typeinfo' = @{ zh = '类型信息'; src = 'typeinfo'; a = @(
      # 类型：必须同一类型 —— typeid() 返回的就是 std::type_info 的引用（铁律 4）
      @('类型','类型信息','std::type_info'),
      # 异常类型也只能别名：捕获按类型匹配，抄一份/派生就抓不到别人抛的（铁律 4）
      @('类型','类型转换失败','std::bad_cast'),
      @('类型','类型标识失败','std::bad_typeid'),
      # 成员改不了名（类型是 std 的），只能做成中文自由函数
      @('原样','内联 常量 字符* 名称(常量 类型信息& 信息) noexcept { 返回 信息.name(); }'),
      @('原样','内联 size_t 哈希值(常量 类型信息& 信息) noexcept { 返回 信息.hash_code(); }'),
      @('原样','内联 布尔 先于(常量 类型信息& 甲, 常量 类型信息& 乙) noexcept { 返回 甲.before(乙); }'),
      @('原样','内联 布尔 相等(常量 类型信息& 甲, 常量 类型信息& 乙) noexcept { 返回 甲 == 乙; }'),
      @('原样','内联 布尔 不等(常量 类型信息& 甲, 常量 类型信息& 乙) noexcept { 返回 甲 != 乙; }')
  )
    tests = @(
      @('只引中文头（类型别名 + 中文自由函数）','#包含 <类型信息>`n整数 主函数(){ 返回 (整数)标准::哈希值(类型标识(整数)) * 0; }'),
      @('与 <typeinfo> 并存','#包含 <类型信息>`n#包含 <typeinfo>`n整数 主函数(){ 常量 std::type_info& 乙 = 类型标识(整数); 返回 (整数)标准::哈希值(类型标识(整数)) * 0 + (整数)乙.hash_code() * 0; }'),
      @('类型身份必须相同（铁律 4）','#包含 <类型信息>`n静态断言(std::is_same<标准::类型转换失败, std::bad_cast>::value, "");`n静态断言(std::is_same<标准::类型信息, std::type_info>::value, "");`n整数 主函数(){ 返回 0; }')
    )
  }
  # §17.27.60.2（阶段(4) 别名轨道）：<compare> —— 比较类别是【身份参与语义】的类型
  #   用户代码会拿 `<=>` 的结果与 std::strong_ordering::equal 直接比较；抄一份改名会让两侧类型不同，
  #   与 std 的常量比不了（铁律④）。所以只能别名，与 <类型信息>/<比> 同类。
  'compare' = @{ zh = '比较'; src = 'compare'; reason = '铁律④：比较类别身份参与语义 —— 与 std::strong_ordering::equal 直接比较，抄/派生会让两侧类型不同。'; a = @(
      @('类型','强序','std::strong_ordering'),
      @('类型','弱序','std::weak_ordering'),
      @('类型','偏序','std::partial_ordering'),
      # 判定函数：成员在 std 类型上改不了名，做成中文转发（同 <类型信息> 的手法）
      @('函数','是否相等','std::is_eq'),
      @('函数','是否不等','std::is_neq'),
      @('函数','是否小于','std::is_lt'),
      @('函数','是否小于等于','std::is_lteq'),
      @('函数','是否大于','std::is_gt'),
      @('函数','是否大于等于','std::is_gteq')
  )
    tests = @(
      @('只引中文头 + 类型身份相同','#包含 <比较>`n静态断言(std::is_same<标准::强序, std::strong_ordering>::value, "");`n整数 主函数(){ 返回 0; }'),
      @('与 <compare> 并存 + 判定函数可用','#包含 <比较>`n#包含 <compare>`n整数 主函数(){ 自动 果 = 1 <=> 2; 返回 标准::是否小于(果) ? 0 : 1; }'),
      @('弱序 / 偏序 同类型（铁律④ 守卫）','#包含 <比较>`n静态断言(std::is_same<标准::弱序, std::weak_ordering>::value, "");`n静态断言(std::is_same<标准::偏序, std::partial_ordering>::value, "");`n整数 主函数(){ 返回 0; }')
    )
  }
  'numbers' = @{ zh = '数字'; src = 'numbers'; a = @(
      @('常量','圆周率','std::numbers::pi','双精度'),
      @('常量','自然常数','std::numbers::e','双精度'),
      @('常量','欧拉常数','std::numbers::egamma','双精度'),
      @('常量','黄金比例','std::numbers::phi','双精度'),
      @('常量','二的自然对数','std::numbers::ln2','双精度'),
      @('常量','十的自然对数','std::numbers::ln10','双精度'),
      @('常量','以二为底自然常数的对数','std::numbers::log2e','双精度'),
      @('常量','以十为底自然常数的对数','std::numbers::log10e','双精度'),
      @('常量','二的平方根','std::numbers::sqrt2','双精度'),
      @('常量','三的平方根','std::numbers::sqrt3','双精度'),
      @('常量','圆周率的倒数','std::numbers::inv_pi','双精度'),
      @('常量','圆周率平方根的倒数','std::numbers::inv_sqrtpi','双精度'),
      @('常量','三的平方根的倒数','std::numbers::inv_sqrt3','双精度')
  ) }
}

# -ExportJson：把整张表以 JSON 输出后退出（供 tools\make_zh_usage.ps1 生成用法对照表）。
#   用的是【同一张表】、不靠正则扫描 —— 扫描正则会漂移（见 make_zhstdlib2.ps1 同一开关的说明）。
# ---------------------------------------------------------------------------
#  §17.19.30 关键词守卫【别名轨道这一份】—— 第 105 轮实测的缺口：
#  关键词检查住在 make_zhstdlib2.ps1 里，只扫它的表；本轨道的 `原样` 行是手写 C++，
#  于是 `模板 <类型名 类型>`（`类型` 是 class 的汉写）一路走到编译才报「缺少 identifier」。
#  判据：**手写块也要过同一套关键词检查**（与 §17.19.22 补的 extra/prologue 同一条）。
#  关键词表从编译器那份唯一来源 ChineseKeywords.def 读（读不到就用内置危险集兜底）。
# ---------------------------------------------------------------------------
$kw = @{}
$defFile = Join-Path $root 'LLVM-main\clang\include\clang\Basic\ChineseKeywords.def'
if (Test-Path $defFile) {
    #  §17.19.32 缺口修正（第 107 轮实测）：`不等于` 是 ZH_OPERATOR_KEYWORD 的**第一**字段
    #  （ZH_OPERATOR_KEYWORD(不等于, exclaimequal) // != ），旧正则只读第二字段 → 漏报，
    #  于是 `使用 不等于 = std::not_equal_to<...>;` 一路走到编译才报
    #  「不能把 using 声明模板化」——又是从报错看不出是命名问题的老坑。
    #  判据：与 make_zhstdlib2.ps1 同一张表口径 —— 普通关键字读第二字段，运算符关键字读第一字段。
    $defText = [System.IO.File]::ReadAllText($defFile)
    foreach ($m in [regex]::Matches($defText, '(?m)^\s*ZH_(?:KEYWORD|CONTEXTUAL_KEYWORD|VIRT_SPECIFIER)\s*\(\s*[^,]+,\s*([^\s,]+)')) {
        $kw[$m.Groups[1].Value] = $true
    }
    foreach ($m in [regex]::Matches($defText, '(?m)^\s*ZH_OPERATOR_KEYWORD\s*\(\s*([^\s,]+)\s*,')) {
        $kw[$m.Groups[1].Value] = $true
    }
}
if ($kw.Count -eq 0) { foreach ($k in @('类型','类','结构','名域','模板','类型名','使用','自动','整数','字符','空型','常量')) { $kw[$k] = $true } }
#  §17.19.36 第三个缺口：**函数名位置**（本轮实测 `布尔 删除(...)` —— 删除 是 delete 的关键字）。
#  前两个缺口（§17.19.30 别名轨道整条守卫、§17.19.32 运算符关键字）管的都是"名字位置"；
#  函数定义名既不是 `类型名 X` 也不是 `使用 X =`，于是 `删除` 一路走到编译才报「缺少（种类）非限定标识符」。
#  判据：关键词出现在【函数名位置】（左侧不是中文/字母/数字/下划线，右侧直接跟 `(`）一律拦；
#        白名单只放本方言里合法"后跟括号"的关键字用法（声明类型(自动)、返回 (x) 等）。
#  自测（假报和漏报一样坏）：`布尔 删除(x)` 必须命中；`左对齐(x)`、`文件大小(x)` 必须不命中。
$kwAllow = @{ '声明类型' = $true; '返回' = $true; '类型标识' = $true }
$kwSelf = 0
if ('布尔 删除(const char*) {}' -match ('(?<![\w\u4e00-\u9fff])删除\s*\(')) { $kwSelf++ }
if ('声明类型(自动) 左对齐(参数&&... 值)' -notmatch ('(?<![\w\u4e00-\u9fff])对齐\s*\(')) { $kwSelf++ }
if ('声明类型(自动) 文件大小(const char*)' -notmatch ('(?<![\w\u4e00-\u9fff])大小\s*\(')) { $kwSelf++ }
if (-not $ExportJson) { Write-Host ("  [关键词守卫自测] 函数名位置 3 条：{0}/3" -f $kwSelf) }  # 不能污染 -ExportJson 的 stdout
$kwBad = @()
foreach ($k2 in $H.Keys) {
    $lines = @()
    if ($H[$k2].ContainsKey('a')) { foreach ($x in $H[$k2].a) { if ($x.Count -ge 2) { $lines += [string]$x[1] } } }
    foreach ($ln in $lines) {
        foreach ($k in $kw.Keys) {
            if ($ln -match ('类型名\s*(?:\.\.\.)?\s*' + [regex]::Escape($k) + '(?![\w\u4e00-\u9fff])') -or
                $ln -match ('使用\s+' + [regex]::Escape($k) + '\s*=') -or (($ln -match ('(?<![\w\u4e00-\u9fff])' + [regex]::Escape($k) + '\s*\(')) -and -not $kwAllow.ContainsKey($k))) {
                $kwBad += ("  [{0}] 原样行里 '{1}' 在【名字位置】—— 它是关键词：{2}" -f $k2, $k, $ln.Trim())
            }
        }
    }
}
if ($kwBad.Count) {
    Write-Host "❌ 别名轨道的原样行里有中文名撞关键词：" -ForegroundColor Red
    $kwBad | Sort-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw "别名轨道关键词撞车，先改名再生成"
}
if ($ExportJson) { $H | ConvertTo-Json -Depth 8; exit 0 }

$spec = $H[$Header]
if (-not $spec) { throw "表里没有 $Header" }

$body = @(); $n = @{ '常量'=0; '类型'=0; '函数'=0; '原样'=0 }
foreach ($e in $spec.a) {
    switch ($e[0]) {
        '常量' { $body += ("    内联 常量 {0} {1} = {2};" -f $e[3], $e[1], $e[2]); $n['常量']++ }
        '类型' { $body += ("    使用 {0} = {1};" -f $e[1], $e[2]); $n['类型']++ }
        # §16.52 返回类型用 声明类型(自动)：别名层的被转发函数（std::get / std::front …）
        #   不少是【引用返回】，`自动` 会把引用语义砍掉。
        '函数' { $body += ("    模板 <类型名... 参数> 声明类型(自动) {0}(参数&&... 值) {{ 返回 {1}(static_cast<参数&&>(值)...); }}" -f $e[1], $e[2]); $n['函数']++ }
        '原样' { $body += ("    " + $e[1]); $n['原样']++ }
    }
}

# 每个条目可以给一句"为什么只能别名"的准确理由；没给就用默认那句。
# ⚠ 别再用写死的理由：以前所有头都印"本头里是常量而不是类"，
#   对 <数组>/<元组>/<类型信息> 都是假话 —— 生成器不许对读者说谎。
$reason = if ($spec.ContainsKey('reason')) { $spec.reason } else { '本头里的东西，类型身份参与语义（换一份就成了两套互不相认的东西）。' }
$text = @"
// <$($spec.zh)> —— $($spec.src) 的中文别名层
//
// 为什么是别名而不是抄一份（方案铁律 4）：
//   $($reason)
//   这类头一旦抄一份，就会和 std 里那份成为两套互不相认的东西。
//
// 英文原名照旧可用：这里只是【多一个名字】，原头一个字节没动。
// 变体（英文里带 _v 的变量模板形式）暂未提供中文名，属"必须的妥协"，见方案 §六。
#pragma once
#include <$($spec.src)>

名域 标准 {
$($body -join "`n")
}
"@
New-Item -ItemType Directory -Force $out | Out-Null
$outPath = Join-Path $out $spec.zh
[System.IO.File]::WriteAllText($outPath, $text, $utf8)
Write-Host "=== <$($spec.zh)> ===" -ForegroundColor Cyan
Write-Host ("  生成 常量 {0} / 类型 {1} / 函数 {2} / 原样 {3}" -f $n['常量'], $n['类型'], $n['函数'], $n['原样'])

# 验证：能引、能用、与原名并存
$t = Join-Path $root 'build\_zha'
if (Test-Path $t) { Remove-Item -Recurse -Force $t }
New-Item -ItemType Directory -Force $t | Out-Null
$cases = if ($spec.ContainsKey('tests')) { $spec.tests } else {
    $first = $spec.a | Where-Object { $_[0] -eq '常量' } | Select-Object -First 1
    @(
      @('只引中文头', "#包含 <$($spec.zh)>`n整数 主函数(){ 返回 (整数)标准::$($first[1]); }"),
      @('与微软原头并存', "#包含 <$($spec.zh)>`n#包含 <$($spec.src)>`n整数 主函数(){ 返回 (整数)标准::$($first[1]) + (整数)$($first[2]); }")
    )
}
$pass = 0
foreach ($c in $cases) {
    $src = Join-Path $t 't.cpp'
    [System.IO.File]::WriteAllText($src, $c[1] + "`n", $utf8)
    & cmd /c "`"$cxx`" -std=c++20 -isystem`"$out`" -fsyntax-only `"$src`" > `"$t\o.txt`" 2>&1"
    if ($LASTEXITCODE -eq 0) { Write-Host ("  [ok]   {0}" -f $c[0]); $pass++ }
    else {
        Write-Host ("  [FAIL] {0}" -f $c[0]) -ForegroundColor Yellow
        Get-Content "$t\o.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match 'error:' } |
            Select-Object -First 2 | ForEach-Object { Write-Host ("         " + ([string]$_).Trim()) }
    }
}
Write-Host ("  {0} / {1}" -f $pass, $cases.Count)
Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
