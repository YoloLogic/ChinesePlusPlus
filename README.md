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
