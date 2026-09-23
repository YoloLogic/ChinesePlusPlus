# third_party —— 用**别人的代码**验收我们的编译器

> 这个文件夹里放的**不是我们的代码**。它的唯一目的，是兑现项目自己立下的那条底线：
>
> **做完任何一项中文化之后，随便拿一个开源 C++ 项目，用我们的编译器编，必须照样编得过。**
>
> 在此之前，`tests\` 里的 19 项、`报错示例\` 的 15 个文件、`tools\acceptance.ps1` 的 17 条断言
> ——**全部是我们自己写的代码**。自己写的测试证明不了"别人的代码照样编得过"。
> 这里就是补上这一块。

---

## 一、目录结构

| 目录 | 放什么 | 能不能删 |
|---|---|---|
| `src\<项目>\` | 从上游克隆的**原样**源码，**一行都不改** | 可重新克隆 |
| `build\<项目>-ours\` | 用**我们的编译器**生成的构建树 | 随便删 |
| `build\<项目>-stock\` | 用**官方 clang** 生成的构建树（对照组） | 随便删 |
| `logs\<项目>-<side>.log` | 每次运行的**原始日志**（配置/编译/测试全在里面） | 是证据，别删 |
| `downloads\` | 预留：如果有项目要下载压缩包，原始包放这里 | — |

> ⚠️ 这个文件夹**不在任何补丁里**。`tools\make_patch.ps1` 只扫描 `LLVM-main\` 下的
> `clang\`、`llvm\`、`clang-tools-extra\`，这里放多少东西都不影响补丁。

---

## 二、被验证的项目（来源凭证）

本轮全部通过 **gitee 镜像**克隆。GitHub 其实**也直连得通**——最初以为不通，是受限沙箱下
Schannel 用不了的**误判**（已实测更正，见第四节"问题 2"）：

| 项目 | 语言 | 版本 | commit | 许可 | 它的测试套件 |
|---|---|---|---|---|---|
| [pugixml](https://gitee.com/mirrors/pugixml) | C++ | 1.16 | `27b68329de32cf9c601ca8eb6c588fd639960c40` | MIT | 自带（`PUGIXML_BUILD_TESTS=ON`） |
| [tinyxml2](https://gitee.com/mirrors/tinyxml2) | C++ | 10.0.0 | `312a8092245df393db14a0b2427457ed2ba75e1b` | zlib | 自带 `xmltest` |
| [fmt](https://gitee.com/mirrors/fmt) | C++ | 12.2.1（`FMT_VERSION 120201`） | `cde18a38bbd960a2e803b76880fbbf4b4ffb3cd7` | MIT | GoogleTest（**仓库内自带**，无需联网） |
| [googletest](https://gitee.com/mirrors/googletest) | C++ | 1.18.0 | `283c17563fe7a1111cd7f581aa5d541e8baeff2f` | BSD-3 | 自带（`gtest_build_tests=ON`） |
| [zlib](https://gitee.com/mirrors/zlib) | **C** | 1.3.x | `e3dc0a8` | zlib | 自带（含 `.rc` 资源 + 共享库 + 嵌套 CMake 测试） |
| [libuv](https://gitee.com/mirrors/libuv) | **C** | 1.x | `84af0b1` | MIT | 自带 `uv_test` |
| [cJSON](https://gitee.com/mirrors/cJSON) | **C** | 1.7.x | `fb16e5c` | MIT | 自带 unity 测试 |

**为什么要加纯 C 项目**：前四个全是 C++，也就是说**我们的 C 驱动 `clang.exe` 从没被真实代码用过**
（只在 CMake 探测 ABI 时编过一个 3 行的 C 文件）。这是唯一一块从没被碰过的功能面。

克隆命令（**必须带 `-c http.sslBackend=openssl`**，原因见第四节"问题 2"）：

```powershell
git -c http.sslBackend=openssl clone --depth 1 https://gitee.com/mirrors/pugixml.git src\pugixml
```

---

## 三、怎么跑

```powershell
# 全部项目（默认只跑 static 形态）
powershell -File E:\Chinese++\tools\verify_third_party.ps1

