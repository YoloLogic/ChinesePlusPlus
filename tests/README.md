# 测试目录

按**测试模块**分类，一个目录一类。每个目录都能自己跑。

| 目录 | 测什么 | 怎么跑 |
|---|---|---|
| `01-keywords/` | 基础中文关键字 + 中文标识符 + 中文类型定义 | 自动：编译并运行 |
| `02-virt-specifiers/` | `重写` / `最终`（上下文关键字，与英文**并存**） | 自动：编译并运行 |
| `03-operators/` | 11 个运算符替代拼写（并且 或者 并非 …） | 自动：编译并运行 |
| `04-modules/` | **C++20 模块端到端**：中文模块名 + `导出 模块` + `导入` | `build.ps1`（四步） |
| `05-console/` | 控制台 UTF-8：打印调用前后的代码页 | 自动：编译并运行 |
| `06-parity/` | **无锁定**：转成英文后用 stock clang 编，输出须逐字节相同 | `check.ps1` |
| `07-negative/` | 负面：旧译名 `动态绑定` 必须**编译失败**（改名生效） | `check.ps1`（断言失败） |

统一入口：`run_all.ps1`。

```
powershell -File E:\Chinese++\tests\run_all.ps1
```

## 调度约定

`run_all.ps1` 只做**目录发现**，不硬编码任何源文件名：

| 目录里有 | 怎么处理 |
|---|---|
| `build.ps1` | 跑它（多步骤，如 04-modules 的四步编译链接） |
| `check.ps1` | 跑它（需要比对或断言失败，如 06/07） |
| 都没有 | 把目录里每个 `*.cpp` 用 `chinese++.exe` 编译并运行，退出码非 0 即失败 |

所以**你往 `tests/` 下丢一个新目录（比如 `demo/`），它会被自动收进来**，不用改脚本。

## 子脚本用哪个 PowerShell：优先 7，回退 5.1（2026-09-24）

三个会**再拉起子进程**的脚本 —— `tests\run_all.ps1`、`tools\acceptance.ps1`、
`tests\checks\verify_make_patch_gate.ps1` —— 都是同一段选择逻辑：

```powershell
$psExe = 'powershell'
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) {
    & $pwshCmd.Source -NoProfile -Command 'exit 0' 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $psExe = $pwshCmd.Source }
}
Write-Host ("  child shells: " + $psExe)
```

- **优先 PowerShell 7（`pwsh`）**，没有就回退 Windows 自带的 5.1 —— 所以**开箱即用没有丢**。
- **为什么要真跑一下**：在 PATH 上不等于能用。Store 装出来的 `pwsh.exe` 是一个
  **应用执行别名**（app-execution alias），在某些上下文里会起不来，所以先起一次看退出码。
- **为什么把那行打出来**：**不可观测的回退等于没测过**。两条路都要能证明自己走通了。

> ⚠️ 改这三个脚本时注意两条已经踩过的坑：
> **① 必须保持纯 ASCII** —— PowerShell 5.1 按 GBK 读无 BOM 文件，中文注释会变乱码并顶崩解析器。
> **② 行尾的 `|` 当续行是 PowerShell 7 才有的**，5.1 会报 `Unexpected token ')'`。
> **③ 重定向要经 cmd，不要经 PowerShell 管道**。`& $exe > file` 是**跟 shell 有关**的：
> 5.1 把文本推过 `Out-File`，落成 UTF-16LE 带 BOM（`06-parity` 那句输出是 **68** 字节）；
> 7 直接写程序原始字节（**45** 字节）。**字节数是证据，就不能让"谁在驱动测试"决定它。**
> `06-parity` 已改成 `cmd /c "... > file"`（和 `rebuild_clang.ps1` 对 MSBuild 用的是同一条教训），
> 现在两条路都是 45。
>
> 两条路都实测过（2026-09-24，PowerShell 7.6.6）：
>
> | | child shells | run_all | acceptance |
> |---|---|---|---|
> | 路径 A：pwsh 在场 | `...\WindowsApps\pwsh.exe` | passed 19 / 0 | passed 17 / 0 |
> | 路径 B：把 pwsh 从 PATH 拿掉 | `powershell` | passed 19 / 0 | passed 17 / 0 |

