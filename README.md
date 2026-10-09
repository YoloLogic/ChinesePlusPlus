# Chinese++ · 中文编程

> **作者个人理解的完美的汉语编程。**

中文关键字是 Clang/LLVM 的**第一公民**。英文拼写照旧可用，两种写法可以随意混写。

```cpp
#包含 <cstdio>          // 中文指令，等价于 #include
#include <vector>        // 英文指令 —— 混着写没问题

整数 主函数() {                       // 主函数 = main
    std::vector<int> 数字{1, 2, 3};   // 库名仍是英文
    整数 和 = 0;                      // 整数 = int
    对于 (整数 n : 数字)              // 对于 = for
        和 += n;
    std::printf("和 = %d\n", 和);
    返回 0;                           // 返回 = return
}
```

> 完整可编译示例见 [`vscode-kit/示例.cpp`](vscode-kit/示例.cpp)（含类、构造函数、范围 for）。
> 上面这段、以及包内那份示例，都在发行包自带的编译器上**实测编译并运行通过**。

入口点可以写 `main`，也可以写 `主函数`：

```cpp
整数 主函数() { 返回 0; }   // 等价于 int main() { return 0; }
```

<details>
<summary><b>English summary</b></summary>

**Chinese++** is a modified Clang/LLVM toolchain that makes **Chinese keywords a first-class spelling** in C++. English keywords still work, and the two can be mixed freely in the same file.

```cpp
#包含 <cstdio>          // #include — a Chinese preprocessor directive
#include <vector>        // English directives still work; mix freely

整数 主函数() {                       // int main()
    std::vector<int> 数字{1, 2, 3};   // library names stay English
    整数 和 = 0;                      // int
    对于 (整数 n : 数字)              // for
        和 += n;
    std::printf("和 = %d\n", 和);
    返回 0;                           // return
}
```

- 99 Chinese keyword spellings, 22 Chinese preprocessor directives, 7344/7374 translated diagnostic messages
- `主函数` is the same identifier as `main`
- The standard library deliberately keeps its English names — renaming it would cut the project off from the existing ecosystem
- The `error:` / `warning:` prefixes stay English on purpose, so editors and CI keep parsing them
- Built on a modified **LLVM/Clang 24.0.0git**; the LLVM-derived parts stay under **Apache-2.0 WITH LLVM-exception** (see [`LICENSE.TXT`](LICENSE.TXT)); modification notice in [`NOTICE.txt`](NOTICE.txt). This project's **own** work is under **AGPL-3.0** (see [`LICENSE`](LICENSE) / [`LICENSE-AGPL-3.0.txt`](LICENSE-AGPL-3.0.txt), scope rules in [`LICENSE-SCOPE.md`](LICENSE-SCOPE.md)); name/logo policy in [`TRADEMARK.md`](TRADEMARK.md). **Programs you build with it are entirely yours.**
- Windows x64 only (`x86_64-pc-windows-msvc`)

**Requirement:** the **MSVC STL and Windows SDK are not bundled** — install Visual Studio Build Tools with the C++ workload first, or compilation will fail with `file not found: 'cstdio'`.

**Quick start:** install that workload → double-click `一键安装.cmd` → run `verify.ps1` to prove it works.

</details>

---

## 🔴 报错也是中文

学 C++ 最痛的时刻不是敲 `int`，是**编译器甩给你一屏英文**。

本工具链把 **7344 / 7374 条诊断正文**翻成了中文。前缀 `error:` **故意保留英文** —— 编辑器的问题面板和 CI 脚本靠它抓日志，翻成「错误:」它们就抓不到了。

### 同一段代码，两种输出

源码（故意留两个错）：

```cpp
结构 坐标 {              // 结构 = struct
    整数 纵坐标;
};

坐标点 甲;               // 错 1：没有这个类型

整数 主函数() {
    坐标 点;
    返回 点.横坐标;       // 错 2：没有这个成员
}
```

**英文**（`-fno-chinese-diagnostics`）：