# 只跑某几个 / 指定构建形态
powershell -Command "& 'E:\Chinese++\tools\verify_third_party.ps1' -Projects zlib,libuv -Variants static"
powershell -Command "& 'E:\Chinese++\tools\verify_third_party.ps1' -Projects tinyxml2,pugixml -Variants shared,debug"
```

**构建形态**（第一轮只覆盖了第一种，每一种都是新的风险面）：

| `-Variants` | 加了什么 | 覆盖什么 |
|---|---|---|
| `static`（默认） | — | Ninja + Release + 静态库 |
| `shared` | `-DBUILD_SHARED_LIBS=ON` | DLL 导出/导入、`.lib` 导入库 |
| `debug` | `-DCMAKE_BUILD_TYPE=Debug` | PDB / CodeView 生成 |

对每个项目分别在**两个编译器**上跑完 `configure → build → ctest`，比对三组退出码：

| 代号 | 编译器 | 说明 |
|---|---|---|
| `ours` | `E:\Chinese++\build\Release\bin\clang.exe` / `chinese++.exe` | 我们改过的 fork（clang 24.0.0git） |
| `stock` | VS 自带 `...\VC\Tools\Llvm\x64\bin\clang.exe` | **未经改动的**官方 clang 19.1.5 |

> `PASS` = 我们三组退出码全 0，且与对照组完全一致。
> `SAME` = 我们**以完全相同的方式失败**（上游/环境问题，不是我们改出来的）。
> `FAIL` = 两边不一致 —— **这才是要找的东西**。

### 跑之前必须知道的两件事

1. **必须在放宽文件沙箱的会话里跑。** `cmake` 探测编译器时会以**管道**方式起子进程
   并抓它的输出，在受限沙箱（read-only / workspace-write）下**必然死锁**
   （官方 clang 也一样死锁，与我们的编译器无关）。表现为 `Detecting C compiler ABI info`
   之后 cmake/ninja 双双 CPU 0%。
   会话级放宽要在**启动 DSH 时**设环境变量 `DSH_PERMISSION_MODE=danger-full-access`
   （见 `dsh-base\cordis.patch.yml` 第 211/227 行）。
2. 构建工具都在仓库外：CMake/Ninja 来自 CLion，`rc.exe` 来自 Windows SDK。
   脚本会自动把 SDK 的 bin 加进 `PATH`（MSVC 的 `link.exe` 只会在 `PATH` 上找 `rc.exe`）。

---

## 四、已发现的问题（**真实项目才暴露得出来的**）

### 问题 1：我们的发行包曾缺一整套二进制工具（**前三样已于 2026-09-23 补齐**）

> ## ✅ 状态：已修复（2026-09-23 当天）
>
> **补上了**：`lld-link.exe`、`llvm-ar.exe`、`llvm-lib.exe`、`llvm-ranlib.exe`、`llvm-rc.exe`
> —— 全部用**我们自己源码树里的源码、我们自己的编译器**编出来，已装进
> `build\Release\bin\`（lld 那 4 个名字是硬链接，共用 44.6 MB）。
>
> **验收判据（已达成，且数字完全吻合）**：zlib 的失败测试数应从 **7 降到 5**、与官方 clang 一致。
> 实测：`ours 55% passed, 5 failed` / `stock 55% passed, 5 failed`，**失败集逐条相同**，
> 判定由 **FAIL → SAME**。
>
> **仍然缺的**：compiler-rt 运行时（`clang_rt.*`，影响 `-fsanitize` / `-coverage` / PGO）
> —— 那是另一个工程，见 `docs\打包\打包方案.md`。
>
> 下面保留的是**修复前的原始记录**，因为"怎么发现的"和"怎么复现"本身有价值。

修复前：`E:\Chinese++\build\Release\bin\` 里**只有编译器驱动**，对照官方 VS LLVM 的 bin 目录：

| 工具 | 作用 | 官方 | 我们（修复前） | 现在 |
|---|---|---|---|---|
| `lld-link.exe` | CMake 默认要求 Clang 用的链接器 | ✅ | ❌ | ✅ 44.6 MB |
| `llvm-ar.exe` / `llvm-ranlib.exe` | 打静态库（`.lib`） | ✅ | ❌ | ✅ 各 8.3 MB |
| `llvm-lib.exe` | MSVC 风格打库 | ✅ | ❌ | ✅ 8.3 MB |
| `llvm-rc.exe` | 资源编译 | ✅ | ❌ | ✅ 0.6 MB |

**后果（两个都是实测撞上的，不是推测）：**

- CMake 4.2 在 Windows+Clang 下默认给链接命令加 `-fuse-ld=lld-link`
  （`Modules\Platform\Windows-Clang.cmake` 第 65 行 `_USING_LINKER_DEFAULT`）。
  我们没这个程序 → `clang: error: unable to execute command: program not executable`
  → **配置阶段就失败**，任何 CMake 项目开箱即用都编不过。
- 打静态库时 CMake 执行的字面量是 `CMAKE_AR-NOTFOUND qc tinyxml2.lib ...`
  → `'CMAKE_AR-NOTFOUND' is not recognized as an internal or external command`。

**结论**：现在这套东西**只能算"一个能单独调用的编译器"，不能算"一套工具链"**。
要给别人用（打包方案的前置条件），必须把 `lld` 与 `llvm-ar`/`llvm-lib`/`llvm-ranlib`/`llvm-rc`
一起编出来放进 `bin\`。

#### 怎么自己复现这两条（不用相信我的话）

```powershell
# 缺 lld-link.exe：原样跑（不用任何绕法）→ 配置阶段就死
& 'E:\Chinese++\tools\verify_third_party.ps1' -Toolchain plain -Projects tinyxml2
#   ours    configure=1  ← clang: error: unable to execute command: program not executable
#   stock   configure=0   同一个项目、同一台机器，官方 clang 全过
#   存证：logs\tinyxml2-ours-plain.log

