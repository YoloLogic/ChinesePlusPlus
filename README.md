# 中文编程（Chinese++）

中文关键字是 Clang/LLVM 的**第一公民**，英文照旧可用。
不是创新的汉语编程，却是最强的汉语编程。

编译器：`build\Release\bin\chinese++.exe`

**发行包**：Chinese++ **0.2**（win64）—— `dist\Chinese++-0.2-win64.zip`（80.8 MB；**线上 v0.2 资产**是 §18.48 批1 之前的包，仓库现在打出的已含"地基"，见下）→ 解压 → 双击 `一键安装.cmd`

**汉语标准库**：`zhstdlib\` 已覆盖 **103 / 103 个标准头**（产物 **119** 个）—— `#包含 <向量>` 直接可用，`标准::向量<整数>`、中文成员名都有，英文原名照旧可用。总判据 `tools\regen_zhstdlib.ps1`（**20 道守卫**，含 `pugixml/cJSON/lz4/fmt` 四个真实开源项目的 ours-vs-原生对照）每次提交都跑；账本见 `docs\标准库汉化\`。

**C 运行库 / 系统 API**：也是「加名字，不改原件」（符号仍在微软 DLL / UCRT 里）。**2026-10-07 全量盘点**：C 线头数 **26**（`zhstdlib\C运行库\` 25 个包装头 ＋ `标准库\错误号`），已起 **C 线中文名 310**（类型 57 ／ 函数 247 ／ 值宏 6）；按逻辑口径（整族重载合并成一个中文名）参考全集 364 ⇒ **C 线逻辑缺口 54**。**五批已销账**：§18.59 `C宽字符`（cwchar）60 → **1**、§18.60 `C数学`（cmath）56 → **12**、§18.62 `C标准库`（cstdlib）29 → **0**、§18.63 `C标准整数`（cstdint）16 → **0**、§18.64 `C宽字符类别`（cwctype）16 → **0** —— 只剩 `_MbStatet`，它与 `mbstate_t` 是**同一个类型**（MSVC 内部拼写）⇒ 只起一个中文名，登记为边界。逐头明细、缺口清单、硬边界（宏 / `va_*` / `setjmp` / C-only 头）与复算命令见 [`docs\标准库汉化\C库汉化台账.md`](docs/标准库汉化/C库汉化台账.md)（自动生成，第 29 道守卫看住）。

```cpp
#包含 <输入输出流>

