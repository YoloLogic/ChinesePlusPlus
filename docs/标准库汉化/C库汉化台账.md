# C 库汉化台账（C 线覆盖盘点）

> **本文件是自动生成的，不要手改。**
> 由 `tools\make_c_ledger.ps1` 从盘上的真文件算出来（单一真相），
> 并由闸门里的守卫用 `-Check` 核对 —— **手改或不重新生成都会被抓出来**。

用户 2026-10-07 裁定：**不做纯 C**（不新增宏别名层），只把 Chinese++ 现有的
「C 包装头」别名层（`zhstdlib\C运行库\`）做扎实，并要求先有一份盘点。

## 一、两侧数据来源

| 侧 | 来源 |
|---|---|
| 我们 | `zhstdlib\C运行库\` 的 25 个中文 C 包装头 + `zhstdlib\标准库\错误号`（cerrno），共 **26** 个头 |
| 参考 | `dist\Chinese++-0.2-win64\lib\stl` 里各 `cXXX` 的 `using _CSTD <名字>;` 名单 —— 那是 MSVC STL 把 C 名字搬进 `std` 的**全集**，也就是"可以起中文名"的全集 |

## 二、两种口径（别混，混了会把缺口放大近一倍）

| 口径 | 含义 | 为什么需要它 |
|---|---|---|
| **符号口径** | `acos` / `acosf` / `acosl` 各算一个 | 这是 STL 暴露符号的方式，用来对拍参考集的**规模** |
| **逻辑口径** | 把 `f`/`l` 变体合并成一个逻辑函数 | 我们的机制是**变参模板转发**：**一个中文名覆盖整族重载** ⇒ 逻辑口径才是**真实工作量** |

合并的边界（`tools\make_c_ledger.ps1` 的 `Merge-Variants`，自带自测）：

* **合**：`acosf`/`acosl` → `acos`（`<cmath>` 里是**同一个重载名**，一个中文名转发过去就全覆盖）；
  基名以 `l`/`f` 结尾也照合（`ceill` → `ceil`、`modff` → `modf`）。
* **判据**：**整族存在**才算重载族 —— `X`、`Xf`、`Xl` 三个名字都在参考集里才合并。
* **不合**：`strtoll` / `atoll` / `wcstoull`（要 `strtol`+`strtolf`+`strtoll` 三个都在才算族，
  而 `strtolf` 这类名字**根本不存在** ⇒ 它们是 **long long 版的另一个函数**，不是重载）；
  以及 `nanf`/`nanl`（三个名字齐、看着像族，但标准里 `nan`/`nanf`/`nanl` 是**三个独立名字** ⇒ 显式例外）。

> ⚠ 这两条例外是**修正后**的（§18.58）：第一版判据把 `ll` 当成了 `l` 变体、把 `nanf` 当成 `nan` 的重载，
> **缺口少算 7 个**且表面完全正常。现在判据自带 `Test-MergeVariants` 自测，改坏就当场抛错。

## 三、逐头明细（我们做了什么）

| 中文头 | 英文头 | 类型 | 函数 | 值宏 | 我们合计 | 参考符号 | 参考逻辑 | 缺（逻辑） |
|---|---|---|---|---|---|---|---|---|
| C宽字符类别 | cwctype | 0 | 5 | 0 | **5** | 21 | 21 | 16 |
| C字符串 | cstring | 0 | 10 | 0 | **10** | 23 | 23 | 13 |
| C数学 | cmath | 2 | 60 | 0 | **62** | 186 | 74 | 12 |
| C标准输入输出 | cstdio | 1 | 39 | 1 | **41** | 49 | 49 | 9 |
| C浮点环境 | cfenv | 2 | 2 | 0 | **4** | 13 | 13 | 9 |
| C时间 | ctime | 3 | 6 | 0 | **9** | 15 | 15 | 6 |
| C字符转换 | cuchar | 0 | 0 | 0 | **0** | 6 | 6 | 6 |
| C字符类别 | cctype | 0 | 9 | 0 | **9** | 14 | 14 | 5 |
| C整数格式 | cinttypes | 1 | 2 | 0 | **3** | 7 | 7 | 4 |
| C本地化 | clocale | 1 | 1 | 0 | **2** | 3 | 3 | 1 |
| C宽字符 | cwchar | 4 | 59 | 0 | **63** | 64 | 64 | 1 |
| 错误号 | cerrno | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C变参 | cstdarg | 1 | 0 | 0 | **1** | 0 | 0 | 0 |
| C标准定义 | cstddef | 5 | 0 | 0 | **5** | 2 | 2 | 0 |
| C标准库 | cstdlib | 4 | 38 | 0 | **42** | 42 | 42 | 0 |
| C标准整数 | cstdint | 28 | 0 | 0 | **28** | 28 | 28 | 0 |
| C布尔 | cstdbool | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C断言 | cassert | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C对齐 | cstdalign | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C泛型数学 | ctgmath | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C浮点极值 | cfloat | 0 | 0 | 2 | **2** | 0 | 0 | 0 |
| C复数 | ccomplex | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C替代拼写 | ciso646 | 0 | 0 | 0 | **0** | 0 | 0 | 0 |
| C跳转 | csetjmp | 1 | 1 | 0 | **2** | 0 | 0 | 0 |
| C信号 | csignal | 1 | 2 | 0 | **3** | 3 | 3 | 0 |
| C整数极值 | climits | 0 | 0 | 3 | **3** | 0 | 0 | 0 |
| **合计** |  | **54** | **234** | **6** | **294** | **476** | **364** | **70** |

**一句话**：头覆盖 **26/26**；我们起了 **294** 个中文名（类型 54 / 函数 234 / 值宏 6）；
按逻辑口径，参考全集 **364**、已覆盖 **294**、**还缺 70**；按符号口径参考 **476**（含 f/l 变体，会把缺口放大，别拿它对工作量）。

**零名字的头**（8 个）：`C布尔`、`C断言`、`C对齐`、`C泛型数学`、`C复数`、`C替代拼写`、`C字符转换`、`错误号`

其中绝大多数**本来就转不了**：内容全是宏（`errno`/`assert`）、或已是关键字（`bool`/`alignas`/`and`）、
或该头在 C++ 里是空的（`ctgmath`/`ccomplex`，名字在别处）。**例外是真欠账**，逐条见第五节。

## 四、缺口清单（还缺什么，按头分组）

口径：逻辑名（已合并 `f`/`l` 变体）。**其中有些是宏**（转不了，见第五节），
这里一律列出以便逐条判断，不作自动过滤。

* **`C宽字符类别`**（`cwctype`，缺 16）：`iswalnum` `iswblank` `iswcntrl` `iswctype` `iswgraph` `iswlower` `iswprint` `iswpunct` `iswupper` `iswxdigit` `towctrans` `wctrans` `wctrans_t` `wctype` `wctype_t` `wint_t`
* **`C字符串`**（`cstring`，缺 13）：`memchr` `size_t` `strcoll` `strcspn` `strerror` `strncat` `strncmp` `strncpy` `strpbrk` `strrchr` `strspn` `strtok` `strxfrm`
* **`C数学`**（`cmath`，缺 12）：`fpclassify` `isfinite` `isgreater` `isgreaterequal` `isinf` `isless` `islessequal` `islessgreater` `isnan` `isnormal` `isunordered` `signbit`
* **`C标准输入输出`**（`cstdio`，缺 9）：`_Mbstatet` `fgetpos` `fpos_t` `freopen` `fsetpos` `getc` `putc` `setbuf` `size_t`
* **`C浮点环境`**（`cfenv`，缺 9）：`fegetenv` `fegetexceptflag` `fegetround` `feholdexcept` `feraiseexcept` `fesetenv` `fesetexceptflag` `fesetround` `feupdateenv`
* **`C时间`**（`ctime`，缺 6）：`asctime` `ctime` `mktime` `size_t` `timespec` `timespec_get`
* **`C字符转换`**（`cuchar`，缺 6）：`c16rtomb` `c32rtomb` `mbrtoc16` `mbrtoc32` `mbstate_t` `size_t`
* **`C字符类别`**（`cctype`，缺 5）：`isblank` `iscntrl` `isgraph` `isprint` `isxdigit`
* **`C整数格式`**（`cinttypes`，缺 4）：`strtoimax` `strtoumax` `wcstoimax` `wcstoumax`
* **`C本地化`**（`clocale`，缺 1）：`setlocale`
* **`C宽字符`**（`cwchar`，缺 1）：`_Mbstatet`

## 五、硬边界（做不了的，别当欠账）

| 类别 | 例子 | 为什么 |
|---|---|---|
| 同一个类型的内部拼写 | _Mbstatet（cwchar / cstdio 的缺口里各出现一次） | 它就是 mbstate_t 本体（MSVC 的内部拼写）—— C 语言里是 `typedef _Mbstatet mbstate_t;` ⇒ 只给这一个类型起一个中文名（`多字节状态`），_Mbstatet 不再另起（§18.59） |
| 宏：无法起别名 | errno、EINVAL 等 E* 一族 | C 头里是宏，别名层只能给"名字"起别名，宏没有别名机制 |
| 宏：无法起别名 | assert（cassert） | 同上；且它在 NDEBUG 下会被整体抹掉 |
| 函数式宏：无法转发 | va_start、va_arg、va_end、va_copy、setjmp | 函数式宏不是函数，变参模板转发够不着（方案 §3.4.1 已登记） |
| 宏：无法起别名 | isfinite、isnan、isinf、signbit、fpclassify、isgreater 一族 | 在标准 C 里是宏；MSVC STL 虽以函数形式暴露，但换平台/换头就散架，不起中文名 |
| 标准已删除 | gets | C11 已删除，这套 STL 里 std::gets 根本不存在（实测编译报错） |
| 别人的符号 | 微软 UCRT / Windows DLL 里的导出符号 | 只能"加名字"不能"改名字"；中文名是新增层，原件一个字节不动 |
| 不做纯 C ⇒ 保持英文 | <threads.h>、<stdatomic.h>、<stdbit.h>、<stdnoreturn.h>、<stdckdint.h> | 用户 2026-10-07 裁定不做纯 C（不加宏别名层）；这些是 C-only 头，别名层机制也够不着 |

## 六、怎么复现

```powershell
pwsh -File tools\make_c_ledger.ps1            # 重新生成本台账
pwsh -File tools\make_c_ledger.ps1 -Check     # 只核对（闸门守卫调它）
```

参考基准的定位顺序：`vendor\stl` → `build\include` → `dist\Chinese++-*\lib\stl`，
也可用 `-StlDir` 显式指定。**找不到就如实跳过**（退出码 2），不算失败。

