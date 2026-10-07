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

def esc(s):
    """Escape a pipe so it cannot break out of a markdown table cell.

    GFM resolves table structure BEFORE inline spans, so a raw '|' splits the
    cell even when it sits inside backticks. The documented escape is '\\|',
    which renders as a literal pipe. This is not hypothetical: the operator
    table has rows whose ENTIRE symbol is '|', '||' and '|=', and those rows
    were silently corrupting that table (found 2026-09-26).
    """
    return str(s).replace("|", "\\|")

rows = sorted(plain + virt, key=lambda x: x[0])
cols = 4
cell = "| `%s` | `%s` "
w("| 中文 | 英文 " * 0 + "|" + " 中文 | 英文 |" * (cols // 2))
w("|" + "---|" * cols)
per = (len(rows) + cols // 2 - 1) // (cols // 2)
for i in range(per):
    line = "|"
    for c in range(cols // 2):
        j = i + c * per
        if j < len(rows):
            en, zh = rows[j]
            line += " `%s` | `%s` |" % (esc(zh), esc(en))
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
    w("| `%s` | `%s` | `%s` |" % (esc(zh), esc(en), esc(sym)))
w("")
w("这些和 C++ 原本的 `and` / `or` / `not` 是同一类东西（运算符的替代拼写）。")
w("")
w("## 三、预处理指令（%d 条）" % len(directives))
w("")
w("| 中文 | 英文 |")
w("|---|---|")
for en, zh in sorted(directives):
    w("| `#%s` | `#%s` |" % (esc(zh), esc(en)))
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
w("中文覆盖**语言本身**；标准库另有一层**中文版**（复制层 + 派生层）。下面这些**英文必须照旧可用**（生态兼容），但多数**已经不是唯一写法**：")
w("")
w("| 东西 | 例子 | 为什么 |")
w("|---|---|---|")
w("| 标准库的名字与成员函数 | `std::vector`、`v.push_back(1)` | **英文照旧可用**；**中文也有一套**：`标准::向量<整数>`、`表.尾插(1)`（复制层汉化 + 派生层补回英文，微软原头不改 —— 见 `docs\\标准库汉化\\`） |")
w("| 库的头文件名 | `#include <vector>` | 文件是微软 STL 的文件；**指令名**可以中文（`#包含 <vector>`），**中文头名也有**：`#包含 <向量>`（已覆盖全部标准头，明细见 `docs\\标准库汉化\\头文件覆盖台账.md`） |")
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
w("    std::vector<商品> 货物;           // 库名英文照旧可用（汉语标准库另有中文名：标准::向量<整数>）")
w("    货物.push_back(商品(\"苹果\", 3.5));  // 成员名同理，英文照旧可用")
w("    std::printf(\"%.1f\\n\", 货物[0].单价());")
w("    返回 0;")
w("}")
w("```")
w("")

# ---------------------------------------------------------------------------
# Guard: every table emitted here must have a delimiter row whose cell count
# matches its header row (and every body row).
#
# Why this check exists -- the bug it would have caught:
#   the keyword table's delimiter was built as  "|---|---|" * (cols // 2).
#   "|---|---|" is TWO cells but THREE pipes, so repeating it produced
#   "|---|---||---|---|" = FIVE cells for a FOUR-column header. GFM then
#   refuses to parse the table and the reader sees a wall of pipes -- and
#   NOTHING reports an error: not Python, not the compiler, not the editor.
#   Section one of 中文对照表.md shipped like that (reported 2026-09-26).
# ---------------------------------------------------------------------------
def _cells(line):
    """Split a table row into cells, treating '\\|' as content, not a separator.

    A plain s.split('|') is wrong here: it would also split on the escaped
    pipes that esc() writes, making correctly-escaped rows look malformed.
    """
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    cells = []
    cur = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            cur.append(s[i:i + 2])
            i += 2
            continue
        if c == "|":
            cells.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    cells.append("".join(cur))
    return cells

def _is_delimiter(raw):
    """True if this line is a table's delimiter row.

    Deliberately permissive: it only requires the line to consist of '|', '-',
    ':' and spaces. Empty cells are ALLOWED on purpose. The malformed delimiter
    that caused the reported bug -- "|---|---||---|---|", i.e. 5 cells for a
    4-column header -- contains one empty cell. A stricter test that rejected
    empty cells classified that line as "not a delimiter row", skipped the whole
    table, and MISSED the very bug this guard exists to catch. The mutation test
    found that hole; the cell-count comparison is what reports the problem.
    """
    t = raw.strip()
    return bool(t) and t.startswith("|") and "-" in t and not (set(t) - set("|-: "))

def check_tables(lines):
    problems = []
    ntables = 0
    i = 0
    while i < len(lines):
        if lines[i].startswith("|") and i + 1 < len(lines) and lines[i + 1].startswith("|"):
            delim = _cells(lines[i + 1])
            if _is_delimiter(lines[i + 1]):
                ntables += 1
                head = _cells(lines[i])
                if len(head) != len(delim):
                    problems.append((i + 1, len(head), len(delim), lines[i + 1]))
                j = i + 2
                while j < len(lines) and lines[j].startswith("|"):
                    got = len(_cells(lines[j]))
                    if got != len(head):
                        problems.append((j + 1, len(head), got, lines[j]))
                    j += 1
                i = j
                continue
        i += 1
    return problems, ntables

bad, ntables = check_tables(out)
if bad:
    for ln, want, got, text in bad:
        print("表格列数不一致：第 %d 行，表头 %d 列、该行 %d 列" % (ln, want, got))
        print("    " + text)
    raise SystemExit("refusing to write a table that GFM will not parse")
print("表格自检通过：%d 张表列数一致" % ntables)

text = "\n".join(out)

# ---------------------------------------------------------------------------
# --check：只核对盘上的文件是否与本脚本【此刻会生成的内容】一致，不写盘。
#
# 为什么需要它（2026-10-07 实测发现的真事故）：
#   本文件是【生成物】，但在此之前没有任何自动步骤重跑或核对它 ——
#   全仓 ps1 里没有一处调用本脚本，它只在注释与文档里被提到。
#   于是发生了这件事：有人手改了 packaging\中文对照表.md
#   （把「标准库我们没有改名」更新为「已有中文版：标准::向量<整数>」），
#   却没改生成器；此后只要有人跑一次本脚本，就会把【正确内容改回陈旧的错误说法】。
#   实测证据：重跑后 SHA256 由 F4483911… 变为 21C86429…，diff 正是第五节的措辞。
#
#   本脚本原先只有「表格列数自检」，那只管排版，管不到【措辞与事实】。
#   接进闸门后，「生成器与生成物不一致」当场就会被抓出来。
# ---------------------------------------------------------------------------
if "--check" in sys.argv:
    if not os.path.exists(OUT):
        raise SystemExit("缺少 %s，请先运行 python tools\\make_cheatsheet.py" % OUT)
    current = io.open(OUT, encoding="utf-8").read()
    if current != text:
        raise SystemExit(
            "对照表与生成器不一致：%s\n"
            "  盘上 %d 行，本脚本会生成 %d 行。\n"
            "  请运行 python tools\\make_cheatsheet.py 并提交其结果；\n"
            "  若你手改过该文件，请把改动搬进 tools\\make_cheatsheet.py（它才是生成器）。"
            % (OUT, current.count("\n") + 1, len(out))
        )
    print("对照表与生成器一致（%d 行）：%s" % (len(out), OUT))
    raise SystemExit(0)

io.open(OUT, "w", encoding="utf-8").write(text)
print("写入 %s（%d 行）" % (OUT, len(out)))