整数 主函数() {
  标准::标准输出流 << "你好，世界" << 标准::行尾流冲刷;
  返回 0;
}
```

## 第四条产品线：ChineseTypeScript（网页那一角）

三角定位「最快的（C++）/ 最全面的（Python）/ 最适合浏览器页面的（JS 或 TS 魔改）」
里的**网页那一角** —— 把 Go 版 TypeScript（也就是今天 `tsc` 的本体）汉化：
汉语关键字与英文落成**同一个 token**；`.chts` 源文件编译产出的 js
**仍是标准英文关键字**，能被 node 直接运行；英文 `.ts` 的产物与上游**逐字节一致**。

* 工作副本：`E:\ChineseTypeScript`（底本 `microsoft/typescript-go`，Apache-2.0）
* 文件扩展名 `.chts`（`.cts` 已被上游占为 CommonJS 版 TS）
* 说明与证据：[`docs\ChineseTypeScript\ChineseTypeScript-说明.md`](docs/ChineseTypeScript/ChineseTypeScript-说明.md)

## 文档都在 `docs\`

**从 [`docs\README.md`](docs/README.md) 进** —— 那里有文档地图与阅读顺序。

**想学怎么写**（从零开始，不是查手册）：[`教程\Chinese++-教学教程.md`](教程/Chinese++-教学教程.md)
—— 10 课，每课都有**能直接编译运行**的例子与真实输出；附录 B 是完整关键字总表。
另有 **Word 版** [`教程\Chinese++-教学教程.docx`](教程/Chinese++-教学教程.docx)，适合打印或发给学生。

只想快速上手： [`docs\使用说明.md`](docs/使用说明.md)

## 一条命令验收

```powershell
powershell -File E:\Chinese++\tools\acceptance.ps1
```

**19** 条断言，每条都打印它自己产出的证据（约 8 分钟）。给复核者用。
`tests\run_all.ps1` 另有一套（最近一次实测 `passed: 22    failed: 0`）。

## 发给别人用（发行包已经产出）

```powershell
powershell -File E:\Chinese++\tools\make_package.ps1
```

产出 `dist\Chinese++-0.2-win64\`（未压缩 **270 MB** / **2700+** 个文件——含 §18.48 起随包的**整套地基**：`lib\stl\` 开源 MSVC STL 头、`lib\mingw\` 2037 个 mingw-w64 头（public domain）、`lib\compiler\` 11 个**手搓**的编译器支撑头、`bin\` 10 个 VC++ 运行库 DLL）与同名 `.zip`（**92 MB**）。
对方解压后双击 `一键安装.cmd`：自动建 9 个别名、**只给会话级 PATH**、
检测 VS Build Tools、按需下载便携 VS Code（中文界面 ＋ 能认中文关键字的 clangd）、
跑包内自测 `verify.ps1`（**26 项**）。另外三个：

| 脚本 | 干什么 |
|---|---|
| `一键为工作区配置.cmd` | 把 `.vscode` 配到**你自己打开的**工作区（不用把工作区搬进包里） |
| `一键装配到我的VSCode.cmd` | 用**你已有的** VS Code（扩展装进便携 `data\`，不动 `%APPDATA%\Code`） |
| `一键还原我的VSCode.cmd` | 完全还原上面那一步（没装配过就什么都不做） |

**如实记一条没验证的**：发行包**尚未在没有构建树的机器上**试过 —— 本机始终有构建树。
包内 `verify.ps1` 不引用构建树，所以它测的东西可信；但换机器这件事还没测。

## 回滚：这是个 git 仓库

改坏了能退回来。**已验证**（误改、误删都能还原到同一字节）：

```powershell
cd E:\Chinese++
git status                  # 看改了什么
git diff                    # 看具体差别
git checkout -- <文件>       # 单个文件退回上次提交
git checkout -- .           # 全部退回
git log --oneline           # 历史
```

**跟踪什么**（176 个文件，约 2 MB）：`docs\`、`tools\`、`tests\`、`patches\`、
各种示例、配置文件 —— 也就是**我们自己写的全部东西**。

**故意不跟踪什么**（理由写在 `.gitignore` 里）：

| 不跟踪 | 为什么 | 它的回滚靠什么 |
|---|---|---|
| `LLVM-main\`（18 万文件 / 2.09 GB） | 太大；且已有更可靠的路径 | `E:\LLVM-main` 干净上游树（原件）+ `patches\*.patch`（我们的改动） |
| `build\`、`zhcpp-demo\build\` | 构建产物，可重编（主树一棵 4.4 GB） | `tools\rebuild_clang.ps1` |
| `third_party\{src,build}\` | 第三方克隆，可重新下载 | `third_party\README.md` 里记着来源与 commit |
| `.idea\`、`*.pdb`、`*.exe`、`*.lib` 等 | IDE 本地配置 / 编译产物 | 不需要 |

> ⚠️ `.gitattributes` 里写了 `* -text`，**禁止 git 做行尾转换**。
> 这不是洁癖：本项目的多处验收是**逐字节比较**（`tests\12-diagnostics` 的
> expect/forbid 标记、`make_patch.ps1` 的 SHA256 硬链接检查），
> 一旦 git 悄悄把 LF 换成 CRLF，这些验收就会莫名其妙地开始失败。

## ⚠️ 建这个仓库曾经弄坏过一个门禁（已修，但必须知道）

**症状**：`tools\acceptance.ps1` 第 7 条自检失败 —— "the verification gate does not
distinguish good from broken"，连**好补丁都被判 False**。

**原因**：`tools\make_patch.ps1` 的校验流程是——把上游原件拷进一个**普通目录**
（`build\_patchgen\*.verify`），在那儿跑 `git apply`，再逐文件比对哈希。
这个目录**故意不是** git 仓库，靠的就是"在仓库外"这个语境。
`E:\Chinese++` 变成仓库之后，`git apply` 会**向上找到** `E:\Chinese++\.git`
（实测 `git rev-parse --show-toplevel` 从里面返回 `E:/Chinese++`），
于是它**静默空转**：退出码 0，却一个字节都没写。

**修法**：`make_patch.ps1` 里那次 `git apply` 加了
`set "GIT_CEILING_DIRECTORIES=<_patchgen>"`，把向上查找挡在 `_patchgen` 之前，
恢复"仓库外"的语义（`$repo` 自己有 `.git`，不受影响）。

**怎么定位的**：A/B 对照 —— 把 `.gitattributes` 移走**仍然失败**，把 `.git` 移走**立刻通过**。

> **教训**：**新增一个全局性的东西（这里是仓库）会改变已有工具的行为。**
> 这次是**验收套件自己抓到的** —— 这正是"每条门禁都必须能失败"那条规矩的价值：
> 如果 `make_patch.ps1` 的校验是个橡皮图章（它曾经就是），
> 这个静默失效会一路蒙混过关。