# 缺 llvm-ar.exe：只补上链接器（-DCMAKE_LINKER_TYPE=MSVC）→ 编译过了，打静态库时死
& 'E:\Chinese++\tools\verify_third_party.ps1' -Toolchain nolld -Projects tinyxml2
#   ours    configure=0  build=1  ← CMAKE_AR-NOTFOUND qc tinyxml2.lib ...
#   注意 configure=0 且日志里有 "[1/4] Building CXX object ... tinyxml2.cpp.obj"
#   —— 也就是说 3000 多行真实 C++ 已经被我们的编译器编过了，死在最后打库那一步
#   存证：logs\tinyxml2-ours-nolld.log
```

三档 `-Toolchain` 的含义：`workaround`（默认，借归档器 + 用 MSVC 的 link.exe，用来**单独隔离编译器**）、
`plain`（**原样**，复现缺 `lld-link`）、`nolld`（有链接器无归档器，复现缺 `llvm-ar`）。

#### 🎯 差别性证据：**同一个命令，官方 clang 能过，我们过不了**（本轮新发现）

前面两条是"两边都挂"，这条不是。**zlib 的 `zlib_add_subdirectory_configure` 测试**会新建一个
**嵌套的 CMake 工程**并用我们的编译器配置它：

```
嵌套工程【不会】继承 -DCMAKE_LINKER_TYPE=MSVC（那是个全新工程）
  → 用 CMake 默认的 -fuse-ld=lld-link
  → ours ：没有 lld-link.exe → The C compiler "...\clang.exe" is not able to compile a simple test program  ✗
  → stock：VS 的 LLVM 自带 lld-link.exe → 通过  ✓
