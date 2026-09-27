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
#    函数  -> 模板 <类型名... 参数> 自动 中文名(参数&&... 值) { 返回 std::原名(...); }
#
#  用法：powershell -File tools\make_zhalias.ps1 -Header numbers
# ============================================================================
param([string] $Header = 'numbers')

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

$spec = $H[$Header]
if (-not $spec) { throw "表里没有 $Header" }

$body = @(); $n = @{ '常量'=0; '类型'=0; '函数'=0; '原样'=0 }
foreach ($e in $spec.a) {
    switch ($e[0]) {
        '常量' { $body += ("    内联 常量 {0} {1} = {2};" -f $e[3], $e[1], $e[2]); $n['常量']++ }
        '类型' { $body += ("    使用 {0} = {1};" -f $e[1], $e[2]); $n['类型']++ }
        '函数' { $body += ("    模板 <类型名... 参数> 自动 {0}(参数&&... 值) {{ 返回 {1}(static_cast<参数&&>(值)...); }}" -f $e[1], $e[2]); $n['函数']++ }
        '原样' { $body += ("    " + $e[1]); $n['原样']++ }
    }
}

$text = @"
// <$($spec.zh)> —— $($spec.src) 的中文别名层
//
// 为什么是别名而不是抄一份（方案铁律 4）：
//   本头里是【常量】而不是类 —— 常量换不了类型，只能承载它的值。
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
