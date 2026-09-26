# Chinese++ · 中文编程

> **作者个人理解的完美的汉语编程。**

中文关键字是 Clang/LLVM 的**第一公民**。英文拼写照旧可用，两种写法可以随意混写。

```cpp
整数 main() {
  标准::输出 << "你好，世界" << 标准::换行;
  返回 0;
}
```

入口点可以写 `main`，也可以写 `主函数`：

```cpp
整数 主函数() { 返回 0; }   // 等价于 int main() { return 0; }
```

<details>
<summary><b>English summary</b></summary>

**Chinese++** is a modified Clang/LLVM toolchain that makes **Chinese keywords a first-class spelling** in C++. English keywords still work, and the two can be mixed freely in the same file.

```cpp
整数 main() {                                // int main()
  标准::输出 << "你好，世界" << 标准::换行;   // std::cout << "Hello, world" << std::endl;
  返回 0;                                     // return 0;
}
```

- 99 Chinese keyword spellings, 22 Chinese preprocessor directives, 7344/7374 translated diagnostic messages
- `主函数` is the same identifier as `main`
- The standard library deliberately keeps its English names — renaming it would cut the project off from the existing ecosystem
- The `error:` / `warning:` prefixes stay English on purpose, so editors and CI keep parsing them
- Built on a modified **LLVM/Clang 24.0.0git**, distributed under **Apache-2.0 WITH LLVM-exception** (see [`LICENSE.TXT`](LICENSE.TXT)); modification notice in [`NOTICE.txt`](NOTICE.txt)
- Windows x64 only (`x86_64-pc-windows-msvc`)

**Requirement:** the **MSVC STL and Windows SDK are not bundled** — install Visual Studio Build Tools with the C++ workload first, or compilation will fail with `file not found: 'cstdio'`.

**Quick start:** install that workload → double-click `一键安装.cmd` → run `verify.ps1` to prove it works.

</details>

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

### 第 1 步：先装 Visual Studio（**必须，别跳过**）

**本工具链不自带标准库。** C++ 标准库（`std::vector`、`std::string`…）、C 运行库、Windows SDK 都是微软的东西，没有权利把它们打包分发。

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

或者下载 **Visual Studio Community**（免费），安装时勾选 **「使用 C++ 的桌面开发」**。

> 下载约 2 GB，装完约占 6 GB，需要管理员权限，需要几分钟。

**这也是一件好事**：正因为用的是微软原封不动的 MSVC STL，本编译器编出来的东西和官方 clang / MSVC 编出来的**二进制兼容**，可以互相链接，现成的第三方库照用。

**没装的症状**：编译时报 `找不到文件（名字） 'cstdio'`。看到"找不到文件"这类错，十有八九就是这一条。

### 第 2 步：双击 `一键安装.cmd`

它会做这些事（**全部在这个文件夹内**）：

- 重建 9 个硬链接别名（`clang.exe`、`clang-cl.exe`、`lld.exe`…）
- 生成 `env.cmd` —— 窗口级 PATH 设置器，**不碰你的永久 PATH**
- 检查 Visual Studio Build Tools，缺了就打印**确切**要装什么
- 把官方 VS Code 下载到本目录的 `.\vscode\`，用**便携模式**配好（中文语言包 + clangd），**你自己装的那个 VS Code 一个字节都不动**
- 编译并运行一个中文 hello world，**证明它真的能用**

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
lib\clang\24\include\      编译器内建头文件（stddef.h / stdint.h 等）
lib\clang\24\lib\windows\  compiler-rt 运行时（asan / ubsan / profile）
vscode-kit\                编辑器配置套件
```

> 上面若干 `.exe` 是**同一个程序的硬链接**。若复制或解压后硬链接丢失，会变成多份独立副本 —— 功能不受影响，只是占用变大。`install.ps1` 会用 `New-Item -ItemType HardLink` 重建。

## 包里【没有】什么

| 缺什么 | 为什么 | 怎么办 |
|---|---|---|
| MSVC STL、Windows SDK、`link.exe` | 微软的东西，无权分发 | 自己装 Visual Studio Build Tools |
| `opt` / `llc` / `lldb` / `clang-tidy` / `libclang` / `polly` | 编译用不到 | —— |
| Visual C++ 运行库（`MSVCP140.dll`、`VCRUNTIME140.dll`） | 微软可再分发运行库 | 开发机装了 Visual Studio 即已具备 |

---

## 中文覆盖到哪一层

**覆盖的是「语言本身」：**

- **关键字** —— `整数`、`如果`、`返回`、`类型`…
- **预处理指令** —— `包含`、`定义`…
- **诊断信息正文** —— 报错解释是中文
- **`主函数` ≡ `main`**

**没有覆盖的是「标准库」：**

`std::vector`、`.push_back()`、`printf` **保持英文原样**。

这是**故意的**。改名会切断生态 —— 所有第三方库、所有教程、所有现成代码全都对不上。中文是**并列多出来的一种拼写**，不是替换英文。

同理，报错前缀 `error:` / `warning:` **故意保留英文** —— 编辑器的问题面板和 CI 脚本靠这个前缀抓日志，翻成「错误:」它们就抓不到了。

---

## 文档

| 文件 | 内容 |
|---|---|
| **[`常见问题.md`](常见问题.md)** | **使用前必读** —— 安装、编辑器、报错排查 |
| [`中文对照表.md`](中文对照表.md) | 中英关键字对照表。由脚本从编译器**真正在用的那两张表**自动生成，不是手写的 —— 手写的副本一定会和编译器漂移 |
| [`NOTICE.txt`](NOTICE.txt) | 发行说明、改动清单、第三方声明 |
| [`MANIFEST.txt`](MANIFEST.txt) | 构建时间与各二进制的 SHA256 |
| [`LICENSE.TXT`](LICENSE.TXT) | 许可证正文 |

---

## 基于 LLVM

本发行包里的 `clang` / `lld` / `clangd` / `llvm-*` 二进制，**是由修改过的 LLVM 源码构建的，不是上游原版。**

依据 Apache License 2.0 第 4(b) 条，我们在此明确声明：**我们改动了若干 LLVM/Clang 源文件。** 改动范围与理由见 [`NOTICE.txt`](NOTICE.txt)。

- 上游项目：[llvm.org](https://llvm.org/)（LLVM 24.0.0git）
- 目标平台：`x86_64-pc-windows-msvc`

## 许可证

本发行包内 LLVM 派生的全部内容，采用 **Apache License v2.0 with LLVM Exceptions** 分发。许可证正文完整附于 [`LICENSE.TXT`](LICENSE.TXT)（15141 字节，与上游 `LICENSE.TXT` 逐字节相同）。**请连同该文件一起分发。**

本工具链**不是**微软官方产品，与 Microsoft 无隶属或背书关系。它使用但你**没有**获得微软的 MSVC STL、Windows SDK 与 Visual C++ 运行库 —— 那些需要使用者自行安装并遵守微软自己的许可条款。

## 免责声明

**本工具链按「现状」提供，不附带任何担保。** 使用它及其脚本所造成的任何后果 —— 包括但不限于系统或数据损坏、软件冲突、编译产物有问题、项目延期 —— **发布者不承担责任。** 请在使用前自行备份重要数据。

本包内 LLVM / Clang 部分依 Apache License v2.0 with LLVM Exceptions 分发，**其中的免责与责任限制条款同样适用。**

---

## 反馈

有问题、报 bug、提建议，欢迎在本仓库的 **Issues** 里提出。
