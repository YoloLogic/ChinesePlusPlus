# -*- coding: utf-8 -*-
"""从编译器的两张表生成《中文对照表》，放进发行包。

为什么是【生成】而不是手写
--------------------------
手写的对照表一定会和编译器漂移 —— 本项目已经栽过多次「两份副本各说各话」。
所以这里只认两个数据源，它们是编译器真正在用的那两张表：

    clang\\include\\clang\\Basic\\ChineseKeywords.def     关键字 99 个
    clang\\include\\clang\\Basic\\ChineseDirectives.def   预处理指令 22 条

改表之后重跑本脚本，包里的对照表就跟着变。

用法：
    python tools\\make_cheatsheet.py
输出：
    packaging\\中文对照表.md
"""

import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASIC = os.path.join(ROOT, "LLVM-main", "clang", "include", "clang", "Basic")
KW_DEF = os.path.join(BASIC, "ChineseKeywords.def")
DIR_DEF = os.path.join(BASIC, "ChineseDirectives.def")
OUT = os.path.join(ROOT, "packaging", "中文对照表.md")

kw_src = io.open(KW_DEF, encoding="utf-8").read()
dir_src = io.open(DIR_DEF, encoding="utf-8").read()

plain, virt, oper = [], [], []
for line in kw_src.splitlines():
    m = re.match(r"\s*ZH_KEYWORD\(\s*(\w+)\s*,\s*([^,]+?)\s*,", line)
    if m:
        plain.append((m.group(1), m.group(2)))
        continue
    m = re.match(r"\s*ZH_VIRT_SPECIFIER\(\s*(\w+)\s*,\s*([^)]+?)\s*\)", line)
    if m:
        virt.append((m.group(1), m.group(2)))
        continue
    m = re.match(r"\s*ZH_OPERATOR_KEYWORD\(\s*([^,]+?)\s*,\s*([^)]+?)\s*\)"
                 r"\s*//[^=]*=\s*(\w+)\s*=\s*(\S+)", line)
    if m:
        oper.append((m.group(3), m.group(4), m.group(1)))

directives = []
for line in dir_src.splitlines():
    m = re.match(r"\s*ZH_DIRECTIVE\(\s*(\w+)\s*,\s*([^)]+?)\s*\)\s*$", line)
    if m:
        directives.append((m.group(1), m.group(2)))

print("关键字：普通 %d ＋ 上下文 %d ＋ 运算符 %d ＝ %d"
      % (len(plain), len(virt), len(oper), len(plain) + len(virt) + len(oper)))
print("预处理指令：%d" % len(directives))

out = []
w = out.append

w("# 中文编程对照表")
w("")
w("> 本表由 `tools/make_cheatsheet.py` 从编译器**真正在用的那两张表**自动生成，")
w("> 不是手写的 —— 手写的副本一定会和编译器漂移。")
w("> 改表之后重新生成，本表跟着变。")
w("")
w("**中英两种写法都可以用，而且可以混着写。** 中文不是替换英文，是并列多出来的一种拼写。")
w("")
w("---")
w("")
w("## 一、关键字（%d 个）" % (len(plain) + len(virt)))
w("")

rows = sorted(plain + virt, key=lambda x: x[0])
cols = 4
cell = "| `%s` | `%s` "
w("| 中文 | 英文 " * 0 + "|" + " 中文 | 英文 |" * (cols // 2))
w("|---|---|" * (cols // 2))
per = (len(rows) + cols // 2 - 1) // (cols // 2)
for i in range(per):
    line = "|"
    for c in range(cols // 2):
        j = i + c * per
        if j < len(rows):
            en, zh = rows[j]
            line += " `%s` | `%s` |" % (zh, en)
        else:
            line += "  |  |"
    w(line)
w("")
w("其中 `重写`（override）与 `最终`（final）是**上下文关键字**：")
w("它们只在特定位置上被当作关键字，在别的位置仍是普通标识符。")
w("")
w("## 二、运算符替代拼写（%d 个）" % len(oper))
w("")
w("| 中文 | 英文 | 符号 |")
w("|---|---|---|")
for en, sym, zh in sorted(oper):
    w("| `%s` | `%s` | `%s` |" % (zh, en, sym))
w("")
w("这些和 C++ 原本的 `and` / `or` / `not` 是同一类东西（运算符的替代拼写）。")
w("")
w("## 三、预处理指令（%d 条）" % len(directives))
w("")
w("| 中文 | 英文 |")
w("|---|---|")
for en, zh in sorted(directives):
    w("| `#%s` | `#%s` |" % (zh, en))
w("")
w("**中英可以混用**，同一个文件、同一条 `#if` 链里混着写都行，不影响编译结果。")
w("")
w("## 四、入口点")
w("")
w("| 中文 | 英文 | 说明 |")
w("|---|---|---|")
w("| `主函数` | `main` | **同一个标识符**：写哪个都行，但不能同时写两个（那是重定义） |")
w("")
w("## 五、这些仍然必须写英文")
w("")
w("中文只覆盖**语言本身**。下面这些不属于语言，保持英文：")
w("")
w("| 东西 | 例子 | 为什么 |")
w("|---|---|---|")
w("| 标准库的名字与成员函数 | `std::vector`、`v.push_back(1)` | 标准库是微软的 MSVC STL，我们没有改名（改名会切断生态） |")
w("| 库的头文件名 | `#include <vector>` | 文件是微软 STL 的文件。**指令名**可以中文：`#包含 <vector>` |")
w("| C 运行库 / 系统 API | `printf`、`malloc` | 符号在微软的 DLL 里 |")
w("| 诊断的级别前缀 | `error:` / `warning:` / `note:` | 编辑器与 CI 靠它抓日志；**正文**是中文 |")
w("| 警告开关名 | `[-Wunused-variable]` | 构建系统靠它 |")
w("| `--help` 的输出 | —— | 尚未汉化（第一版没做） |")
w("| `#pragma` 后面的名字 | `#编译指示 once` | 那是各家编译器的自定义命名空间 |")
w("| 下划线开头的内建拼写 | `__attribute__`、`__int128` | 实现扩展，翻译了反而干扰 |")
w("")
w("## 六、一个完整例子")
w("")
w("```cpp")
w("#包含 <cstdio>          // 中文指令（等价于 #include）")
w("#include <vector>        // 英文指令，混着写也可以")
w("")
w("类型 商品 {              // 类型 = class")
w("公开:                    // 公开 = public")
w("    商品(常量 char* 名, 双精度 单价) : 名_(名), 单价_(单价) {}")
w("    双精度 单价() 常量 { 返回 单价_; }   // 返回 = return")
w("私有:")
w("    常量 char* 名_;")
w("    双精度 单价_;")
w("};")
w("")
w("整数 main() {            // 也可以写 整数 主函数()")
w("    std::vector<商品> 货物;           // 库的名字仍是英文")
w("    货物.push_back(商品(\"苹果\", 3.5));  // 库的成员名仍是英文")
w("    std::printf(\"%.1f\\n\", 货物[0].单价());")
w("    返回 0;")
w("}")
w("```")
w("")

io.open(OUT, "w", encoding="utf-8").write("\n".join(out))
print("写入 %s（%d 行）" % (OUT, len(out)))
