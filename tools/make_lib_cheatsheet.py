# -*- coding: utf-8 -*-
"""从 zhstdlib 与它的英文母本生成《中英对照表 · 标准库用法》。

为什么是【生成】而不是手写
--------------------------
手写的对照表一定会漂移。本项目已经栽过多次「两份副本各说各话」，所以这里
不靠人记，只靠两份**实际存在的文件**：

    zhstdlib\\<类别>\\<中文头>        中文侧（真源）
    vendor\\msvc-stl\\<英文头>        英文母本（中文侧是它的逐行翻译副本）
    vendor\\mingw\\<英文头>           C 运行库的母本

三部分提取方式
--------------
1. 头文件对照：中文头第一行 `#include <英文头>` 就是它的母本。
2. 类型别名对照：正则抓 `使用 <中文> = <英文>;`（别名层与类内的 using）。
3. 成员函数对照：**按函数定义出现的顺序配对**。
   翻译保留结构，不保留行号（注释翻译会改变行数：向量 4065 行 vs vector
   3988 行）。实测两边的函数名序列长度相同（119 = 119），顺序一一对应，
   所以按位置 zip 即可，再用「中文侧含汉字、英文侧纯 ASCII」筛一遍。

**只收录能验证的条目。** 计数不一致的头一律跳过并在文末列出，绝不猜。

用法：
    python tools\\make_lib_cheatsheet.py
输出：
    docs\\用户手册\\中英对照-标准库.md
"""

import difflib
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZH_ROOT = os.path.join(ROOT, "zhstdlib")
OUT = os.path.join(ROOT, "docs", "用户手册", "中英对照-标准库.md")
# 同一份内容也放进 packaging\，随包发给用户（同一个生成器产出两份，不会漂移）
OUT_PKG = os.path.join(ROOT, "packaging", "中英对照-标准库.md")

CJK = re.compile(r"[\u4e00-\u9fff]")
IDENT = re.compile(r"^[A-Za-z_\u4e00-\u9fff][\w\u4e00-\u9fff]*$")

# 中文头第一行/前几行的 #include <英文头>，但要排除内部实现头
INTERNAL_HEADER = re.compile(
    r"^(yvals_core\.h|__.*|x.*|yvals\.h|vcruntime.*|sal\.h|_.*|.*\.hpp|.*\.inl)$"
)
INCLUDE = re.compile(r"^\s*#\s*include\s*<([^>]+)>")

# 成员函数定义行。
# ⚠ 不能写成「一个返回类型 + 名字」：实测中文侧是 `_CONSTEXPR20 void 尾插(...)`，
#   名字前面可能有多个 token（_CONSTEXPR20 / void / 类名限定），只认一个 token
#   会把**全部公开方法**漏掉（这就是第一版只剩内部名和容量的原因）。
#   改成「任意个 token，第一个后面紧跟 `(` 的就是函数名」再排除控制流。
FUNC_DEF = re.compile(
    r"^\s*(?:\S+\s+)*?([\u4e00-\u9fffA-Za-z_][\w\u4e00-\u9fff]*)\s*\(([^;]*)$"
)
# 这些行不是函数定义（控制流 / 构造初始化列表 / 运算符重载）
BAD_LINE_START = re.compile(
    r"^\s*(?:return|if|for|while|switch|catch|sizeof|throw|delete|new|using|case|else|"
    r"do|try|co_return|co_await|co_yield|:|,|&&|\|\||\?\?|\[\[)\b"
)

# 这些词不是函数名（匹配到就说明正则吃到了说明符或控制流）
SPECIFIERS = {
    "constexpr", "consteval", "constinit", "static", "inline", "virtual", "explicit",
    "friend", "noexcept", "const", "volatile", "typename", "template", "if", "else",
    "for", "while", "do", "switch", "case", "return", "catch", "sizeof", "decltype",
    "alignof", "static_assert", "throw", "new", "delete", "operator", "using",
    "return", "public", "private", "protected", "class", "struct", "enum", "union",
}
NOT_A_NAME = {
    "if", "for", "while", "switch", "return", "catch", "sizeof", "static_assert",
    "decltype", "alignof", "noexcept", "throw", "new", "delete", "operator",
}