```

| | ours | stock |
|---|---|---|
| zlib 全量 ctest | 36% passed，**7** failed | 55% passed，**5** failed |
| 差的那两个 | `zlib_add_subdirectory_configure`、`zlib_add_subdirectory_exclude_configure` | 这两个**通过** |

**这条比"缺陷 1"更有分量**：它不是"我们都编不过"，而是
**"官方 clang 编得过、我们编不过"** —— 缺陷的严格定义。

**它还顺手推翻了一个假设**：我原先以为"用户加个 `-DCMAKE_LINKER_TYPE=MSVC` 就能绕过"。
嵌套 / 子工程（`add_subdirectory` 测试、`FetchContent`、`ExternalProject`）**拿不到这个设置**，
照样会去要 `lld-link`。所以 **`CMAKE_LINKER_TYPE` 不是绕法，只是本机测编译器时的隔离手段**；
唯一稳的修法是把 `lld-link.exe` 装进发行包。

原始日志：`logs\zlib-ours.log` 与 `logs\zlib-stock.log`。

> **两条教训（都是这一轮真踩到的）**
>
> 1. **坏的验证环境会掩盖真差异。** 这个差异一开始根本看不到——因为那 4 个嵌套测试
>    连"跑"都跑不起来（`CMake was unable to find a build program corresponding to "Ninja"`）。
>    等我把 Ninja 和 SDK 头文件路径补进环境，它们才真的跑，差异才露出来。
>    **不干净的验证 = 不敏感的验证。**
> 2. **判定逻辑不能只比聚合数字。** 这里两边 ctest 退出码都是 `8`，
>    只比退出码会判成 SAME —— **又一次"比数字而不比实际集合"**（上一次是"被截断的中文表"
>    骗过了校核器）。现在判定同时比 **退出码** 和 **失败测试名集合**。

> 这一轮验证为了把"编译器本身"单独隔离出来，**归档器借用**官方 LLVM 的
> `llvm-ar.exe`/`llvm-ranlib.exe`，并且**给两边用同一个**；链接器两边都用 MSVC 的
> `link.exe`（`-DCMAKE_LINKER_TYPE=MSVC`）。
> 换句话说：**表格里的 PASS 只说明"编译器没问题"，不说明"发行包没问题"。**

### 问题 2：受限沙箱里用不了 Schannel（**不是本机坏了**）

在受限沙箱（read-only / workspace-write）里，所有走**系统 TLS 栈**的工具都报：

```
schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030e)
```

涉及 `curl.exe`、默认配置的 `git`、`Invoke-WebRequest`。

> ⚠️ 这里原先写的是"本机 schannel 坏掉"——**那个诊断是错的**，已按实测更正。
> 教训与项目里其它结论一样：**没验证过的因果推断不要写成结论**。

**实测（2026-09-23，在同一台机器上）**：

| 检查项 | 受限沙箱 | 放宽沙箱 |
|---|---|---|
| `CryptSvc`（加密服务） | Running / Automatic（两种模式下都是） | — |
| FIPS 策略 | 关闭（正常） | — |
| `curl https://gitee.com` | `SEC_E_NO_CREDENTIALS` | **HTTP 200** |
| `curl https://www.baidu.com` | 同上 | **HTTP 200** |
| `Invoke-WebRequest https://gitee.com` | 同上 | **HTTP 200** |
| `git ls-remote https://github.com/fmtlib/fmt.git`（openssl 后端） | 成功列出 refs | 成功列出 refs |
| `python urllib https://github.com` | **200** | 200 |

**结论**：本机 TLS 栈完全正常，**不需要修**。原因是受限进程拿不到 Schannel 凭证
（凭证要从密钥库 / LSA 取，而沙箱恰好把那里围住了）。

顺带更正第二个同源误判：**"GitHub 在本机不通"也是错的**（那是同一批受限模式下的测试得出的）。
用自带 OpenSSL 的通道，受限沙箱下 **GitHub 与 gitee 都能直连**。
两处错误是同一个毛病：把"我的测试环境受限导致的失败"当成了"机器/网络的问题"。

**绕法（两条，按场合选）**：

1. 需要系统 TLS 栈的场合 → 用放宽沙箱启动：`DSH_PERMISSION_MODE=danger-full-access`（要重启 DSH）。
2. 只想下载东西 → 换用**自带 OpenSSL** 的工具，受限沙箱下照样能用：
   `git -c http.sslBackend=openssl ...`，或 `python -c "import urllib.request; ..."`。
   （上文克隆命令用的就是这条。）

---

## 五、实测结果

