# Chinese++ 的许可范围（哪些是 AGPL、哪些不是）

> 这一份说明**为什么**包里同时存在多种许可，以及**怎么判定**某个文件属于哪一种。
> 判定规则是**机器可查**的（看文件自己的声明），不靠人记。

著作权归项目作者所有。各部分适用不同许可：

## 一、本项目原创部分 —— **AGPL-3.0**

采用 **GNU Affero General Public License v3.0**（完整正文见同目录 `LICENSE-AGPL-3.0.txt`）：

* 中文关键字拼写表、中文预处理指令拼写表、中文诊断正文表，以及它们的生成器与守卫
* `zhstdlib\` 中**我们自己写的**部分：中文别名层、C 包装头（`zhstdlib\C运行库\*`）、
  Windows 系统头的中文名层（`zhstdlib\windows系统\*`），以及手写的薄壳
* `tools\`、`packaging\`、`tests\`、`docs\`、`patches\` 下的脚本、数据与文档
* 发行包里的 `install.ps1`、`verify.ps1`、`*.cmd` 与全部中文说明文档

**用本工具链编译出来的程序/库，版权与许可完全由作者自己决定。**
本许可**不**对编译产物附加任何条件（不"传染"到你的软件）——这是明确的授权，不需要再问。

## 二、从 LLVM / Clang 派生的部分 —— **Apache-2.0 with LLVM Exceptions**

* `bin\chinese++.exe`（就是 clang）、`clangd`、`lld-link`、`llvm-ar`、`llvm-rc` 等**全部二进制**
* `lib\clang\**`（编译器内建头与 compiler-rt 运行时）
* LLVM 源码的补丁（`patches\*`）

这些**不是**本项目的版权：它们派生自 LLVM/Clang，按 **Apache License v2.0 with LLVM Exceptions**
分发（正文见同目录 `LICENSE.TXT`，与上游逐字节相同）。

⇒ **你从本发行包拿到的这些二进制，仍然享有 Apache-2.0 给你的全部权利**（可以再分发、可以商用、可以再许可）。
本项目的 AGPL **不改变、也无权改变**这一部分的权利。

## 三、从微软 MSVC STL 派生的部分 —— 同样是 **Apache-2.0 with LLVM Exceptions**

`zhstdlib\标准库\` 里**深度复制轨道**的那些头（例如派生的 `向量实现`、`字符串内部件` 等）
派生自 **MSVC STL**。**判定办法**：文件头带

```
// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
```

的，就按 **Apache-2.0 with LLVM Exceptions** 处理，**不适用** AGPL。

（`zhstdlib\标准库\` 里由我们手写、只做 `#包含` 与把英文原名补回来的**薄壳**，属第一条的 AGPL。）

## 四、第三方（随包但不属于我们，各按各的许可）

| 在包里 | 是什么 | 许可 / 来源 |
|---|---|---|
`lib\mingw\`（2037 个文件） | mingw-w64 的 UCRT + Win32 头 | mingw-w64 项目（多为 public domain 或 MIT 类），以各文件头为准 |
`lib\stl\`（176 个文件） | **开源版 MSVC STL 头** | microsoft/STL，Apache-2.0 with LLVM Exceptions |
`bin\*.dll`（10 个） | Visual C++ 运行时库（app-local，`msvcp140*.dll` / `vcruntime140*.dll` 等） | 微软**可再分发**运行库，按其再分发条款随包附带 |
`lib\crt\`、`lib\compiler\` | 我们自己的 CRT/导入库与编译器支持头 | 本项目（第一条 AGPL） |

逐文件来源与 SHA256 见包内 `MANIFEST.txt`。

## 五、名称与图标

见同目录 `TRADEMARK.md`。**名称限制独立于软件许可** —— AGPL 给你复制、修改、再分发代码的权利，
但它**不**给你使用本项目名称与图标的权利。

## 六、一句话概括

> * 我们写的东西：**AGPL-3.0**（改了要开源；做成网络服务也要给源码）。
> * LLVM / 微软的东西：各按各的许可（Apache-2.0 with LLVM Exceptions 等）—— 我们没有、也不会给它们加限制。
> * 你用本工具链写出来的程序：**完全归你**，不附加任何条件。
> * 名字：AGPL 允许你再分发，但**名字**是我们保留的（见 `TRADEMARK.md`）。