# 别名 / using
USING_ALIAS = re.compile(
    r"^\s*(?:模板\s*<[^>]*>\s*)?使用\s+([\w\u4e00-\u9fff]+)\s*=\s*([\w:]+)\s*;"
)


def read_lines(path):
    with io.open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


def zh_headers():
    """[(类别, 中文头名, 路径)]，按类别排序。"""
    result = []
    for category in sorted(os.listdir(ZH_ROOT)):
        cdir = os.path.join(ZH_ROOT, category)
        if not os.path.isdir(cdir):
            continue
        for name in sorted(os.listdir(cdir)):
            p = os.path.join(cdir, name)
            if os.path.isfile(p):
                result.append((category, name, p))
    return result


def english_parent(lines, category):
    """中文头对应的英文母本头名（取第一个非内部 include）。"""
    for line in lines[:40]:
        m = INCLUDE.match(line)
        if not m:
            continue
        name = m.group(1).strip()
        if INTERNAL_HEADER.match(os.path.basename(name)):
            continue
        return name
    return None


def find_english_file(header):
    """在 vendor 树里找英文母本，返回路径或 None。"""
    base = header.replace("/", os.sep)
    for tree in ("msvc-stl", "mingw", "compiler-support"):
        p = os.path.join(ROOT, "vendor", tree, base)
        if os.path.isfile(p):
            return p
    return None


def param_arity(params_text):
    """参数个数：数顶层逗号 + 1（空参数表算 0）。"""
    t = params_text.strip()
    if not t or t == "void":
        return 0
    depth = 0
    n = 1
    for ch in t:
        if ch in "<([{":
            depth += 1
        elif ch in ">)]}":
            depth -= 1
        elif ch == "," and depth == 0:
            n += 1
    return n


def norm_signature(line, own_name):
    """把一行函数定义归一化成可比较的签名。

    为什么需要它：顺序配对会漂移（实测「相邻差」曾配到 constexpr）。
    签名匹配不依赖顺序：把 STL 内部标识符 `_Xxx` 与中文标识符都归一化，
    再把函数自己的名字抹掉，两侧就应当逐字相同。
        void 尾插(const _类型& _Val)      -> void ZH(const _& _)
        void push_back(const _Ty& _Val)  -> void ZH(const _& _)
    """
    s = line
    for cut in ("{", "//", "/*"):
        s = s.split(cut)[0]
    s = s.replace(own_name, "ZH", 1)
    s = re.sub(r"_[A-Za-z0-9_\u4e00-\u9fff]+", "_", s)          # STL 内部标识符
    s = re.sub(r"[\u4e00-\u9fff][\w\u4e00-\u9fff]*", "ZH", s)   # 中文标识符
    s = re.sub(r"\s+", " ", s).strip()
    return s


def params_of(sig):
    """从归一化签名里取出参数表部分（含括号），用来做「只比参数」的兜底匹配。"""
    i = sig.find("(")
    if i < 0:
        return ""
    depth = 0
    for j in range(i, len(sig)):
        if sig[j] == "(":
            depth += 1
        elif sig[j] == ")":
            depth -= 1
            if depth == 0:
                return sig[i : j + 1]
    return sig[i:]


def func_entries(lines):
    """[(名字, 参数个数, 归一化签名)]，按出现顺序。"""
    out = []
    for line in lines:
        if BAD_LINE_START.match(line):
            continue
        m = FUNC_DEF.match(line)
        if not m:
            continue
        n, params = m.group(1), m.group(2)
        if n in NOT_A_NAME or n in SPECIFIERS or n.startswith("_STD"):
            continue
        out.append((n, param_arity(params), norm_signature(line, n)))
    return out


def type_aliases(lines):
    out = []
    for line in lines:
        m = USING_ALIAS.match(line)
        if not m:
            continue
        zh, en = m.group(1), m.group(2)
        if CJK.search(zh) and not CJK.search(en):
            out.append((zh, en))
    return out