## 实测结果（2026-09-22）

`run_all.ps1` 一次跑完：**7 PASS / 0 FAIL**。其中最有价值的两条：

- `04-modules`：中文模块名 `数学`、`导出 模块 数学;`、`导入 数学;` 四步全通，
  运行输出 `加倍(21) = 42` / `圆周率 = 3.1416` / `圆面积(2) = 12.5664`。
- `06-parity`：中文源码经 `zh_to_en.py` 转换（99 条表、替换 17 处）后，用
  **stock clang 19.1.5**（不是我们的 fork）编译运行，输出与中文版**逐字节相同**
  （68 字节对 68 字节）。

## 为什么目录名和脚本名用英文，源码内容用中文

不是崇洋，是踩出来的：

- `.ps1` 脚本里的**中文**在 PowerShell 5.1 下很危险 —— 文件没有 UTF-8 BOM 时它按
  GBK 解码，中文只要落在**语法位置**（哈希表键名、字符串字面量、**含中文的路径**、
  甚至**注释里举例的汉字**）就可能解析失败。而几乎每次编辑保存都会把 BOM 抹掉，
  实测已经失败过三次。
- 所以约定：**脚本与路径一律 ASCII，中文放在源码内容与注释里**。
  源码用中文毫无问题（编译器按 UTF-8 读），那才是本项目的主体。
- 脚本一律跑了纯 ASCII 自检（`非 ASCII 字节数 == 0`）。

## 两个踩出来的坑（写在这里免得重犯）

**一、`-x c++-module` 不能省。** 编模块接口单元时不加它，clang **退出码 0**，
但写出的是**预处理后的文本**（文件以 `# 1 ` 开头）而不是模块 BMI，
下一步就会报 `file doesn't start with precompiled file magic`。
退码 0 而产物是错的，这种静默失败最难查。

**二、编接口单元时不要带自己的 BMI。** 第 2 步（把接口编成 .obj）如果也加
`-fmodule-file=<自己的 pcm>`，clang 会把它当成"又从 BMI 里被 include 了一次"，
报一连串 `redefinition of module '数学'` / `redefinition of '加倍'`。
BMI 只有**导入方**才需要。

## 其它约定

- 要打印中文的程序都 `#include "../../examples/中文控制台.h"` 并调用
  `启用中文控制台()`；否则在 GBK(936) 控制台下会乱码（病根见 `..\docs\使用说明.md` §四）。
- 编译产物统一落在各目录的 `out\` 子目录，不污染源码目录。

## 这个目录是怎么来的

2026-09-22 那轮改动（`virtual`→`虚拟`、新增 `重写`/`最终`、11 个运算符替代拼写、
打通 `模块`/`导入`）的验证原本散在 `examples\_test_out\` 里，命名是
`m1.cpp` / `i3.cpp` / `mod_ident.cpp` 这种，看不出测什么。这里按模块重新归类，
只保留有必要长期留着的用例；那堆散文件已删除。

---

## 修订（分类补齐）

上面那张表写的时候只有 7 类，后来又加了两个，一并补上：

| 目录 | 测什么 | 怎么跑 |
|---|---|---|
| `08-regression/` | 英文回归：中文改动不得破坏英文 C++；中英转译对照 | `check.ps1`（全部须编译通过） |
| `09-diagnostics/` | 中文关键字必须出现在诊断里 + 词法粘连陷阱 + 中英混写 | `check.ps1`（成败断言 + 字节级比对） |
| `demo/` | 随手放的中文程序（**新目录会被自动收进来**） | 自动 |

## 修订三（预处理指令汉化）

| 目录 | 测什么 | 怎么跑 |
|---|---|---|
| `13-preprocessor/` | **预处理指令中文拼写**：22 条逐条与英文对拍（行为 + 诊断必须一致）、中英混用、全中文 vs 全英文 `-E -P` **逐字节相同**、指令名当普通标识符仍可用、拼错的拼写仍被拒、`-E -dI` 原样回显用户写的拼写 | `check.ps1`（7 项）＋ `sweep.py`（22 条 + 嵌套） |

### 当前实测结果（2026-09-24）

`run_all.ps1` 一次跑完：**20 PASS / 0 FAIL**。

```
15 个测试目录（01～13 ＋ checks ＋ demo）＋ checks 里 5 个检查脚本 = 20 项全绿
（run_all 会先把每个目录当一项跑，checks 目录自身没有 build/check 也没有 .cpp，
  按约定算 0；随后再单独跑它下面的 5 个脚本，所以 checks 被计两次是脚本本来的行为）
