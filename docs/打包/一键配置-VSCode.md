# 一键配置 VS Code（推荐的第一个动作）

> 状态：**设计，未实施**（2026-09-23 起草；当天写过一个草稿，按用户要求已删除，
> 本文把那份草稿的思路与配置内容完整保留下来，随时可以照着重建）。
>
> 本文里的配置内容**不是凭空设计的** —— 它们是从仓库里那套**已经实测通过**的
> `.vscode\*.json` + `.clangd` 泛化来的（那套的调试配置、clangd 参数都验证过）。

---

## 一、目标（用户视角）

> 用户**已经有 VS Code**（也大概率已经有 VS Build Tools）→ **点一下**我们给的脚本 →
> 配置好了 → 他能：
>
> 1. 用中文关键字写代码，**能编译运行**
> 2. 报错和警告是**中文**
> 3. 中文关键字**不被识别为未知**（不标红）
> 4. 后悔了可以**一键还原**

## 二、为什么这一步比"捆 1 GB 的 STL"划算

| | 一键配置 | 阶段 3（零依赖） |
|---|---|---|
| 我们要做的 | 几个配置模板 + 安装/卸载/自测脚本 | 编 `lld-link`、捆 STL + SDK、处理版本锁与许可 |
| 体积 | 几乎为零（复用用户已有的） | +1 GB |
| 长期维护 | 低 | 每次 VS/SDK 升级都要跟 |
| 解决的是 | **第一印象**：像不像中文编程 | 能不能装得上 |

而**第一印象才是决定别人会不会继续用的东西** —— 装 VS 是"一次性的痛"，
编辑器里满屏红波浪线是"每天的痛"。

## 三、要落地的东西（目录结构）

```
<工具链根>\
├── bin\chinese++.exe            ← 我们的编译器
├── bin\clangd.exe               ← 我们的 clangd（认中文关键字的那一个）
├── lib\clang\24\include\
└── vscode-kit\                  ← 这一套
    ├── README.md                ← 中文说明 + 排查表
    ├── 安装到VS Code.cmd         ← 双击/拖放这一个
    ├── 卸载.cmd                  ← 还原
    ├── install.ps1              ← 逻辑（纯 ASCII）
    ├── uninstall.ps1            ← 还原（纯 ASCII）
    ├── verify.ps1               ← 自测（纯 ASCII）
    ├── messages.txt             ← 中文文案（UTF-8 数据文件）
    ├── templates\
    │   ├── settings.json
    │   ├── tasks.json
    │   ├── launch.json
    │   ├── .clangd
    │   ├── 示例.cpp
    │   └── 中文控制台.h
    └── verify-samples\
        └── 报错.cpp
```

**关键设计**：`vscode-kit\` 放在工具链里，脚本从**自己的位置**推导工具链路径
（`$PSScriptRoot\..`），所以工具链搬到任何盘符都能用，没有硬编码路径。

## 四、四个配置文件的关键点（以及为什么）

### 4.1 `settings.json`

```jsonc
{
  // ① 必须指向【我们的】clangd
  //    clangd 扩展默认会自己下载一个官方 clangd，那个不认识中文关键字 → 满屏红波浪
  "clangd.path": "@@CLANGD@@",

  "clangd.arguments": [
    "--background-index",
    "--clang-tidy",
    "--header-insertion=iwyu",
    "--completion-style=detailed",
    "--pch-storage=memory",
    "--fallback-style=LLVM",
    // ② 让它去问我们的编译器"系统头在哪"（MSVC STL / Windows SDK）
    //    没有这一条，#include <cstdio> 会报找不到
    "--query-driver=@@CXX@@"
  ],

  "clangd.onConfigChanged": "restart",

  // ③ 中文源码必须 UTF-8 读写
  "files.encoding": "utf8",
  "files.autoGuessEncoding": false,

  // ④ 微软 C/C++ 扩展只当【调试器】用，关掉它的 IntelliSense，免得和 clangd 抢标红
  "C_Cpp.intelliSenseEngine": "disabled",

  "[cpp]": { "editor.tabSize": 4, "editor.insertSpaces": true },

  "files.exclude": { "**/*.obj": true, "**/*.ilk": true, "**/*.pdb": true, "**/*.pcm": true },
  "search.exclude": { "**/out": true }
}
```

> `.pdb` 只是被**隐藏**，没被删 —— 调试要用它，删了断点会失效。

### 4.2 `.clangd`（必须有）

```yaml
CompileFlags:
  Add: [-std=c++20]
