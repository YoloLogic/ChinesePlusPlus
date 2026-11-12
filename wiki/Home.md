> ### 🀄 中文大战代码 · Chinese++
>
> 不是创新的汉语编程，却是最强的汉语编程。

| [🏠 首页](Home) | [🚀 快速开始](快速开始) | [📖 关键字与预处理](关键字与预处理指令) | [📦 中文标准库](中文标准库) | [🔧 排查](常见错误与排查) | [🧭 设计边界](设计边界与已知问题) |
|:---:|:---:|:---:|:---:|:---:|:---:|
<p align="center"><b>欢迎来到 Chinese++ 中文文档</b></p>

<p align="center"><sub>
本页是 <b>Chinese++</b>（汉语 C/C++ 编译器）的官方文档，与「中文大战代码」产品线同源。<br>
本项目是独立项目，与 Standard C++ Foundation / CppCon 无隶属或背书关系。
</sub></p>

---

<p align="center">
<b>不 是 创 新 的 汉 语 编 程 ， 却 是 最 强 的 汉 语 编 程</b><br>
<sub>NOT A NOVEL IDEA IN CHINESE PROGRAMMING — BUT THE STRONGEST</sub>
</p>

<p align="center">
  <a href="https://github.com/YoloLogic/CDZC/releases"><img src="https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-%E5%AE%89%E8%A3%85%E5%8C%85-C81E22?style=for-the-badge" alt="下载安装包"></a>
  <a href="https://github.com/YoloLogic/ChinesePlusPlus"><img src="https://img.shields.io/badge/%E6%BA%90%E7%A0%81-ChinesePlusPlus-1a1a1e?style=for-the-badge" alt="源码"></a>
  <a href="快速开始"><img src="https://img.shields.io/badge/%E5%85%A5%E9%97%A8-3%20%E5%88%86%E9%92%9F-2ea44f?style=for-the-badge" alt="入门"></a>
</p>

---

## 🔔 最近更新

<table>
<tr>
<td align="center" width="33%">
  <a href="https://github.com/YoloLogic/CDZC/releases">⬇️<br><b>0.1 安装包发布</b></a><br>
  <sub>编辑器 + 引擎 + 四门工具链</sub>
</td>
<td align="center" width="33%">
  <a href="中文标准库">🎮<br><b>引擎内自带 ChinesePython</b></a><br>
  <sub><code>python314.dll</code> + <code>Lib</code> 走磁盘</sub>
</td>
<td align="center" width="33%">
  <a href="Home">🏛️<br><b>文档 6 页上线</b></a><br>
  <sub>快速开始 → 关键字 → 标准库 → 排查 → 边界</sub>
</td>
</tr>
</table>

---

## 🧭 导航

### 语言

| | | | | | |
|:---:|:---:|:---:|:---:|:---:|:---:|
| <a href="关键字与预处理指令">🔤<br><b>关键字</b></a><br><sub>99 个</sub> | <a href="关键字与预处理指令">⚙️<br><b>预处理</b></a><br><sub>22 条</sub> | <a href="中文标准库">📦<br><b>标准库</b></a><br><sub>119 头</sub> | <a href="设计边界与已知问题">🩺<br><b>中文诊断</b></a><br><sub>7300+ 条</sub> | <a href="快速开始">✅<br><b>自检</b></a><br><sub>29 项</sub> | <a href="常见错误与排查">🚨<br><b>报错排查</b></a><br><sub>8 类</sub> |

### 工具

| | | | | | |
|:---:|:---:|:---:|:---:|:---:|:---:|
| <a href="快速开始">💾<br><b>安装</b></a><br><sub>两种方式</sub> | <a href="中文标准库">⚙️<br><b>cfg 机制</b></a><br><sub>免 -I</sub> | <a href="快速开始">🖥️<br><b>编辑器</b></a><br><sub>clangd</sub> | <a href="https://github.com/YoloLogic/CDZC/releases">🎮<br><b>游戏引擎</b></a><br><sub>魔改 Godot</sub> | <a href="https://github.com/YoloLogic/CDZC/releases">⬇️<br><b>下载</b></a><br><sub>Release</sub> | <a href="https://github.com/YoloLogic/ChinesePlusPlus">🏛️<br><b>源码</b></a><br><sub>GitHub</sub> |

### 文档

| | | | | | |
|:---:|:---:|:---:|:---:|:---:|:---:|
| <a href="Home">🏛️<br><b>首页</b></a> | <a href="快速开始">💾<br><b>快速开始</b></a> | <a href="关键字与预处理指令">🔤<br><b>关键字</b></a> | <a href="中文标准库">📦<br><b>标准库</b></a> | <a href="常见错误与排查">🚨<br><b>排查</b></a> | <a href="设计边界与已知问题">🧭<br><b>设计边界</b></a> |

---

## ⚡ 三十秒看它能写什么

```cpp
#包含 <C标准输入输出>
#包含 <向量>

整数 斐波那契(整数 n) {
    如果 (n <= 1) { 返回 n; }
    返回 斐波那契(n - 1) + 斐波那契(n - 2);
}

整数 主函数() {
    标准::向量<整数> 表;
    对于 (整数 i = 0; i < 10; i++) { 表.尾插(斐波那契(i)); }
    标准::格式化输出("前 10 项：%d %d %d ...\n", 表[0], 表[1], 表[2]);
    返回 0;
}
```

```text
前 10 项：0 1 1 ...
```

---

## 📌 三条最容易踩的线

> [!WARNING]
> **`main` 必须返回 `整数`**
> ```cpp
> 整数 主函数() { 返回 0; }   // ✅
> 空型 主函数() { }           // ❌ 'main' 必须返回（关键字） 整数
> ```

> [!WARNING]
> **中文关键字不能当标识符** —— `大小` 是 `sizeof`
> ```cpp
> 整数 大小() { 返回 1; }   // ❌ （关键字） 大小 不能用作标识符
> 整数 尺寸() { 返回 1; }   // ✅
> ```

> [!IMPORTANT]
> **写 C 要显式切模式**：`chinese++ -x c -std=c17 你好.c -o 你好.exe`

---

<details>
<summary><b>🗂️ 更多（产品线 / 许可 / 复核方式）</b></summary>

### 产品线

| 产品 | 说明 |
|---|---|
| [中文大战代码 · CDZC](https://github.com/YoloLogic/CDZC) | 代码编辑器 + 游戏引擎 + 四门工具链的整合发行版 |
| [Chinese++](https://github.com/YoloLogic/ChinesePlusPlus) | 汉语 C/C++ 编译器（本页） |
| [ChinesePython](https://github.com/YoloLogic/ChinesePython) | 汉语 Python |
| [ChineseJava](https://github.com/YoloLogic/ChineseJava) | 汉语 Java（只汉化关键字与诊断） |
| [ChineseTypeScript](https://github.com/YoloLogic/ChineseTypeScript) | 汉语 TypeScript |
| [LinuxChinesePlusPlus](https://github.com/YoloLogic/LinuxChinesePlusPlus) | Linux 版工具链 |

### 许可

- 原创部分：**自定义条款**（源码公开 + 禁止重新发布），见仓库 `LICENSE-SCOPE.md`；
- 不使用 C++ 官方徽标的**修改版或衍生版**；主图标自绘（红底「中」字）。

### 复核

```powershell
pwsh -File <包根>\verify.ps1        # 29 passed, 0 failed
chinese++ -x c++ -E -v -            # 应看到 5 条 zhstdlib 路径
```

</details>