最值得记的几条：
  06-parity    中英输出逐字节相同（45 B 对 45 B），用的是 stock clang 19.1.5
  10-multi-tu  7 个多翻译单元用例全过，含「MSVC 编译 main + 中文关键字 clang 编译实现」
  12-diagnostics  7344 条中文诊断、78 个用例逐条断言通过；回退路径已无条可观测
                  （凡有英文正文的诊断都已进表，保证改由 --check-table 的表级断言承担）
                   由「默认日志与 -fno-chinese-diagnostics 日志逐字节相同」证明
  13-preprocessor 22 条中文指令与英文逐条对拍一致；全中文 vs 全英文 -E -P 逐字节相同
                  （150 B 对 150 B）
  checks       verify_zh_diagnostics.py 同时跑校核器自检（故意写坏占位符必须报错）
  checks       verify_make_patch_gate.ps1 跑补丁门禁自检（**破坏的补丁必须被拒绝**）
  checks       verify_chinese_keywords.py 第 11 节校核指令表（7 项，每条自带自测）
```

### 修订二（再补三个）

| 目录 | 测什么 | 怎么跑 |
|---|---|---|
| `10-multi-tu/` | 多翻译单元：声明/定义跨 TU、中英混链、`inline`/`static`/模板/Odr | `build.ps1`（7 个用例，逐条编译链接运行） |
| `11-cxx20/` | C++20：中文 `概念` / `要求` / 模板与英文写法等价 | 自动 |
| `12-diagnostics/` | **诊断正文中文化**：逐条断言真的出中文、英文正文真的消失、前缀与 `[-Wxxx]` 没动、查不到的回退英文、`-fno-chinese-diagnostics` 能切回英文 | `check.ps1`（字节级断言） |

### 当前实测结果（2026-09-22 22:xx）

`run_all.ps1` 一次跑完：**19 PASS / 0 FAIL**。

```
13 个测试目录（01～12 + demo）+ checks 目录 + 5 个检查脚本 = 19 项全绿
最值得记的几条：
  06-parity    中英输出逐字节相同（45 B 对 45 B），用的是 stock clang 19.1.5
  10-multi-tu  7 个多翻译单元用例全过，含「MSVC 编译 main + 中文关键字 clang 编译实现」
  12-diagnostics  7344 条中文诊断、78 个用例逐条断言通过；回退路径已无条可观测
                 （凡有英文正文的诊断都已进表，保证改由 --check-table 的表级断言承担）
                  由「默认日志与 -fno-chinese-diagnostics 日志逐字节相同」证明
  checks       verify_zh_diagnostics.py 同时跑校核器自检（故意写坏占位符必须报错）
  checks       verify_make_patch_gate.ps1 跑补丁门禁自检（**破坏的补丁必须被拒绝**）
