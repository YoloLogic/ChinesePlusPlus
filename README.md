# 中文编程（Chinese++）

中文关键字是 Clang/LLVM 的**第一公民**，英文照旧可用。
不是创新的汉语编程，却是最强的汉语编程。

编译器：`build\Release\bin\chinese++.exe`

```cpp
整数 main() {
  标准::输出 << "你好，世界" << 标准::换行;
  返回 0;
}
```

## 文档都在 `docs\`

**从 [`docs\README.md`](docs/README.md) 进** —— 那里有文档地图与阅读顺序。

只想快速上手： [`docs\使用说明.md`](docs/使用说明.md)

## 一条命令验收

```powershell
powershell -File E:\Chinese++\tools\acceptance.ps1
```

17 条断言，每条都打印它自己产出的证据（约 8 分钟）。给复核者用。

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