```
示例.cpp:5:1: error: unknown type name '坐标点'; did you mean '坐标'?
    5 | 坐标点 甲;               // 错 1：没有这个类型
      | ^~~~~~
      | 坐标
示例.cpp:1:8: note: '坐标' declared here
    1 | 结构 坐标 {              // 结构 = struct
      |      ^
示例.cpp:9:16: error: no member named '横坐标' in '坐标'
    9 |     返回 点.横坐标;       // 错 2：没有这个成员
      |          ~~ ^
2 errors generated.
```

**中文**（默认）：

```
示例.cpp:5:1: error: 未知的类型名（类型名） '坐标点'；你是不是想写（类型名） '坐标'？
    5 | 坐标点 甲;               // 错 1：没有这个类型
      | ^~~~~~
      | 坐标
示例.cpp:1:8: note: （名字） '坐标' 在此声明
    1 | 结构 坐标 {              // 结构 = struct
      |      ^
示例.cpp:9:16: error: （类型名） '坐标' 中没有名为（成员名） '横坐标' 的成员
    9 |     返回 点.横坐标;       // 错 2：没有这个成员
      |          ~~ ^
生成了 2 个错误。
```

> 上面两段是**实测输出**（只略去了路径前缀）。注意中文版里那行 `note:` —— 有「你是不是想写」就一定会跟一条声明位置说明。

### `（类型名）` 这些括注是干什么的

**这是刻意的角色标注，不是翻译残留。**

英文的 `no member named '横坐标' in '坐标'` 里有两个引号标识符 —— **哪个是成员、哪个是类型，只能靠语序推断**；`did you mean '坐标'?` 里的 `'坐标'` 同样没说明它是什么。初学者经常推错。

所以我们给引号里的标识符**标上它的角色**：

```
error: （类型名） '坐标' 中没有名为（成员名） '横坐标' 的成员
        ^^^^^^^^                  ^^^^^^^^^^
        这是类型名                 这是成员名
```

一条消息里有多个标识符时，这个标注让「哪个是什么」一眼可见 —— 不需要先学会 C++ 的行话。

#### 角色一共 12 个

| 角色 | 出现次数 | 角色 | 出现次数 |
|---|---:|---|---:|
| `（名字）` | 2345 | `（选项）` | 368 |
| `（类型）` | 1374 | `（属性名）` | 314 |
| `（关键字）` | 537 | `（变量名）` | 237 |
| `（表达式）` | 427 | `（成员名）` | 207 |
| `（函数名）` | 397 | `（种类）` | 159 |
| `（类型名）` | 387 | `（符号）` | 140 |

**`（名字）` 最多，因为它是兜底项。** 翻译表里写死了一条规则：

> 能确定的写具体角色；不能确定的写兜底的（名字）。

`%0` 可能是变量、函数、类、名域……种类不定时就写 `（名字）` —— 所以它占了将近三分之一。

**但不是每个引号都有括注。** 角色标注加在**标识符**上；有些消息里的类型描述本来就是裸的：

```
error: 无法初始化 变量 ，其类型为 'int'，而 左值 的类型为 'const char[13]'
                                  ^^^^^                        ^^^^^^^^^^^^^^^
                                  这两个没有括注，原文如此
```

### 为什么中文报错里还有空格？

**因为汉字之间没有词边界。**

英文写 `cannot initialize a variable of type 'int'`，词与词之间天然有空格，眼睛扫过去就知道哪几个字母连成一个词。

中文如果连成一串 —— `无法初始化变量其类型为` —— 读的人要多花一次断句的力气。所以我们**在词与词之间补上空格**：

```cpp
整数 主函数() {
    整数 甲 = "hello world!";   // 整数 装不下字符串字面量
    返回 甲;
}
```

```
error: 无法初始化 变量 ，其类型为 'int'，而 左值 的类型为 'const char[13]'
                ↑      ↑  ↑
          分隔词与词、词与标点 —— 每个空格都是刻意加的
```

**逗号前那个空格也是刻意的** —— 它把前一个词和后面的标点分开，断句更快。

> 报错信息是拿来**扫**的，不是拿来**读**的。加空格让扫的速度接近英文。
### 随时可以切回英文

```powershell
chinese++ 你的文件.cpp -fno-chinese-diagnostics
```