（每一格是 `configure/build/ctest` 的退出码；原始日志在 `logs\`，汇总在 `logs\summary.txt`）

<!-- RESULTS:BEGIN -->
### 第三轮（**当前**）：补齐工具链之后的全量复跑，用**原样发行包**

2026-09-23 补齐 `lld-link` + `llvm-ar/lib/ranlib/rc` 之后重跑，
**默认工具链就是 `plain`（我们实际发的东西，不借任何外部工具）**：

| 项目 | 语言 | ours（我们的工具链） | stock（官方 clang 19.1.5） | 结论 |
|---|---|---|---|---|
| tinyxml2 | C++ | `0/0/0` 1/1 passed | `0/0/0` 同上 | **PASS** |
| pugixml | C++ | `0/0/0` 1/1 passed | `0/0/0` 同上 | **PASS** |
| fmt | C++ | `0/0/8` 3/21 failed | `0/0/8` **完全相同的 3 个** | **SAME** |
| googletest | C++ | `0/1/1` `gtest-printers.h:915` | `0/1/1` **同一文件同一行列** | **SAME** |
| cJSON | **C** | `0/1/1` 测试链接失败 | `0/1/1` **同一条** | **SAME** |
| zlib | **C** | `0/0/8` **5** failed | `0/0/8` **同一批 5 个** | **SAME** ✅ |
| libuv | **C** | `0/0/8` 2/2 failed | `0/0/8` **同两个** | **SAME** |

```
cases=7  pass=2  same=5  fail=0        ← 零差异
```

> **zlib 那一行是这一轮的验收判据**：修复前是 `ours 7 failed / stock 5 failed`（**FAIL**），
> 修复后两边都是 **5 个、且逐条相同**（**SAME**）。数字完全吻合，说明根因就是缺 `lld-link.exe`。

### 历史轮次（保留：它们记录了"怎么发现的"）

第一轮（4 个 C++ 项目 × `static`，工具链是借来的）：

| 项目 | 形态 | ours | stock | 结论 |
|---|---|---|---|---|
| tinyxml2 | static | `0/0/0` | `0/0/0` | **PASS** |
| pugixml | static | `0/0/0` | `0/0/0` | **PASS** |
| fmt | static | `0/0/8` 3/21 | 完全相同的 3 个 | **SAME** |
| googletest | static | `0/1/1` | 同一文件同一行列 | **SAME** |

第二轮（新增纯 C 项目 + `shared`/`debug` 形态，**这一轮抓到了那个 FAIL**）：

| 项目 | 形态 | ours | stock | 结论 |
|---|---|---|---|---|
| tinyxml2 | **shared** | `0/0/0` | `0/0/0` | **PASS** |
| tinyxml2 | **debug** | `0/0/0` | `0/0/0` | **PASS** |
| pugixml | **debug** | `0/0/0` | `0/0/0` | **PASS** |
| pugixml | **shared** | `0/1/1` `no such file: 'pugixml.lib'` | `0/1/1` 同一条 | SAME |
| libuv（C） | static | `0/0/8` 2/2 | 同两个 | SAME |
| cJSON（C） | static | `0/1120/1` | 同一条 | SAME |
| zlib（C） | static | `0/0/8` **7** failed | `0/0/8` **5** failed | **🔴 FAIL** |

```
cases=11  pass=5  same=5  fail=1
```

**那个唯一的 FAIL 就是差别性证据**（见第四节"🎯"）：zlib 的两个嵌套 CMake 测试，
官方过、我们不过，根因是发行包缺 `lld-link.exe`。**第三轮把它修掉了。**

### 怎么读这张表

- **PASS**：我们的编译器全绿，且与官方 clang 结果一致。
- **SAME**：两边**以完全相同的方式失败** —— 上游/环境问题，不是我们改出来的回归。
  **`SAME` 是这张表的主要价值**：它说明我们的编译器与未经改动的 clang 在语义上等价。
- **FAIL**：两边不一致 —— 那才是要找的东西。**这一轮抓到 1 个，根因已定位。**

> 判定同时比 **退出码** 与 **失败测试名集合**。只比退出码会漏掉 zlib 这条
> （两边 ctest 都是 8，失败的却是不同的测试）。

### 纯 C 项目带来的新覆盖（前一轮完全没有）

| 覆盖到的东西 | 由谁证明 |
|---|---|
| **C 驱动 `clang.exe` 能编真实 C 项目** | libuv 全部编过并链接（`build=0`）；zlib 编过并**真的运行了** `zlib_examplestatic`（Passed） |
| **`.rc` 资源文件** | zlib 的 `win32/zlib-cmake.rc` 编译并链接进 DLL |
| **共享库（DLL）** | tinyxml2 shared、zlib 的 `z.dll`、cJSON 默认就是 DLL |
| **Debug / PDB** | tinyxml2 debug、pugixml debug |
| **嵌套 CMake 工程** | zlib 的 `add_subdirectory` / `find_package` 测试 → **就是它抓出了那个 FAIL** |

### 几处"相同失败"的具体原因（都不是我们的问题）

| 项目 | 失败项 | 原因 |
|---|---|---|
| fmt | `chrono-test`、`std-test`(**SEGFAULT**)、`unicode-test` | 本机 locale / MSVC STL 环境差异；两边逐条相同，连 SEGFAULT 都一样 |
| googletest | `gtest-printers.h:915` 用 `std::any` 但没 `#include <any>` | 上游 1.18 与新版 MSVC STL 的可移植性问题；clang 19 与 clang 24 同样报错 |
| pugixml shared | `no such file or directory: 'pugixml.lib'` | CMake 共享库 + `-fuse-ld=link` 的导入库路径问题；**补上 `lld-link` 后应自然消失** |
| cJSON | `LNK2019: 无法解析的外部符号 setUp / tearDown` | cJSON 自己的 `tests\parse_array.c` 等**根本没定义**这两个函数（已核对源码），上游测试配置问题 |
| zlib | `zlib_find_package_*` / `*_build` | 嵌套工程的 DLL 路径与安装布局，两边同源 |
| libuv | `uv_test`、`uv_test_a` | 两边同两个，本机网络/环境相关 |

