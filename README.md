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