```

> `verify_make_patch_gate.ps1` 是补出来的：补丁门禁原本是**橡皮图章**
> —— 坏补丁也报"all patches verified"且退出码 0。一个永远返回
> "通过"的检查等于没有检查，所以每个门禁现在都要有"证明自己会失败"的自测。
> 详见 `..\docs\诊断汉化\诊断汉化清单.md` 第十一节（独立复核）。

### `12-diagnostics/` 的用例分六批

`01`～`11` 是第一批（12 条）：初学者第一次写错就会撞到的句子。
`12`～`26` 是第二批（20 条）：按 `tools\diag_frequency.py` 量出的**真实频次**选的
（400 个真实文件；当时工具报 2820 条实例，修正漏计后同语料为 3890 条、全部 4980 条）。
`27`～`42` 是第三批（16 条）：A/B/C 三组，含 `%select`、模板 note、未使用警告一族。
`43`～`54` 是 C1（17 条，其中 `ext_member_redeclared` 与 `err_member_redeclared` 同文、
共用 `53`，故 12 个文件）：按 `tools\diag_coverage.py` 的实测补「兄弟条目」——
主句翻了、`_suggest` 变体或同文 ID 没翻的那些。
`55`～`68` 是 C2a（16 条，14 个文件）：按实测排名补的高频条目，含三个
`*_redeclared` 兄弟、OpenCL blocks、没有包含守卫的头、常量求值调用栈等。
`69`～`70` 是渲染器手工正文（宏回溯、包含栈）。
`71`～`76` 是 C4（9 条，6 个文件）：按**真实开源项目**的排名补的，主要是弃用
（MSVC CRT）一族与 availability note —— 这一批把真实项目覆盖率推到 99.3%。

## `12-diagnostics/` 的写法约定
期望值写在**每个 `.cpp` 的头部注释**里，脚本从注释里读：

```c
// expect: 未使用的变量（变量名） '甲'     编译器输出里必须出现
// forbid: unused variable       编译器输出里必须【不】出现
```

这样每个用例自解释，`check.ps1` 保持纯 ASCII（按字节比对，
用 `cmd /c ... > log 2>&1` 保留原始 UTF-8 字节）。
加一个新的中文诊断条目时，**同时**加一个这样的 `.cpp`。

## 本目录的边界

`tests\` **只放 C++ 程序用例**。项目里另有一处与测试相关，职责不同：

- `tests\checks\verify_*.py` / `verify_*.ps1` —— 静态检查、端到端检查、
  中文诊断表结构校核、clangd 检查
  （需要 Python 或已构建的 clang，不属于「编译一个 .cpp 看输出」这一类）

即「一个入口跑程序用例（`run_all.ps1` 会自动带跑 `checks\`）+ 一组脚本跑检查」。
---

## 搬移 / 重命名测试文件时的两条硬规矩（都踩过）

**1. 检查 include。** 源文件里凡是 `#include "../../examples/..."` 这种**指向目录外**
的相对路径，换目录后立刻失效。搬完必须逐个改，并且**用编译器验证**，不能只看文件名。

实测踩过：`我的测试.cpp` 从 `experiments\` 搬到 `tests\demo\` 后，里面写的
`#include "../examples/zhstd.h"` 变成了 `tests\examples\zhstd.h`（不存在）——
于是 `zhstd.h` 里定义的 `概念` / `可相加` / `标准` / `数列` 全部报「未声明」，
看起来像语言坏了，其实是路径少了退一级。查漏命令：

```powershell
Get-ChildItem E:\Chinese++\tests -Recurse -Include *.cpp,*.h |
  Select-String '#include\s+"\.\.'
```

**2. 检查引用它的脚本与文档。** 改了文件名，引用方要同步。实测踩过：
`verify_build.py` 按旧名找 `test_chinese.cpp` 等 5 个文件、
`verify_clangd.ps1` 指向 `tests\zh_keywords_min.cpp`，以及 `..\docs\使用说明.md` 里
6 处 `tools\verify_*` 路径——都因为归类改名而失效，已一并修好。

> 一句话：**搬文件是改接口**，不是单纯的移动。