> googletest 那一条顺带成了一个**意外的证据**：两边报的是**同一文件、同一行列**（`915:43`），
> 只有语言不同 ——
> 我们：`error: namespace 'std' 中没有名为 'any' 的成员`
> 官方：`error: no member named 'any' in namespace 'std'`
> 这正是在**真实第三方项目的构建过程**里验证了"中文诊断生效、`error:` 前缀不变、语义不变"。

### 这一轮的边界（不要过度解读）

- 7 个项目都**不大**（最大的是 googletest / libuv），属于"小而真"。
  这比"自己写测试"强得多，但**不等于**"大型工程也没问题"。
- 归档器是**借来的**（借官方 LLVM 的 `llvm-ar`/`llvm-ranlib`，两边同款），
  链接器两边都用 MSVC 的 `link.exe`。所以：**PASS 只说明编译器没问题，不说明发行包没问题**
  —— 发行包的问题正是第四节那两条，而且那个 FAIL 的根因也在那里。
- **编译器语义层目前 0 个差异**（7 个项目、11 个用例）。这既可能是"我们的改动确实安全"
  （改动只有"新增中文关键字别名 + 报错格式化挂钩"，英文代码碰不到），
  也可能是"这些项目压不到那个面"。**不要把它读成"已经证明没问题了"。**
<!-- RESULTS:END -->

---

## 六、注意事项

- `src\` 下的源码**永远不要改**。要改配置就走 `-D` 开关；要打补丁给上游也不是在这里。
- 日志对**行尾和编码**敏感：本目录的脚本一律纯 ASCII，中文只出现在 `.md` 数据文件里
  （PowerShell 5.1 会把无 BOM 的文件按 GBK 读，脚本里的中文字面量会被读坏）。
- 想加一个新项目：克隆到 `src\<名字>\`，在 `tools\verify_third_party.ps1` 的 `$extra`
  哈希表里加一条"怎么打开它自己的测试"的开关即可，其余全自动。