```
-fchinese-diagnostics      Print diagnostics in Chinese (default)
-fno-chinese-diagnostics   Do not print diagnostics in Chinese
```

**中文只是多一个入口，不是替换。** 需要贴给同事、贴到 Stack Overflow、或者写进 CI 日志时，一个开关切回来。

### 这一屏，宏方案（`#define`）永远做不到

宏在编译器开始诊断之前就已经消失了 —— 它改不了报错里的任何一个字符。

---

## 这是什么

一套**修改过的 Clang/LLVM 工具链**。改动只集中在"让编译器认得中文"这一件事上：

| 改动 | 规模 |
|---|---|
| 中文关键字拼写表 | 99 条 |
| 中文预处理指令拼写表 | 22 条，与英文等价、可混用 |
| 中文诊断正文表 | 7344 / 7374 条，查不到时回退英文 |
| `主函数` 与 `main` | 成为同一个标识符 |

**英文拼写一律保留、行为不变。** 改动不涉及任何 `Diagnostic*.td` —— 那 17 个文件与上游**逐字节相同**。

---

## 快速开始

**下载：** [最新发布版](https://github.com/YoloLogic/ChinesePlusPlus/releases/latest) ·
直接下 [Chinese++-0.3-win64.zip](https://github.com/YoloLogic/ChinesePlusPlus/releases/latest/download/Chinese++-0.3-win64.zip)

> 在 Releases 页面找 **Assets** 区块 —— 它**可能是折叠的，点一下展开**才能看到附件。

### 第 1 步：Visual Studio —— **可选**（默认那套工具链不需要它）

本包自带一套工具链基底（`bundled` 模式，**默认**）：

| 在包里 | 是什么 |
|---|---|
`lib\stl`（176 个头） | 开源版 **MSVC STL 头** |
`lib\mingw`（2037 个） | mingw-w64 的 **UCRT + Win32 头** |
`lib\crt`（29 个） | 我们自己的 **CRT 与导入库** |
`lib\compiler`（12 个） | 编译器支持头（手写） |
`bin\*.dll`（10 个） | **VC++ 运行时 DLL**（app-local） |
`zhstdlib\`（119 个头） | **汉语标准库**（`#包含 <向量>` 那一层） |

**实测**（`install.ps1` 结尾会自己跑 `verify.ps1`；下面是 0.3 包在 2026-10-09 的真实输出）：

```
--- 3) Visual Studio Build Tools  [bundled mode]
found: C:\Program Files\Microsoft Visual Studio\2022\Community
(bundled mode does not use it: headers/CRT/import libs and lld-link all come from this package)
[ok]   compiles a Chinese include + std::vector in one file, with no flags (bundled mode)
[ok]   the Chinese-library program links and runs (exit 0, bundled mode)
[ok]   <windows.h> + a Chinese header resolve with NO Microsoft path anywhere (608 includes traced)
[ok]   bundled mode: the link read 48 libraries, none from Program Files
  26 passed, 0 failed -- this package works.
```

注意后两行：**没有任何微软路径参与**、**链接读的 48 个库没有一个来自 Program Files**。

**那你什么时候还需要 Visual Studio？** 只有想用 `system` 模式时才需要：

| 模式 | 怎么开 | 用谁的标准库 | 什么时候选它 |
|---|---|---|---|
`bundled`（**默认**） | 什么都不用做 | 包内自带的那套基底 | 开箱即用；不想在别人机器上再装东西；CI |
`system` | `powershell -File install.ps1 -Toolchain system` | **你机器上**的 Visual Studio / Windows SDK | 要和现有 VS 工程、现成第三方库**完全一致**地链接时 |

（选完记在 `bin\toolchain.txt`；`verify.ps1` 按**实际在用的**那种基底验。
0.1/0.2 早期确实"必须先装 VS" —— 那时只发编译器本体；**0.2 起带了基底**，本 README 与 `常见问题.md` 都已订正。）

**要装的话**（想用 system 模式）：

```powershell
# 最快：一行命令
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

- **Build Tools 直链**（点开就下安装器，约 2 GB）：<https://aka.ms/vs/17/release/vs_BuildTools.exe>
- **完整版 Visual Studio Community**（免费，图形界面更友好）：<https://visualstudio.microsoft.com/vs/community/>
  —— 安装时**务必勾选「使用 C++ 的桌面开发」**
- 官方图文安装教程：<https://learn.microsoft.com/cpp/build/vscpp-step-0-installation>

> 下载约 2 GB，装完约占 6 GB，需要管理员权限，需要几分钟。

**system 模式没装的症状**：编译时报 `找不到文件（名字） 'cstdio'`。

**不确定装没装？** 跑第 3 步的 `verify.ps1` —— 它真编真链接真运行，**26 项全过**才算能用。

### 第 2 步：双击 `一键安装.cmd`

它会做这些事（**全部在这个文件夹内**）：

- 重建 9 个硬链接别名（`clang.exe`、`clang-cl.exe`、`lld.exe`…）
- 生成 `env.cmd` —— 窗口级 PATH 设置器，**不碰你的永久 PATH**
- **写好 `bin\` 里的三个 `<驱动名>.cfg`**（`chinese++.cfg` / `clang++.cfg` / `clang.cfg`）——
  汉化库的搜索路径就在里面。**所以你不用记任何 `-isystem`**：命令行直接 `chinese++ 你的.cpp`，
  编辑器（clangd）读的也是同一份。
  ⚠ 里面是**绝对路径**：**移动或改名本文件夹之后，重新双击一次一键安装**即可。
- 检查 Visual Studio Build Tools，缺了就打印**确切**要装什么
- 把官方 VS Code 下载到本目录的 `.\vscode\`，用**便携模式**配好（中文语言包 + clangd），**你自己装的那个 VS Code 一个字节都不动**
- 跑**包内自测**（26 项）：中文关键字、`#包含 <向量>` 不带任何 `-I` 也能编、AddressSanitizer 真报一次
  内存错误、`--coverage` 真链上……**全过才算能用**

> **需要联网**（下载 VS Code 约 320 MB）。断网了就重新双击一次，已装好的部分不会重装，中断的部分会重来，**不需要先删掉什么**。

### 第 3 步：验证

```powershell
powershell -File verify.ps1
```

它会从包内真编一个中文 hello world。**过了就是能用。**

---

## 包里有什么

```
bin\chinese++.exe          C++ 编译器（中文为主，英文照旧可用）
bin\clang.exe              C 编译器（与上面是同一个程序，靠文件名分派）
bin\clang-cl.exe           MSVC 风格命令行
bin\clang-cpp.exe          仅预处理（-E）
bin\clangd.exe             语言服务（编辑器高亮与补全用）
bin\lld-link.exe           Windows 链接器
bin\llvm-ar.exe            archiver
bin\llvm-rc.exe            Windows 资源编译器
zhstdlib\                  ★ 汉化库：119 个中文头
                             标准库\ 48（向量 / 字符串 / 映射 / 算法 …）
                             别名\ 43    C运行库\ 25（C标准输入输出 / C数学 …）
                             windows系统\ 3（Windows系统 / 窗口 / 绘图）
tools\                     两个安装用的小脚本（搜索路径的唯一真相 + 写成 bin\*.cfg）
lib\clang\24\include\      编译器内建头文件（stddef.h / stdint.h 等）
                             ＋ sanitizer\ profile\ fuzzer\ —— 运行时接口头（写 `#include <sanitizer/asan_interface.h>` 用）
lib\clang\24\lib\windows\  compiler-rt 运行时（asan / ubsan / profile）
lib\clang\24\share\        sanitizer 的 ignorelist
vscode-kit\                编辑器配置套件
```

> 安装之后还会多出：`bin\*.cfg`（三个搜索路径配置，见第 2 步）、`examples\`（编辑器配置副本与示例）、
> `env.cmd`。`vscode\` 是安装时按需下载的便携编辑器。

> 上面若干 `.exe` 是**同一个程序的硬链接**。若复制或解压后硬链接丢失，会变成多份独立副本 —— 功能不受影响，只是占用变大。`install.ps1` 会用 `New-Item -ItemType HardLink` 重建。

## 包里【没有】什么

| 缺什么 | 为什么 | 怎么办 |
|---|---|---|
| MSVC STL、Windows SDK、`link.exe` | 微软的东西，无权分发 | 自己装 Visual Studio Build Tools |
| `opt` / `llc` / `lldb` / `clang-tidy` / `libclang` / `polly` | 编译用不到 | —— |
| Visual C++ 运行库（`MSVCP140.dll`、`VCRUNTIME140.dll`） | 微软可再分发运行库 | 开发机装了 Visual Studio 即已具备 |
| `orc_rt` / `xray` / `memprof` 的运行时与头 | 本次构建**显式关闭**了这三个运行时 | 用不上；要的话得自己按 `tools\build_runtimes.ps1` 的注释改开关重编 |

---

## 中文覆盖到哪一层

**覆盖的是「语言本身」：**

- **关键字** —— `整数`、`如果`、`返回`、`类型`…
- **预处理指令** —— `#包含`、`#定义`…（**`#` 不能省**；写成 `包含 <cstdio>` 会被当成未声明的标识符）
- **诊断信息正文** —— 报错解释是中文
- **`主函数` ≡ `main`**

**还覆盖了「库」这一层（中文是并列多出来的另一种拼写，英文原名照旧可用）：**

```cpp
#包含 <向量>                     // 头名也能用中文；<vector> 照旧
整数 主函数(){
    标准::向量<整数> 表;          // std::vector<int> 照旧可用
    表.尾插(1); 表.尾插(2);       // .push_back() 照旧可用
    返回 (整数)表.尺寸() == 2 ? 0 : 1;   // .size() 照旧可用
}
```

`zhstdlib\` 里是 **119 个中文头**：标准库 48（向量 / 字符串 / 映射 / 算法 / 迭代器…）＋ 别名 43 ＋
C 运行库 25（C标准输入输出 / C数学 / C字符串…）＋ windows系统 3（**`Windows系统`**：句柄 / 文件 /
进程 / 同步对象 / 内存 / 注册表 / 环境变量 / 动态库 / 时间；
**`窗口`**：窗口类 / 消息 / 控件 / 菜单；**`绘图`**：GDI，画矩形 / 画线 / 输出文本…）。

> **边界（说清楚，别误会）**：中文库是**我们另抄、另起名的一层**（`标准::向量`），
> 与微软的 `std::vector` **内存布局相同、但不是同一个类型**，互相传参要显式转换；
> **微软的头文件一个字节没动** —— 这也是为什么它既"完全是汉语书写的"、又不切断生态。
> GDI / 窗口那部分要额外链 `gdi32.lib` / `user32.lib`（包内 `使用说明`/`常见问题` 有例子）。

同理，报错前缀 `error:` / `warning:` **故意保留英文** —— 编辑器的问题面板和 CI 脚本靠这个前缀抓日志，翻成「错误:」它们就抓不到了。

---

## 文档

| 文件 | 内容 |
|---|---|
| **[`常见问题.md`](常见问题.md)** | **使用前必读** —— 安装、编辑器、报错排查、许可与再分发 |
| [`中文对照表.md`](中文对照表.md) | 中英关键字对照表。由脚本从编译器**真正在用的那两张表**自动生成，不是手写的 —— 手写的副本一定会和编译器漂移 |
| [`NOTICE.txt`](NOTICE.txt) | 发行说明、改动清单、第三方声明（**0.3 起按实况订正**） |
| [`MANIFEST.txt`](MANIFEST.txt) | 构建时间与各文件的 SHA256 |
| [`LICENSE`](LICENSE) | 许可总览（先看这一份） |
| [`LICENSE-AGPL-3.0.txt`](LICENSE-AGPL-3.0.txt) | 本项目**原创部分**的许可正文（AGPL-3.0） |
| [`LICENSE-SCOPE.md`](LICENSE-SCOPE.md) | **哪些算 AGPL、哪些不算**（含"看文件头 SPDX"的机器可查规则） |
| [`LICENSE.TXT`](LICENSE.TXT) | LLVM 的许可正文（Apache-2.0 with LLVM Exceptions，与上游逐字节相同） |
| [`TRADEMARK.md`](TRADEMARK.md) | 名称与图标条款（与软件许可分开） |

---

## 基于 LLVM

本发行包里的 `clang` / `lld` / `clangd` / `llvm-*` 二进制，**是由修改过的 LLVM 源码构建的，不是上游原版。**

依据 Apache License 2.0 第 4(b) 条，我们在此明确声明：**我们改动了若干 LLVM/Clang 源文件。** 改动范围与理由见 [`NOTICE.txt`](NOTICE.txt)。

- 上游项目：[llvm.org](https://llvm.org/)（LLVM 24.0.0git）
- 目标平台：`x86_64-pc-windows-msvc`

## 许可证（0.3 起：本项目原创部分用 AGPL-3.0）

本发行包**不是单一许可**。判定规则与逐项说明见 [`LICENSE-SCOPE.md`](LICENSE-SCOPE.md)：

| 哪一部分 | 许可 | 你能做什么 |
|---|---|---|
本项目原创（中文关键字表 / 中文诊断正文表 / 中文标准库里我们写的那部分 / 安装与自检脚本 / 文档） | **AGPL-3.0** —— 正文 [`LICENSE-AGPL-3.0.txt`](LICENSE-AGPL-3.0.txt) | 读、改、用、再分发；**改了再分发要同样开源**，做成网络服务也要给源码 |
从 **LLVM/Clang** 派生的（全部二进制、`lib\clang\**`、补丁） | **Apache-2.0 with LLVM Exceptions** —— 正文 [`LICENSE.TXT`](LICENSE.TXT)（15141 字节，与上游逐字节相同） | 可再分发、可商用、可再许可 —— **不受**本项目 AGPL 限制，我们也无权限制 |
从**微软 MSVC STL** 派生的（中文标准库里的深度复制轨道） | 同上，**不是** AGPL。判定办法：文件头带 `SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception` | 同上 |
第三方随包（`lib\mingw\` 的 mingw-w64 头、`lib\stl\` 的开源版 MSVC STL 头、`bin\*.dll`） | 各按各的许可，逐项见 [`NOTICE.txt`](NOTICE.txt) | 那些 DLL 是微软**可再分发**的运行库 |

* **你用本工具链编译出来的程序，版权与许可完全归你** —— AGPL 不对编译产物附加任何条件。
* **名称与图标**（`Chinese++` / `汉语编程`）**独立于软件许可**，见 [`TRADEMARK.md`](TRADEMARK.md)：
  再分发本身允许（AGPL 允许，Apache-2.0 也允许），但不得用本项目名称与图标发布衍生版本。
* 关于微软部分，如实说明：包里**带了**开源版 MSVC STL 头、mingw-w64 的 UCRT/Win32 头、
  我们自己的 CRT 与导入库，以及 **10 个 app-local 的、微软明确允许再分发的 VC++ 运行时 DLL** ——
  这正是"默认 `bundled` 模式开箱即用、不用先装 Visual Studio"的原因。
  **微软的 Windows SDK 库与 MSVC 工具链本体（cl.exe 等）不在包内**，要用 `system` 模式请自行安装并遵守微软条款。
  本工具链**不是**微软官方产品，与 Microsoft 无隶属或背书关系。

## 免责声明

**本工具链按「现状」提供，不附带任何担保。** 使用它及其脚本所造成的任何后果 —— 包括但不限于系统或数据损坏、软件冲突、编译产物有问题、项目延期 —— **发布者不承担责任。** 请在使用前自行备份重要数据。

本包内 LLVM / Clang 部分依 Apache License v2.0 with LLVM Exceptions 分发，**其中的免责与责任限制条款同样适用**；本项目原创部分依 AGPL-3.0 分发（正文见 [`LICENSE-AGPL-3.0.txt`](LICENSE-AGPL-3.0.txt)），该许可证同样**不含任何担保**。

---

## 反馈

有问题、报 bug、提建议，欢迎在本仓库的 **Issues** 里提出。