```

**为什么必须有**：没有 `compile_commands.json` 时 clangd 用回退命令，
而它的回退默认是 **`-std=c++14`**（实测它传给 cc1 的正是这个）。
于是用了 C++20 特性（概念 / 模块 / 约束）的文件会被**误标红**，明明能编过。

### 4.3 `tasks.json`

```jsonc
{
  "version": "2.0.0",
  "tasks": [
    { "label": "编译当前文件", "type": "shell", "command": "@@CXX@@",
      "args": ["-std=c++20","-g","-Wall","${file}","-o","${fileDirname}\\${fileBasenameNoExtension}.exe"],
      "options": { "cwd": "${fileDirname}" },
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": ["$gcc"] },

    { "label": "编译并运行", "type": "shell", "command": "@@CXX@@",
      "args": ["-std=c++20","-g","-Wall","${file}","-o","${fileDirname}\\${fileBasenameNoExtension}.exe",
               "&&","${fileDirname}\\${fileBasenameNoExtension}.exe"],
      "options": { "cwd": "${fileDirname}" },
      "problemMatcher": ["$gcc"] },

    { "label": "只检查语法（看中文报错）", "type": "shell", "command": "@@CXX@@",
      "args": ["-std=c++20","-Wall","-fsyntax-only","${file}"],
      "options": { "cwd": "${fileDirname}" },
      "problemMatcher": ["$gcc"] }
  ]
}
```

> **`problemMatcher: "$gcc"` 靠的是"前缀不翻"那个决定。**
> 它用正则匹配 `error: ` / `warning: ` 把报错抓进 Problems 面板（能点、能跳转）。
> 我们的诊断**只换正文不换前缀**：
> ```
> error: 未知的类型名（类型名） '我的类型'
> ^^^^^   前缀仍是英文 ⇒ $gcc 照样认得
> ```
> 如果哪天把前缀翻成「错误:」，这里就会失灵。
> 这也是《诊断汉化清单.md》里把"前缀故意不翻"写成硬约束的实际理由之一。

### 4.4 `launch.json`

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    { "name": "调试当前文件", "type": "cppvsdbg", "request": "launch",
      "program": "${fileDirname}\\${fileBasenameNoExtension}.exe",
      "cwd": "${fileDirname}", "console": "integratedTerminal",
      "preLaunchTask": "编译当前文件" }
  ]
}
```

> **`type` 必须是 `cppvsdbg`，不能是 `cppdbg`。**
> `cppvsdbg` = Visual Studio 调试器，读 Windows 原生调试信息（PDB / CodeView）。
> `cppdbg` = 给 GDB/LLDB 用的，读 DWARF。
> 我们的 clang 在 Windows 上发的是 **CodeView**（加 `-g` 后是 `.pdb`，实测里面是 `RSDS`
> 记录、没有 DWARF）—— 用错的表现是"能启动但断点全是空心圆，永远不命中"。

### 4.5 终端必须设成 UTF-8（**已落地，且证明过可逆**）

用户实测反馈："终端把 UTF-8 当成 GBK，汉字是乱码。" 诊断出来的乱码形态：

```
终端代码页 936 (GBK)
程序输出的字节   E5 9C 86 20 E9 9D A2 E7 A7 AF ...     （"圆 面积"）
按 UTF-8 解释 -> 圆 面积 = 12.5664      ← 程序真正想说的
按 GBK   解释 -> 鍦?闈㈡Н = 12.5664     ← 用户看到的
```

**关键认识：乱码有两层，位置不同，只治一层会剩一半**

| 层 | 什么时候 | 为什么乱 |
|---|---|---|
| ① 用户程序打印的中文 | 运行时 | 程序发 UTF-8 字节，GBK 终端按 GBK 解释 |
| ② **编译器自己的中文报错** | 编译时 | 诊断也是 UTF-8 字节，**同样**被 GBK 解释成花屏 |

把终端设成 UTF-8，**①②一起解决**。这是最终选定的方案。

#### 走过两条弯路，**别重试**

| 写法 | 结果 |
|---|---|
| `.vscode\settings.json` 里 `args: ["-NoExit","-Command","chcp 65001 > $null; [Console]::OutputEncoding = …"]` | ❌ 终端一开报 `表达式或语句中包含意外的标记"-Command"`（引号被拼丢） |
| 同上但换成短命令 `args: ["-NoExit","-Command","chcp 65001"]` | ❌ 终端一开报 `参数格式不正确 - -Command` |

**两次根因相同**：命令行里出现了**第二个 `-Command`**（VS Code 的 shell 集成 /
conda 注入会再加一个），而 PowerShell **只认第一个** `-Command`，把后面全当脚本文本 →
实际执行的是 `chcp 65001 -Command …` → chcp 收到 `-Command` 就报错。
**硬规矩：终端 profile 的 `args` 里永远不要放 `-Command`。** 它必须独占、只能出现一次，
而"别人也想用 `-Command`"是你控制不了的。

另两种**实测**也不可行：`chcp 65001>nul`（PowerShell 把 `65001>nul` 当整一个参数传给
chcp → `Parameter format not correct`）、`[Console]::OutputEncoding=[Text.Encoding]::UTF8`
（**惰性**，要等 .NET 第一次写控制台才生效，当场 `chcp` 仍是 936）。

#### 最终方案：改用户自己的 `$PROFILE`（附脚本，已验证可逆）

不碰任何 VS Code 配置，而是往用户自己的 PowerShell profile 里加一段**带标记的块**：

```powershell
try { chcp 65001 > $null } catch { }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { $OutputEncoding = [Text.Encoding]::UTF8 } catch { }
```

`$PROFILE` 不经过任何编辑器的参数拼接，所以**在任何终端都生效**
（VS Code 集成终端 / 普通窗口 / 别的 IDE 的终端），而且两层乱码一起治。

脚本：`tools\setup_utf8_terminal.ps1`（`-Undo` 撤销，`-WhatIfOnly` 预演）。
**只碰本来就存在的 profile 文件**；没有则创建宿主专用那个。
块首行写入 `prev-chars=<原字符数>`，`-Undo` 按它截断回原长度。

#### 改 `$PROFILE` 会不会弄坏别的工具？——不会，实测过

| 工具 | 在 CP936 终端 | 在 CP65001 终端 |
|---|---|---|
| 我们的 clang（**固定**发 UTF-8） | ❌ 乱码 | ✅ 正常 |
| MSVC 的 `cl.exe`（发 GBK） | ✅ 正常 | ✅ **也正常** —— 它会**跟着代码页**改成 UTF-8 |

#### 可逆性是**证明**过的（不是"应该没问题"）

```
基线        269 字节  SHA256 前16 0F9125A2EB391C3A
安装后      830 字节  含 prev-chars=269，conda 段落完好，BOM 仍为 False
有效验证    父控制台先 chcp 936 → 新 PowerShell 报 65001   ← 只有 profile 能做到
撤销后      269 字节  SHA256 前16 0F9125A2EB391C3A          ← 与基线逐字节一致
```

> 顺带记一条**教训**：这个脚本的第一版写入被沙箱拒绝，却仍然打印
> "updated 2 profile file(s)" 并 exit 0 —— 又是"失败报成功"。
> 已修：每次写入包 try/catch、**写完再读回来确认块真的在**，任何失败都
> `FAILED` + `exit 1`。复核者在这个项目里抓过同类 bug 两次，这是第三次，
> 所以规则是：**任何"装好了"的宣告后面都必须跟一次读回验证。**

**这个方案对未来的 kit 意味着什么**：一键配置脚本除了写 `.vscode\*` 与 `.clangd`，
还要**询问用户是否允许**加这段 UTF-8 块（因为那是他的个人环境），
并同时提供 `-Undo`。程序里仍建议调用 `启用中文控制台()` —— 那管的是
双击 exe、把程序拷给别人等终端设置覆盖不到的场景。

## 五、安装 / 卸载 / 自测 三个脚本的设计

### `install.ps1`
1. 从 `$PSScriptRoot\..` 推出工具链根；校验 `bin\chinese++.exe`、`bin\clangd.exe`、
   `lib\clang\<版本>\include` 都在
2. 取目标项目文件夹：**拖放到 .cmd 上**（`%*` 传进来）或双击后提示输入
3. **只写** `<项目>\.vscode\` 和 `<项目>\.clangd`；**绝不碰 VS Code 全局设置**
4. 要覆盖的已有文件先备份成 `<名>.bak-<时间戳>`
5. 把模板里的 `@@CXX@@` / `@@CLANGD@@` 占位符换成实际绝对路径（用正斜杠），写入
6. 写一份清单 `<项目>\.vscode\chinese-cpp-kit.json`，记录"创建了哪些、备份了哪些" —— **卸载就靠它**
7. 跑 `verify.ps1` 自测，把结论打印给用户
8. 提示：回 VS Code 执行 `Developer: Reload Window`

### `uninstall.ps1`
按清单：把 `.bak-*` 移回原位（还原用户原来的配置）→ 删掉我们创建且用户原本没有的文件 →
删掉清单 → `.vscode` 若空了就一并删掉。

### `verify.ps1`（这一步是整套设计里最值钱的部分）
**不用打开 VS Code 就能证明三件事**，直接调我们的 clangd：

```powershell
& $Clangd "--check=$file" "--query-driver=$Cxx"
```

在临时目录里放一份和用户收到的**同样的 `.clangd`**，然后：

| 输入 | 期望 | 证明了什么 |
|---|---|---|
| 合法的中文示例 | 输出 `All checks completed, 0 errors` | **中文关键字没被当成未知**（否则每行都红） |
| 故意写错的示例 | 报错文本等于该文件里 `// expect-zh:` 那一行 | **编辑器里的报错也是中文的** |

两条都成立才 exit 0。这样安装脚本能在装完当场告诉用户"成了"。

## 六、写这套时踩到的坑（重建时务必避开）

| 坑 | 表现 | 正确做法 |
|---|---|---|
| **`.ps1` 里出现中文字面量** | PS 5.1 把无 BOM 的文件按 GBK 读 → **解析直接失败**（我踩了：文件清单里写了 `'示例.cpp'`，7 个 parse error） | 脚本**纯 ASCII**；中文放 **UTF-8 数据文件**（`messages.txt`），**模板文件名也放数据文件**，脚本只读不写中文 |
| **用 `cmd` 拼含中文的路径** | 命令行会被按控制台代码页解释，中文路径被改坏 | 用 `& $exe @args`（**参数数组**），不经过 shell |
| **`[char]0x4F7F + [char]0x7528`** | PowerShell 把两个 char 相加当成**整数加法**，不是拼字符串 | 要拼就用 `[string][char]... + [string][char]...`，或干脆别拼 |
| **模板里用 `${...}` 当占位符** | 会和 VS Code 自己的变量（`${file}`、`${workspaceFolder}`）冲突 | 占位符用**独特记号**，如 `@@CXX@@`；替换时只动这些记号 |
| **`.cmd` 注释里写中文文件名** | 同样是非 ASCII 字节（我踩了 6 个） | `.cmd` 内容也纯 ASCII，中文名只用在**文件名**上 |
| **忘了 `chcp 65001`** | 脚本输出的中文在 cmd 窗口里乱码 | `.cmd` 第一行 `chcp 65001 >nul` |
| **动用户全局设置** | 用户其他项目被改，且难还原 | 只用**工作区**配置；要动全局必须单独开关 + 备份 |

> 这些都是**已经在别的脚本上踩过**的同一类问题（项目里 `make_patch.ps1`、
> `rebuild_clang.ps1` 的头部注释都专门写过"为什么这个文件是纯 ASCII"）。
> 重建时把它们当硬约束，别再试一次。

## 七、重建 Checklist

- [ ] `templates\` 六件套（内容见本文第四节 + 仓库现有的 `.vscode\*.json` / `.clangd` 可作底本）
- [ ] `messages.txt`（中文文案）与 `joblist.txt`（模板文件名 → 目标文件名，含中文名）
- [ ] `install.ps1` / `uninstall.ps1` / `verify.ps1`，**纯 ASCII 自检通过**
- [ ] `安装到VS Code.cmd` / `卸载.cmd`（内容 ASCII，文件名可中文，带 `chcp 65001`）
- [ ] 实测三连：装到临时文件夹 → 看生成的文件 → `verify.ps1` 通过 → 卸载后**与原状逐字节一致**
- [ ] 只有第 5 步全过，才算做完（本项目对"门禁"的要求：**它必须能失败**）