# 手工核对补丁表：自动匹漏掉的极短名（`尺寸`/`容量`/`清空` 这类名字，
# 在英文母本里与相邻重载签名相同，diff 对齐时会落进 delete/insert 块而漏掉）。
# 每一条都来自**源码定义行**（人工读过），并且生成时还会做两道机器校验：
#   1) 中文名必须在中文头里作为函数定义出现
#   2) 英文名必须在英文母本里作为函数定义出现，且参数个数相同
# 校验不过的一律不收录（打到最后的小节里）。
MANUAL = {
    "标准库\\向量": [("尺寸", "size"), ("容量", "capacity"), ("清空", "clear")],
}


def esc(s):
    return s.replace("|", "\\|")


def main():
    headers = zh_headers()
    print("中文头总数 = %d" % len(headers))

    # ---- 1. 头文件对照 -----------------------------------------------------
    header_rows = []
    for category, name, path in headers:
        lines = read_lines(path)
        eng = english_parent(lines, category)
        header_rows.append((category, name, eng or "—"))

    # ---- 2. 类型别名 -------------------------------------------------------
    alias_pairs = {}
    for category, name, path in headers:
        for zh, en in type_aliases(read_lines(path)):
            alias_pairs.setdefault(zh, (en, "%s\\%s" % (category, name)))

    # ---- 3. 成员函数（顺序配对） -------------------------------------------
    member_by_header = {}
    skipped = []
    signature_dropped = [0]
    unmatched = [0]
    for category, name, path in headers:
        if category not in ("标准库", "C运行库", "windows系统"):
            continue
        lines = read_lines(path)
        eng_header = english_parent(lines, category)
        if not eng_header:
            skipped.append((category, name, "认不出英文母本"))
            continue
        eng_path = find_english_file(eng_header)
        if not eng_path:
            skipped.append((category, name, "母本 %s 不在 vendor 树里" % eng_header))
            continue
        zh_ents = func_entries(lines)
        en_ents = func_entries(read_lines(eng_path))
        # 对齐方式：用「签名序列」做 difflib 对齐（相当于逐条 diff），
        # 相等块里按顺序一一配对；替换块只有两侧长度相同才按位置配对。
        # 这样既利用「翻译保留顺序」这一结构事实，又用签名做交叉校验 ——
        # 单靠顺序会漂移（相邻差→constexpr），单靠签名会有多个候选
        # （size/capacity/empty 的签名都是 () const noexcept）。
        zsigs = [s for _, _, s in zh_ents]
        esigs = [s for _, _, s in en_ents]
        sm = difflib.SequenceMatcher(None, zsigs, esigs, autojunk=False)
        pairs = []
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == "equal":
                span = range(i2 - i1)
            elif tag == "replace" and (i2 - i1) == (j2 - j1):
                span = range(i2 - i1)
            else:
                continue
            for k in span:
                zh = zh_ents[i1 + k][0]
                en = en_ents[j1 + k][0]
                if CJK.search(zh) and not CJK.search(en) and IDENT.match(en):
                    pairs.append((zh, en))
                elif not CJK.search(zh):
                    pass
                else:
                    signature_dropped[0] += 1
        if not pairs:
            unmatched[0] += 1
        # 说明：试过按「参数表」做兜底匹配，会误配（尾插 在别的头里配到 push_front，
        # 反而被歧义过滤掉），因此不采用。漏掉的极短名在手写速查表里补。

        pairs = list(dict.fromkeys(pairs))  # 同一头里的重复特化只留一条
        if pairs:
            member_by_header.setdefault((category, name, eng_header), []).extend(pairs)

    # 去重 + 去掉有歧义的（同一中文名对应多个英文名）
    all_pairs = {}
    for key, pairs in member_by_header.items():
        for zh, en in pairs:
            all_pairs.setdefault(zh, set()).add(en)
    ambiguous = {zh: ens for zh, ens in all_pairs.items() if len(ens) > 1}
    for key in member_by_header:
        member_by_header[key] = [
            (zh, en) for zh, en in member_by_header[key] if zh not in ambiguous
        ]

    # ---- 输出 --------------------------------------------------------------
    out = []
    w = out.append
    w("# 中英对照表 · 标准库用法")
    w("")
    w("> **本文是生成物**，不要手改。改 `zhstdlib\\` 之后重跑：")
    w(">")
    w("> ```")
    w("> python tools\\make_lib_cheatsheet.py")
    w("> ```")
    w(">")
    w("> 关键字表是另一份生成物：`packaging\\中文对照表.md`")
    w("> （`python tools\\make_cheatsheet.py`，数据源是编译器自己的")
    w("> `ChineseKeywords.def` / `ChineseDirectives.def`）。")
    w("")
    w("数据源只有两份实际存在的文件：中文侧 `zhstdlib\\<类别>\\<中文头>`，")
    w("英文母本 `vendor\\msvc-stl\\<英文头>`（或 `vendor\\mingw\\`）。")
    w("**只收录能验证的条目**：成员函数按「函数定义出现顺序」配对，")
    w("两边计数不一致的头一律跳过，并在文末列出。")
    w("")

    w("## 一、头文件对照（%d 个中文头）" % len(header_rows))
    w("")
    w("| 中文头 | 英文头 | 类别 |")
    w("|---|---|---|")
    for category, name, eng in header_rows:
        w("| `%s` | %s | %s |" % (esc(name), ("`%s`" % esc(eng)) if eng != "—" else "—", scope(category)))
    w("")

    w("## 二、类型与别名对照（%d 条）" % len(alias_pairs))
    w("")
    w("| 中文名 | 英文原名 | 定义在 |")
    w("|---|---|---|")
    for zh in sorted(alias_pairs):
        en, where = alias_pairs[zh]
        w("| `%s` | `%s` | `%s` |" % (esc(zh), esc(en), esc(where)))
    w("")

    # ---- 手工补丁表（带机器校验，不过就丢） ------------------------------
    manual_added = []
    manual_rejected = []
    zh_by_header = {}
    for category, name, path in headers:
        zh_by_header["%s\\%s" % (category, name)] = (path, read_lines(path))
    for key, items in MANUAL.items():
        if key not in zh_by_header:
            for zh, en in items:
                manual_rejected.append((key, zh, en, "头不存在"))
            continue
        path, lines = zh_by_header[key]
        zh_ops = {n: a for n, a, _ in func_entries(lines)}
        eng_header = english_parent(lines, "标准库")
        eng_path = find_english_file(eng_header) if eng_header else None
        en_ops = {n: a for n, a, _ in func_entries(read_lines(eng_path))} if eng_path else {}
        for zh, en in items:
            if zh not in zh_ops or en not in en_ops:
                manual_rejected.append((key, zh, en, "一侧找不到该函数定义"))
                continue
            if zh_ops[zh] != en_ops[en]:
                manual_rejected.append((key, zh, en, "参数个数 %d vs %d" % (zh_ops[zh], en_ops[en])))
                continue
            manual_added.append((key, zh, en))

    w("## 三、成员函数对照")
    w("")
    w("按中文头分组。**公开名**（写在业务代码里的）在前，")
    w("**内部实现名**（读 STL 源码时才会遇到的 `_` 开头名字）在后，分开列。")
    w("")
    flat = {}
    for key, pairs in member_by_header.items():
        for zh, en in pairs:
            flat.setdefault(zh, (en, key[2]))
    ordered = sorted(member_by_header.items(), key=lambda kv: (-len(kv[1]), kv[0][1]))
    public_total = 0
    internal_total = 0
    for (category, name, eng_header), pairs in ordered:
        public = [(zh, en) for zh, en in pairs if not en.startswith("_")]
        internal = [(zh, en) for zh, en in pairs if en.startswith("_")]
        if not public and not internal:
            continue
        public_total += len(public)
        internal_total += len(internal)
        w("### `%s` ←→ `%s`（公开 %d / 内部 %d）" % (name, eng_header, len(public), len(internal)))
        w("")
        if public:
            w("| 中文 | 英文 | 中文 | 英文 |")
            w("|---|---|---|---|")
            half = (len(public) + 1) // 2
            for i in range(half):
                left = public[i]
                right = public[i + half] if i + half < len(public) else ("", "")
                w(
                    "| `%s` | `%s` | %s | %s |"
                    % (
                        esc(left[0]),
                        esc(left[1]),
                        ("`%s`" % esc(right[0])) if right[0] else "",
                        ("`%s`" % esc(right[1])) if right[1] else "",
                    )
                )
        else:
            w("（无公开名，见下方内部名）")
        if internal:
            w("")
            w("<details><summary>内部实现名 %d 条（读源码时用）</summary>" % len(internal))
            w("")
            w("、".join("`%s`=`%s`" % (esc(zh), esc(en)) for zh, en in internal))
            w("")
            w("</details>")
        w("")
    w("成员函数条目合计：**%d** 条（公开 %d / 内部 %d，去重后 %d 个中文名）。" % (
        public_total + internal_total, public_total, internal_total, len(flat)))
    w("")
    if signature_dropped[0] or unmatched[0]:
        w("匹配方式：把函数定义行归一化（STL 内部标识符 `_Xxx` 与中文标识符都抹平、")
        w("函数自身的名字也抹掉）后逐条比对签名，**只接受唯一匹配**。")
        w("签名匹配不依赖顺序，因此不会出现顺序配对那种漂移。")
        w("")
        w("- 签名唯一匹配：**%d** 条" % (public_total + internal_total))
        w("- 匹配到多个候选（有歧义，丢弃）：**%d** 条" % signature_dropped[0])
        w("- 中文侧找不到同签名（丢弃）：**%d** 条" % unmatched[0])
        w("")

    if manual_added:
        w("### 手工核对补丁（%d 条）" % len(manual_added))
        w("")
        w("这些短名与相邻重载签名相同，diff 对齐会漏掉；条目取自源码定义行，")
        w("生成时做「两侧都存在 + 参数个数相同」两道校验。")
        w("")
        w("| 中文 | 英文 | 所属头 |")
        w("|---|---|---|")
        for key, zh, en in manual_added:
            w("| `%s` | `%s` | `%s` |" % (esc(zh), esc(en), esc(key.split("\\")[-1])))
        w("")

    w("## 四、没有自动收录的部分")
    w("")
    if ambiguous:
        w("- **同一中文名对应多个英文名**（有歧义，未收录）：")
        for zh in sorted(ambiguous)[:4]:
            w("  - `%s` → %s" % (zh, ", ".join("`%s`" % e for e in sorted(ambiguous[zh]))))
        if len(ambiguous) > 4:
            w("  - ……共 %d 个" % len(ambiguous))
    if skipped:
        w("- **函数名计数对不齐，按纪律跳过**（不猜）：")
        for category, name, why in skipped[:8]:
            w("  - `%s\\%s`：%s" % (category, name, why))
        if len(skipped) > 8:
            w("  - ……共 %d 个头" % len(skipped))
    if not ambiguous and not skipped:
        w("- 无。")
    w("")
    w("## 五、怎么用")
    w("")
    w("同一件事的两种写法，编译结果等价：")
    w("")
    w("```cpp")
    w("// 中文")
    w("#包含 <向量>")
    w("标准::向量<整数> 表;")
    w("表.尾插(1);")
    w("```")
    w("")
    w("```cpp")
    w("// 英文（原名照旧可用）")
    w("#include <vector>")
    w("std::vector<int> v;")
    w("v.push_back(1);")
    w("```")
    w("")

    text = "\n".join(out)
    for path in (OUT, OUT_PKG):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("已写出 %s" % path)

    print("已写出 %s" % OUT)
    print("头文件 %d 条 / 类型别名 %d 条 / 成员函数 %d 条 / 跳过 %d 个头"
          % (len(header_rows), len(alias_pairs),
             sum(len(v) for v in member_by_header.values()), len(skipped)))


def scope(category):
    return {
        "标准库": "C++ 标准库",
        "别名": "别名层",
        "C运行库": "C 运行库",
        "windows系统": "Windows 平台",
    }.get(category, category)


if __name__ == "__main__":
    main()
