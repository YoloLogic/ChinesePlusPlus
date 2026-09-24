#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""反查诊断 ID + 校核中文诊断表。

两件事：

1. 反查：把编译器实际打出来的英文诊断文本，反查回诊断 ID
   （= 生成的 Diagnostic*Kinds.inc 里 DIAG 的第一个参数 = .td 里 def 的名字）。

2. 校核：读 clang/include/clang/Basic/ChineseDiagnostics.def，逐条检查
   「ID 真的存在」以及「占位符与英文对得上」。占位符写坏是这件事最大的
   风险（漏 %0 / 写坏 %select 的竖线 / 分支顺序颠倒了），必须机器做。

关键事实（实测）：**生成表 .inc 才是准的，源表 .td 不是**。
   .td 里的 "%sub{select_ovl_candidate_kind}0,1,2" 在生成时就被展开成了
   "%select{function|constructor|...}0"，%enum_select<...>{...} 同理。
   所以：找 def 看 .td（好读、有行号），翻译抄 .inc（已展开、拿到就能用）。

本脚本只读，不改编译器。用法：
  python tools/diag_id_lookup.py                # 跑语料 + 反查，写报告
  python tools/diag_id_lookup.py --no-corpus    # 只做表结构统计
  python tools/diag_id_lookup.py --check-table  # 只校核中文表（退出码 0/1）
"""

import argparse
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TD_DIR = os.path.join(ROOT, "LLVM-main", "clang", "include", "clang", "Basic")
INC_DIR = os.path.join(ROOT, "build", "tools", "clang", "include", "clang", "Basic")
ZH_DEF = os.path.join(ROOT, "LLVM-main", "clang", "include", "clang", "Basic",
                      "ChineseDiagnostics.def")

# 中文表至少要有这么多条。**加了一批就把它调大。**
# 存在的理由：逐条校核抓不到"表被改小"—— 剩下的条目依然条条合法。
# 独立复核者 2026-09-22 实测：砍到 7 条时校核器仍报 0 问题、退出码 0（反例 A）。
MIN_ENTRIES = 7344
CORPUS = os.path.join(ROOT, "build", "_diag_corpus")
CLANGXX = os.path.join(ROOT, "build", "Release", "bin", "clang++.exe")
REPORT = os.path.join(ROOT, "build", "_diag_report.txt")


# --------------------------------------------------------------------------
# 通用小工具
# --------------------------------------------------------------------------

def unescape(lit):
    out, i, n = [], 0, len(lit)
    while i < n:
        c = lit[i]
        if c == "\\" and i + 1 < n:
            d = lit[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(d, d))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_top(s, sep):
    out, cur, depth = [], [], 0
    for ch in s:
        if ch in "{(":
            depth += 1
        elif ch in "})":
            depth -= 1
        if ch == sep and depth == 0:
            out.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    out.append("".join(cur))
    return out


def read_braced(s, i):
    """s[i] == '{'，返回 (内层, 收尾下标+1)。"""
    depth, j = 0, i
    while j < len(s):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return s[i + 1:j], j + 1
        j += 1
    return s[i + 1:], len(s)


def split_args(s):
    """按顶层逗号切分 DIAG(...) 的参数。"""
    out, cur, depth, in_str = [], [], 0, False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_str:
            if c == "\\":
                cur.append(s[i:i + 2])
                i += 2
                continue
            if c == '"':
                in_str = False
            cur.append(c)
            i += 1
            continue
        if c == '"':
            in_str = True
            cur.append(c)
            i += 1
            continue
        if c in "(<{[":
            depth += 1
        elif c in ")>}]":
            depth -= 1
        if c == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    out.append("".join(cur).strip())
    return out


# --------------------------------------------------------------------------
# 一、解析生成表 .inc（权威）
# --------------------------------------------------------------------------

def parse_inc():
    """生成表：name -> (消息, 文件名, 行号)。"""
    entries = {}
    for path in sorted(glob.glob(os.path.join(INC_DIR, "Diagnostic*Kinds.inc"))):
        with open(path, encoding="utf-8", errors="replace") as f:
            for lineno, line in enumerate(f, 1):
                if not line.lstrip().startswith("DIAG("):
                    continue
                body = line.strip()
                body = body[body.index("(") + 1:]
                if body.endswith(")"):
                    body = body[:-1]
                args = split_args(body)
                if len(args) < 4:
                    continue
                desc = args[3]
                if not desc.startswith('"'):
                    continue
                end = desc.rfind('"')
                entries[args[0]] = (unescape(desc[1:end]),
                                    os.path.basename(path), lineno)
    return entries


# --------------------------------------------------------------------------
# 二、解析源表 .td（只为定位/好读）
# --------------------------------------------------------------------------

DEF_RE = re.compile(r"\bdef\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w:]*)\s*<")
STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def blank_comments(text):
    out = list(text)
    i, n, in_str = 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def matching_angle(text, start):
    depth, i, n, in_str = 0, start, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == "<":
            depth += 1
        elif c == ">":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def parse_td():
    entries = {}
    for path in sorted(glob.glob(os.path.join(TD_DIR, "Diagnostic*Kinds.td"))):
        raw = open(path, encoding="utf-8", errors="replace").read()
        text = blank_comments(raw)
        for m in DEF_RE.finditer(text):
            lt = text.index("<", m.start())
            gt = matching_angle(text, lt)
            if gt == -1:
                continue
            head = text[lt + 1:gt].lstrip()
            if not head.startswith('"'):
                continue
            parts, pos = [], 0
            while True:
                mm = STR_RE.match(head, pos)
                if not mm:
                    break
                parts.append(unescape(mm.group(1)))
                pos = mm.end()
                while pos < len(head) and head[pos] in " \t\r\n":
                    pos += 1
            if not parts:
                continue
            line = raw.count("\n", 0, m.start()) + 1
            entries[m.group(1)] = ("".join(parts), os.path.basename(path), line)
    return entries


# --------------------------------------------------------------------------
# 三、占位符语法（见 clang/docs/InternalsManual.rst「The Format String」）
# --------------------------------------------------------------------------

PLACEHOLDER = r"(?:'[^']*?'|[^\s']+)"
ORDINAL_RE = r"\d+(?:st|nd|rd|th)"
HUMAN_RE = r"[0-9.]+[kMGT]?"

BRANCHING = ("select", "plural", "selectordinal", "diff")


def scan_specs(tpl):
    """遍历模板里的占位符，产出 (种类, 参数序号元组, 分支数或 None, 内层文本)。

    种类：
      arg      普通 %0 / %q0 / %quoted0 / %human0 …（word 为 "" / "q" / …）
      s        %s0 —— 英文复数 s，中文可以直接删
      ordinal  %ordinal0 —— 只渲染成英文的 1st/2nd
      select / plural / selectordinal / diff —— 有分支
    """
    i, n = 0, len(tpl)
    while i < n:
        if tpl[i] != "%":
            i += 1
            continue
        # %% 是【字面百分号】的转义，不是占位符。漏掉这一支会把 `%%` 判成
        # "畸形的 % 转义"，于是任何保留 %% 的译文都会红 —— 可 %% 恰恰是必须
        # 原样保留的。批量翻译 7 条含 %% 的条目时撞出来的。
        if i + 1 < n and tpl[i + 1] == "%":
            i += 2
            continue
        j = i + 1
        word = ""
        while j < n and tpl[j].isalpha():
            word += tpl[j]
            j += 1
        if j < n and tpl[j] == "<":          # %enum_select<Kind>{...}N
            k = tpl.find(">", j)
            if k == -1:
                yield ("bad", (), None, "")
                i = j
                continue
            j = k + 1
        if j < n and tpl[j] == "{":          # 有分支的占位符
            inner, after = read_braced(tpl, j)
            k, idxs = after, []
            while k < n and (tpl[k].isdigit() or tpl[k] == ","):
                if tpl[k].isdigit():
                    st = k
                    while k < n and tpl[k].isdigit():
                        k += 1
                    idxs.append(int(tpl[st:k]))
                else:
                    k += 1
            kind = word if word in BRANCHING else "select"
            yield (kind, tuple(idxs), len(split_top(inner, "|")), inner)
            i = k
            continue
        k = j
        while k < n and tpl[k].isdigit():
            k += 1
        if k == j:
            yield ("bad", (), None, "")
            i = k
            continue
        yield (word or "arg", (int(tpl[j:k]),), None, "")
        i = k


def spec_profile(tpl):
    """把一个模板压成可比较的「指纹」。

    返回 (原子, 分支, 问题)：
      原子 = 排序后的 [(种类, 参数序号)]，只含直接渲染参数的占位符。
             %ordinalN 归一成 ("arg", N)；%sN 直接丢掉（中文可删）。
      分支 = 排序后的 [(种类, 参数序号元组, 分支数)]，递归进每个分支收集。

    用「多重集」而不是「有序序列」比较：中文语序与英文不同
    （"A 中没有 B" 对应 "no B in A"），参数出现顺序本来就会变。
    真正不能变的是：引用了哪几个参数、每个 %select 挂在哪个序号上、
    有几个分支。
    """
    atoms, branches, problems = [], [], []

    def walk(s):
        for (kind, idxs, nalt, inner) in scan_specs(s):
            if kind == "bad":
                problems.append("畸形的 %% 转义：%r" % s)
                continue
            if kind == "s":
                continue                      # 中文没有单复数，允许删
            if kind == "ordinal":
                atoms.append(("arg", idxs[0]))  # 中文写 第%N个，取整数
                continue
            if kind in BRANCHING:
                branches.append((kind, idxs, nalt))
                for alt in split_top(inner, "|"):
                    walk(alt)
                continue
            atoms.append((kind, idxs[0]))

    walk(tpl)
    return sorted(atoms), sorted(branches), problems


def branch_signature(tpl):
    r"""按文档顺序收集每个分支占位符、以及它各分支的"原子画像"。

    用途：抓 **分支顺序被颠倒**。多重集比较（spec_profile）抓不到这个，
    因为它排序了。独立复核者 2026-09-22 指出这一层原本是缺口（F4）。

    局限（如实写在 docs\诊断汉化\诊断汉化清单.md 里）：若某个 %select 的所有分支彼此
    原子画像完全相同（例如 %select{非|}），颠倒顺序在结构上看不出来 ——
    这类只能靠运行时逐条断言兜底。
    """
    out = []

    def walk(s):
        for (kind, idxs, nalt, inner) in scan_specs(s):
            if kind not in BRANCHING:
                continue
            alts = split_top(inner, "|")
            sigs = []
            for a in alts:
                a_atoms, _a_br, _a_pb = spec_profile(a)
                sigs.append(tuple(a_atoms))
            out.append((kind, idxs, tuple(sigs)))
            for a in alts:
                walk(a)

    walk(tpl)
    return out


# 去掉所有 %… 占位符后剩下的纯文本，用来找"中文正文里混着的英文词"。
# 这类残留不一定是错的（分号 ';'、代码关键字 'typename' 就该保留），
# 所以只报告、不判失败，由人确认。
ASCII_RUN = re.compile(r"[A-Za-z]{2,}")


def strip_specs(tpl):
    out, i, n = [], 0, len(tpl)
    while i < n:
        if tpl[i] != "%":
            out.append(tpl[i])
            i += 1
            continue
        j = i + 1
        while j < n and tpl[j].isalpha():
            j += 1
        if j < n and tpl[j] == "<":
            k = tpl.find(">", j)
            j = (k + 1) if k != -1 else j
        if j < n and tpl[j] == "{":
            _inner, after = read_braced(tpl, j)
            k = after
            while k < n and (tpl[k].isdigit() or tpl[k] == ","):
                k += 1
            i = k
            continue
        k = j
        while k < n and tpl[k].isdigit():
            k += 1
        i = k
    return "".join(out)


def ascii_residue(tpl):
    """中文正文里出现的英文单词（不含占位符内部）。需人工判断是否该保留。"""
    return sorted(set(ASCII_RUN.findall(strip_specs(tpl))))


def template_to_regex(tpl):
    """模板 -> 正则，用来拿实测文本反查 ID。"""
    out, i, n = [], 0, len(tpl)
    while i < n:
        c = tpl[i]
        if c != "%":
            out.append(re.escape(c))
            i += 1
            continue
        j = i + 1
        word = ""
        while j < n and tpl[j].isalpha():
            word += tpl[j]
            j += 1
        if j < n and tpl[j] == "<":
            k = tpl.find(">", j)
            j = (k + 1) if k != -1 else j
        if j < n and tpl[j] == "{":
            inner, after = read_braced(tpl, j)
            if word == "plural" or word == "selectordinal":
                alts = []
                for p in split_top(inner, "|"):
                    k = p.find(":")
                    alts.append(p[k + 1:] if k != -1 else p)
                out.append("(?:" + "|".join(template_to_regex(a) for a in alts) + ")")
            elif word == "diff":
                parts = split_top(inner, "|")
                alts = [p.replace("$", PLACEHOLDER) for p in parts]
                out.append("(?:" + "|".join(template_to_regex(a) for a in alts) + ")")
            else:
                out.append("(?:" + "|".join(
                    template_to_regex(p) for p in split_top(inner, "|")) + ")")
            k = after
            while k < n and (tpl[k].isdigit() or tpl[k] == ","):
                k += 1
            i = k
            continue
        k = j
        while k < n and tpl[k].isdigit():
            k += 1
        if k == j:
            out.append(re.escape("%" + word))
            i = k
            continue
        if word == "s":
            out.append("s?")
        elif word == "ordinal":
            out.append(ORDINAL_RE)
        elif word == "human":
            out.append(HUMAN_RE)
        else:
            out.append(PLACEHOLDER)
        i = k
    return "".join(out)


# --------------------------------------------------------------------------
# 四、跑语料
# --------------------------------------------------------------------------

DIAG_LINE = re.compile(
    r"^(.*?):\s*(error|warning|note|remark|fatal error):\s*(.*?)(?:\s*\[-W[\w\-\+=,]+\])?\s*$"
)


def run_corpus():
    if not os.path.isfile(CLANGXX):
        sys.exit("找不到编译器：%s" % CLANGXX)
    msgs = []
    for path in sorted(glob.glob(os.path.join(CORPUS, "*.cpp"))):
        cmd = [CLANGXX, "-std=c++20", "-fsyntax-only", "-Wall", "-Wextra",
               "-ferror-limit=0", "-fno-caret-diagnostics",
               "-fno-diagnostics-fixit-info", "-fno-color-diagnostics", path]
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for line in p.stderr.decode("utf-8", errors="replace").splitlines():
            m = DIAG_LINE.match(line)
            if m:
                msgs.append((os.path.basename(path), m.group(2), m.group(3).strip()))
    return msgs


# --------------------------------------------------------------------------
# 五、读并校核中文表
# --------------------------------------------------------------------------

def parse_zh_def(raw=None):
    """读 ChineseDiagnostics.def，返回 [(name, text, 行号)]。支持相邻字符串拼接。

    raw 可以显式传入文本（自测要喂被截断的副本时用）。
    """
    if raw is None:
        if not os.path.isfile(ZH_DEF):
            return []
        raw = open(ZH_DEF, encoding="utf-8", errors="replace").read()
    # 用「注释被抹成空格、长度不变」的副本扫描，避免注释里的示例被当成条目
    scan = blank_comments(raw)
    out = []
    for m in re.finditer(r"ZH_DIAG\s*\(", scan):
        # 跳过表头的 "#define ZH_DIAG(NAME, TEXT)"
        bol = scan.rfind("\n", 0, m.start()) + 1
        if scan[bol:m.start()].lstrip().startswith("#"):
            continue
        start = m.end()
        depth, i, n, in_str = 1, start, len(scan), False
        while i < n and depth:
            c = scan[i]
            if in_str:
                if c == "\\":
                    i += 2
                    continue
                if c == '"':
                    in_str = False
                i += 1
                continue
            if c == '"':
                in_str = True
                i += 1
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
        args = split_args(scan[start:i - 1])
        if len(args) < 2:
            continue
        name = args[0].strip()
        parts = [unescape(mm.group(1)) for mm in STR_RE.finditer(args[1])]
        if not parts:
            continue
        out.append((name, "".join(parts), raw.count("\n", 0, m.start()) + 1))
    return out


def check_zh(name, zh, inc):
    """返回问题列表（空 = 通过）与英文原文。"""
    problems = []
    if name not in inc:
        return ["%s：生成表里没有这个诊断 ID（拼错了？）" % name], None
    en = inc[name][0]
    en_atoms, en_br, en_bad = spec_profile(en)
    zh_atoms, zh_br, zh_bad = spec_profile(zh)
    if len(zh_bad) > len(en_bad):
        # 只报【中文比英文多出来】的畸形转义。英文模板自己就可能有这种写法
        # （例：note_omp_atomic_update 模板里含带引号的 '%|'，scan_specs 认不出），
        # 那是上游的写法，不是中文引入的 —— 原先只看 zh_bad，于是这条无论怎么
        # 翻都必红：删掉它还要同时丢记号、分支数对不上，两条路都走不通。
        problems.append("%s：中文里有畸形的 %% 转义（英文 %d 处，中文 %d 处）\n"
                        "      英文 %s\n      中文 %s"
                        % (name, len(en_bad), len(zh_bad), en, zh))
    if en_atoms != zh_atoms:
        problems.append("%s：引用的参数对不上\n      英文 %s\n      中文 %s"
                        % (name, en_atoms, zh_atoms))
    if en_br != zh_br:
        problems.append("%s：%%select/%%plural/%%diff 的结构对不上"
                        "（种类、挂的序号、分支数）\n      英文 %s\n      中文 %s"
                        % (name, en_br, zh_br))
    # 分支顺序：多重集比较抓不到"把两个分支对调"，这里按文档顺序比一次。
    en_sig = branch_signature(en)
    zh_sig = branch_signature(zh)
    if en_sig != zh_sig:
        problems.append("%s：分支顺序或分支内容对不上"
                        "（%%select 的分支就是下标，顺序不能换）\n      英文 %s\n      中文 %s"
                        % (name, en_sig, zh_sig))
    return problems, en


# --------------------------------------------------------------------------
# 六、主流程
# --------------------------------------------------------------------------

def self_test(inc):
    """自检：故意写坏几种占位符，确认校核器真的能抓出来。

    校核器永远返回「通过」就毫无价值，所以它自己也要有测试。
    """
    cases = [
        # (说明, ID, 故意写坏的中文, 是否应该被抓出)
        ("漏掉 %0", "err_unknown_typename", "未知的类型名", True),
        ("多出一个 %2", "err_no_member", "%1 中没有名为 %0 的成员 %2", True),
        ("把 %1 写成 %0（重复引用）", "err_no_member",
         "%0 中没有名为 %0 的成员", True),
        ("%select 少一个分支", "err_expected_unqualified_id",
         "缺少 %select{标识符}0", True),
        ("%select 挂错序号", "err_expected_unqualified_id",
         "缺少 %select{标识符|非限定标识符}1", True),
        ("嵌套 %select 被拆平", "err_typecheck_assign_const",
         "%select{不能给返回值赋值|不能给%select{变量 %2|左值}1赋值|"
         "只读变量不能赋值}0", True),
        ("中文删掉 %s（允许）", None, None, False),
        ("正确的中文", "err_unknown_typename", "未知的类型名 %0", False),
        ("%ordinal 改成 %N（允许）", None, None, False),
    ]
    bad = []
    for (why, name, zh, should_fail) in cases:
        if name is None:
            continue
        got, _ = check_zh(name, zh, inc)
        if bool(got) != should_fail:
            bad.append("%s：期望%s，实际%s" % (why, "报错" if should_fail else "通过",
                                            "报错" if got else "通过"))
    # 两条专门的「允许的改动」检查
    en = "requires %0 parameter%s0, has %1"
    ok_atoms, _, _ = spec_profile(en)
    zh_atoms, _, _ = spec_profile("需要 %0 个参数，已有 %1")
    if ok_atoms != zh_atoms:
        bad.append("删掉 %s 被误判：%s vs %s" % ("%s0", ok_atoms, zh_atoms))
    o_en, _, _ = spec_profile("ambiguity in %ordinal0 argument")
    o_zh, _, _ = spec_profile("第%0个实参有歧义")
    if o_en != o_zh:
        bad.append("%ordinal 改 %N 被误判：%s vs %s" % (o_en, o_zh))
    # 角色表检查本身也要有测试（2026-09-23 才真正实现；在此之前 .def 的注释
    # 曾写「校核器会查角色表」，而检查并不存在 —— 独立复核者用三份违规副本
    # 实测 problems=0 才把空洞暴露出来。一条没被测过的检查等于没有检查。）
    role_cases = [
        ("连词写法（允许）", "err_typecheck_invalid_operands",
         "二元表达式的运算对象无效（表达式 和 表达式）（%0 和 %1）", False),
        ("角色表里只有连词", "err_typecheck_invalid_operands",
         "二元表达式的运算对象无效（和）（%0 和 %1）", True),
        ("角色词不在封闭词表", "err_unknown_typename",
         "未知的类型名（东西） %0", True),
        ("含占位符的括号组不算角色表，光有它仍是缺角色表（硬失败）",
         "err_typecheck_invalid_operands",
         "二元表达式的运算对象无效（%0 和 %1）", True),
        # 判据本身的自测：%select 渲染的是"选中的那段文本"，不是参数的值。
        ("只有 %select、没有值占位符（不要求角色表）",
         "err_expected_unqualified_id",
         "缺少%select{标识符|非限定标识符}0", False),
        ("%select 之外还有值占位符（要求角色表）",
         "err_unknown_typename", "未知的类型名%select{|甲}0 %0", True),
    ]
    for (why, name, zh, should_fail) in role_cases:
        got, _ = check_role_table(name, zh)
        if bool(got) != should_fail:
            bad.append("角色表·%s：期望%s，实际%s"
                       % (why, "报错" if should_fail else "通过",
                          "报错" if got else "通过"))
    # 半角括号：必须失败，而且报错必须【说清是括号的问题】。
    # 只断言"失败"不够 —— 原来的失败信息指向"没有角色表"，会把人带偏，
    # 而那正是第四次复核记下的那个盲点。检查的措辞本身也要被检查。
    hp, _ = check_role_table("err_unknown_typename", "未知的类型名(类型名) %0")
    if not hp:
        bad.append("半角括号写的角色表没被判失败")
    elif "半角" not in hp[0]:
        bad.append("半角括号被判失败，但报错没指出是括号的问题：%s" % hp[0])
    # 分支顺序颠倒必须被抓到（独立复核者指出的缺口 F4，现已补上）
    sig_a = branch_signature("candidate %select{%ordinal0 argument|object argument}1")
    sig_b = branch_signature("candidate %select{object argument|%ordinal0 argument}1")
    if sig_a == sig_b:
        bad.append("分支顺序颠倒没被抓到（branch_signature 失效）")
    # 英文残留检测器本身也要能用
    if ascii_residue("未使用的 %select{类型别名|别名声明}0 %1"):
        bad.append("ascii_residue 把纯中文误报成英文残留")
    if "typedef" not in ascii_residue("未使用的 typedef %1"):
        bad.append("ascii_residue 抓不到英文残留")
    # 表被截断必须被抓到（独立复核者 2026-09-22 的反例 A）
    real_raw = open(ZH_DEF, encoding="utf-8", errors="replace").read()
    cut = real_raw.index("ZH_DIAG(err_no_member,")
    cut = real_raw.index("\n", cut) + 1
    trunc_raw = real_raw[:cut]
    trunc_zh = parse_zh_def(raw=trunc_raw)
    _l, trunc_probs, _z = check_table(inc, zh=trunc_zh, raw=trunc_raw)
    if not trunc_probs:
        bad.append("表被截断没被抓到（反例 A：砍到 %d 条仍报通过）" % len(trunc_zh))
    # 反过来：真表不能被这套新检查误伤
    good_probs = [p for p in check_table(inc, zh=parse_zh_def(raw=real_raw), raw=real_raw)[1]
                  if "少于下限" in p or "截断" in p or "守卫" in p]
    if good_probs:
        bad.append("新加的规模/收尾检查误报了真表：%s" % good_probs)

    # 不可翻记号检查本身也要有测试。它 2026-09-24 才加，加它的直接原因是
    # 「批量翻 2654 条纯句子」—— 那批没法逐条构造触发用例，只能靠静态不变量兜。
    # 一条没被测过的检查等于没有检查（这个项目已经栽过一次：.def 的注释声称
    # 校核器会查角色表，而检查并不存在）。
    tok_cases = [
        # (说明, 英文, 中文, 是否应该失败)
        ("引号里的代码丢了",
         "expected 'begin' or 'end'", "要求 开始 或 结束", True),
        ("关键字译成中文关键字（必须这样做）",
         "missing 'typename' prior to dependent type name",
         "依赖类型名之前缺少（关键字） 类型名", False),
        ("关键字保留英文原拼写（2026-09-24 起判失败）",
         "missing 'typename' prior to dependent type name",
         "依赖类型名之前缺少 'typename'", True),
        ("关键字既没译也没留（丢了）",
         "missing 'typename' prior to dependent type name",
         "依赖类型名之前缺少", True),
        ("选项丢了",
         "unknown argument '-fno-rtti'", "未知的参数", True),
        ("选项保留",
         "unknown argument '-fno-rtti'", "未知的参数 '-fno-rtti'", False),
        ("%% 转义丢了",
         "invalid %% escape in inline assembly string",
         "内联汇编字符串里的转义无效", True),
        ("%% 转义保留",
         "invalid %% escape in inline assembly string",
         "内联汇编字符串里的 %% 转义无效", False),
        ("带占位符的引号不算记号（不要求照抄引号）",
         "declare a conversion to '%1'", "声明到 %1 的转换", False),
        ("内建记号丢了",
         "use of __builtin_alloca_with_align", "使用了内建函数", True),
        ("内建记号保留",
         "use of __builtin_alloca_with_align", "使用了 __builtin_alloca_with_align", False),
    ]
    for (why, en, zh, should_fail) in tok_cases:
        got = check_protected_tokens("self_test", en, zh) + check_percent_escapes("self_test", en, zh)
        if bool(got) != should_fail:
            bad.append("记号·%s：期望%s，实际%s"
                       % (why, "报错" if should_fail else "通过",
                          "报错" if got else "通过"))

    # 关键字表必须真的读到了东西 —— 读不到就会让上面「关键字允许译」的用例
    # 悄悄变成「原样保留」，检查形同虚设。
    kw = keyword_cn_map()
    if kw.get("typename") != "类型名":
        bad.append("从 ChineseKeywords.def 读关键字映射失败：typename -> %r"
                   % kw.get("typename"))
    if kw.get("and") != "并且":
        bad.append("替代记号映射失败（and 应该 -> 并且）：%r" % kw.get("and"))

    # DSL 例外：引号里装的是别的语言的记号（OpenMP/OpenACC 子句名、map 取值），
    # 拼写碰巧和 C++ 关键字一样，必须保留英文。两个方向都要测。
    dsl_cases = [
        ("DSL 记号保留英文（正确）",
         "err_omp_no_more_if_clause", "no more 'if' clause is allowed",
         "不再允许 'if' 子句", False),
        ("DSL 记号被当成关键字译掉（要报错）",
         "err_omp_no_more_if_clause", "no more 'if' clause is allowed",
         "不再允许（关键字） 如果 子句", True),
        ("DSL 记号整个丢了（要报错）",
         "err_omp_no_more_if_clause", "no more 'if' clause is allowed",
         "不再允许该子句", True),
        ("同一个 'if' 在别的条目里【是】关键字语义时仍按关键字译",
         "err_if_expected", "expected 'if'", "缺少（关键字） 如果", None),
    ]
    for (why, name, en, zh, should_fail) in dsl_cases:
        if should_fail is None:          # 只断言不炸，不判成败
            continue
        got = check_protected_tokens(name, en, zh)
        if bool(got) != should_fail:
            bad.append("DSL·%s：期望%s，实际%s"
                       % (why, "报错" if should_fail else "通过",
                          "报错" if got else "通过"))
    # 例外名单本身要非空，且真的被用上 —— 空名单会让上面的用例悄悄退化
    if not KW_IS_DSL_TOKEN:
        bad.append("KW_IS_DSL_TOKEN 是空的，DSL 例外形同虚设")

    # （关键字）标记的适用范围。这条检查 2026-09-24 写好时**忘了接进 check_table**，
    # 也没写自检 —— 是批量翻译的子代理反过来指出的（"工具里定义了但没人调用"）。
    # 这个项目已经栽过两次同类：.def 注释声称会查角色表而检查不存在、
    # IGNORE_IDS 是死代码却在注释里声称做了排除。所以这里既接上、也补上自检。
    marker_cases = [
        ("引号内的关键字标了（正确）",
         "expected variable name or 'this' in lambda capture list",
         "lambda 捕获列表里缺少变量名或（关键字） 自身", False),
        ("裸提及也标了（要报错）",
         "for loop has empty body", "（关键字） 对于 循环的主体为空", True),
        ("裸提及不标（正确）",
         "for loop has empty body", "对于 循环的主体为空", False),
        ("标了个不在词表里的词（要报错）",
         "expected expression", "缺少（关键字） 表达式体", True),
        ("英文有引号形式但没标（不报错，交给 check_protected_tokens 管）",
         "'static_assert' with no message", "不带消息的静态断言", False),
    ]
    for (why, en, zh, should_fail) in marker_cases:
        got = check_keyword_markers("self_test", en, zh)
        if bool(got) != should_fail:
            bad.append("标记范围·%s：期望%s，实际%s"
                       % (why, "报错" if should_fail else "通过",
                          "报错" if got else "通过"))
    # 全角问号不能被当成关键字的一部分（'空型？' 曾被误报）
    if check_keyword_markers("self_test", "should this cast be to 'void'?",
                             "这个转换是否应该转换为（关键字） 空型？"):
        bad.append("全角问号被当成了中文关键字的一部分（'空型？'）")
    return bad


# 角色表的封闭词表（第三批起启用，见 ChineseDiagnostics.def 第十二节）。
# 加词是一次【明确动作】：要同时改这里和 .def 里的说明。
ROLE_WORDS = frozenset([
    "关键字", "种类", "变量名", "类型名", "函数名", "属性名", "成员名", "名字",
    "表达式", "类型", "符号", "选项",
])

# 角色表里允许出现的【连词】：多个成分并列时，角色表按位置一一对应，连词照写，
# 例如「二元表达式的运算对象无效（表达式 和 表达式）（%0 和 %1）」。
# 连词必须用空格与角色词分开；加词同样是一次【明确动作】。
ROLE_CONNECTORS = frozenset(["和", "与"])

# 匹配一处角色表：（关键字 类型名） / （名字） / （选项） / （表达式 和 表达式）
ROLE_GROUP_RE = re.compile(r"（([^（）]*)）")

# %select{…}N / %plural{…}N / %diff{…}N,M 的开头。要整块去掉，因为大括号会嵌套。
_SELECTOR_RE = re.compile(r"%(select|plural|diff)\{")


def has_value_placeholder(text):
    """去掉所有 %select/%plural/%diff 之后，文本里还有没有 "%"。

    为什么要这么判：`%select` 渲染的是【按参数选中的那段文本】，不是参数的值。
    分支本身是整句从句时（如 err_blocks_disable 的 "-fblocks 或部署目标"），
    句子里根本没有【成分】，也就没有东西可标角色。
    2026-09-23 的判据是「文本里有没有 %"，于是把这种条目误判成"缺角色表" ——
    是 C2a 两条新条目（err_blocks_disable / note_previous_initializer）撞出来的。
    """
    out, i, n = [], 0, len(text)
    while i < n:
        m = _SELECTOR_RE.match(text, i)
        if not m:
            out.append(text[i])
            i += 1
            continue
        j = m.end()                      # 刚过 '{'
        depth = 1
        while j < n and depth:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        while j < n and (text[j].isdigit() or text[j] == ","):
            j += 1                       # 跳过挂载序号（N 或 N,M）
        i = j
    # %% 是字面百分号的转义，不是占位符 —— 必须先去掉再判，
    # 否则任何保留 %% 的条目都会被判成"有占位符"，进而被要求挂角色表。
    return "%" in "".join(out).replace("%%", "")


def check_role_table(name, text):
    """角色表检查。返回 (硬问题列表, 待办报告行列表)。

    ⚠ 这个检查【查不出角色标错】—— 把（属性名）写成（变量名）照样通过。
      独立复核者 2026-09-23 实测：造三份违规副本喂给旧版校核器，
      「不存在的角色词」「整句无角色表」「角色标错」全部 problems=0，
      只有删占位符的对照组被抓到。这里是补上的两条。

    设计取舍的历史：2026-09-23 引入时，「有占位符就该有角色表」**只报告、不判失败**
    —— 第一批那 32 条写在角色表约定之前（例如 `缺少 %0` 就没有角色表），硬判会让
    它们全部变红，所以先列成迁移待办。当天 20 条迁移完毕后，这一项**转为硬失败**：
    既然「一律标」是有意选择的统一，就该由机器保证它继续成立，而不是靠人记得 ——
    新增条目若不带角色表会直接让校核器变红。

    2026-09-23 又修过一次判据：原先是「文本里有没有 %」，于是把【只有 %select】
    的条目也判成"缺角色表" —— 可那类条目的分支是整句从句，句子里根本没有成分。
    现在按 has_value_placeholder() 判：只有真正渲染【值】的占位符才算成分。
    """
    problems, notes = [], []
    # 候选括号组：不含占位符的（含 %0 的是「（%0 和 %1）」这种补注，不是角色表）。
    cands = [g for g in ROLE_GROUP_RE.findall(text) if "%" not in g]
    # 2026-09-24：候选里只有【至少含一个角色词】的才算角色表。
    # 一个角色词都没有的全角括号组是【普通补注】，例如
    # 「POD（plain old data）类型」「多余的右花括号（'}'）」「VSX 支持（POWER7 或更高版本可用）」。
    # 原先把任何全角括号组都当角色表，于是批量翻译新增的 121 条补注全被判非法 ——
    # 可全角括号本来就是中文排版的正常用法，硬占为角色表专用是过度约束。
    # 这个收窄不会放过「（和）」这类空角色表：它没有角色词 -> 不算角色表 ->
    # 下面 `has_ph and not groups` 照样会以「有占位符却没有角色表」失败。
    groups = []
    for g in cands:
        words = g.split()
        if not any(w in ROLE_WORDS for w in words):
            notes.append("    [补注] 全角括号组（非角色表）: %r" % g)
            continue
        groups.append(g)
        for w in words:
            if w in ROLE_WORDS or w in ROLE_CONNECTORS:
                continue
            problems.append(
                "%s：角色表里有词既不在封闭词表也不在连词表内 -> %r"
                "（词表：%s；连词：%s）"
                % (name, w, "、".join(sorted(ROLE_WORDS)),
                   "、".join(sorted(ROLE_CONNECTORS))))
    has_ph = has_value_placeholder(text)
    if has_ph and not groups:
        # 角色表只认【全角】括号（）。写半角会被判成"缺角色表" —— 失败是响的
        # （2026-09-23 起这一项是硬失败），但原来的报错信息会指向错的方向：
        # 它说"没有角色表"，用户看到的却是自己明明写了 (类型名)。这里把真实
        # 原因一并说出来。这是第四次复核记下的盲点，不是新加的规则。
        hint = ""
        for g in re.findall(r"\(([^()]*)\)", text):
            if "%" in g:
                continue
            if any(w in ROLE_WORDS for w in g.split()):
                hint = ("；你是不是用了半角括号？角色表必须用全角（）—— 发现了 (%s)" % g)
                break
        problems.append(
            "%s：有占位符却没有角色表（一律标是有意选择的统一；"
            "若确实该例外，请写进 .def 并说明理由）%s" % (name, hint))
    return problems, notes


# --------------------------------------------------------------------------
# 五之二、不可翻记号：英文正文里是【代码】的部分，中文正文里必须还在
# --------------------------------------------------------------------------

ZH_KEYWORDS_DEF = os.path.join(TD_DIR, "ChineseKeywords.def")

_KEYWORD_MAP = None


def keyword_cn_map():
    """英文关键字拼写 -> 中文关键字拼写。**从 ChineseKeywords.def 现读**。

    故意不手写这张表：手写的副本一定会和关键字表漂移，
    而这个项目已经栽过三次「两份副本各说各话」。
    """
    global _KEYWORD_MAP
    if _KEYWORD_MAP is not None:
        return _KEYWORD_MAP
    m = {}
    try:
        raw = open(ZH_KEYWORDS_DEF, encoding="utf-8", errors="replace").read()
    except OSError:
        _KEYWORD_MAP = m
        return m
    for line in raw.splitlines():
        mm = re.match(r"\s*ZH_KEYWORD\(\s*(\w+)\s*,\s*(\w+)\s*,", line)
        if mm:
            m[mm.group(1)] = mm.group(2)
            continue
        mm = re.match(r"\s*ZH_VIRT_SPECIFIER\(\s*(\w+)\s*,\s*(\w+)\s*\)", line)
        if mm:
            m[mm.group(1)] = mm.group(2)
            continue
        # ZH_OPERATOR_KEYWORD(并且, ampamp)   // 并且 = and = &&
        mm = re.match(r"\s*ZH_OPERATOR_KEYWORD\(\s*(\w+)\s*,\s*(\w+)\s*\)"
                      r"\s*//[^=]*=\s*(\w+)", line)
        if mm:
            m[mm.group(3)] = mm.group(1)      # 替代记号 and/or/not/... -> 中文
    _KEYWORD_MAP = m
    return m


# 判定「可能是代码」的形状。顺序有意义：先整段吃掉单引号内容，别被后面的规则切碎。
_CODE_PATTERNS = [
    # 开引号前面不能是字母：否则 English 里的所有格/缩写（function's / don't）
    # 会被当成引号开头，跨着一大段散文配对出 "'s / method'" 这种假记号。
    (r"(?<![A-Za-z])'[^']*'", "quoted"),
    (r"__[A-Za-z_]\w*", "dunder"),
    (r"\b[A-Za-z_]\w*(?:::[A-Za-z_]\w*)+", "scoped"),
    (r"\bC(?:\+\+)?\d+[a-z]?\b", "stdver"),
    (r"\bC\+\+", "cpp"),
    (r"(?<![\w-])-{1,2}(?:W|f|m|O|g|std=|pedantic|target)[\w=+.-]*", "flag"),
    (r"\b[A-Za-z_]\w*<[^<>]*>", "template"),
    (r"\b[A-Za-z_]\w*\(\)", "call"),
]
_CODE_RX = [(re.compile(p), k) for p, k in _CODE_PATTERNS]

# 选项开关的形状。单独提出来，因为「加了引号的选项」要按裸选项处理。
_FLAG_RX = re.compile(r"-{1,2}(?:W|f|m|O|g|std=|pedantic|target)[\w=+.-]*")

# 引号里带【占位符】的不算代码记号：'%1' 里的引号是排版，占位符本身由
# check_zh 管。但 '%%P' 里的 %% 是转义、是真代码，必须留下 —— 差别就在
# 后面跟的是不是数字。
_QUOTED_PLACEHOLDER = re.compile(r"%[a-zA-Z]*\d")

# 引号里若是 %select/%plural/%diff，整段也不能当「必须逐字保留的代码记号」——
# 分支本身就是要翻的文本，引号只是排版；它的结构由 check_zh 的分支指纹管。
# 2026-09-24：批量翻译时 5 条 `'%select{if|switch}0'` 撞出来的矛盾 ——
# 门禁逼着把英文分支原样留下，而那正是最该翻的部分。
_QUOTED_SELECTOR = re.compile(r"%(?:select|plural|selectordinal|diff)\{")

# 引号里若是【描述性英文短语】而不是代码，就不该当记号要求逐字保留。
# 例：'variable length array in structure' 是扩展的名字，中文写
# 「结构体中的变长数组」是合理的，硬要求保留英文反而错。
# 判据：≥4 个空格分隔的纯字母单词，且不含任何代码标点。
_PROSE_QUOTED = re.compile(r"^[A-Za-z]+(?: [A-Za-z]+){3,}$")


def protect_tokens(text):
    """抽出必须原样出现在中文里的记号。返回 [(token, kind)]，去重保序。

    早先版本的连字符规则写成 -[A-Za-z]...，把英语连字符词也当成了选项
    （non-type -> -type、multi-line -> -line），会逼着人往中文里塞英文单词。
    现在只认 -W / -f / -m / -O / -g / -std= / -pedantic / --target 这些真前缀。

    2026-09-24 又修两处（都是批量翻译时被门禁自己的误报逼出来的）：

    1. **引号内容首尾带空白的一律丢弃。** 英文诊断里会出现 `''{...}'` 这种
       相邻引号，`'[^']*'` 会跨着一大段散文配对，产出
       `' are expressions with scalar type, and '` 这种根本不是记号的"记号"。
       代码记号不会有内边距，所以按首尾空白一刀切，干净且不误伤。
    2. **加了引号的选项按裸选项处理。** 英文写 `'-fno-rtti'`，中文按项目约定写
       `（选项） -fno-rtti`（gold 的 `传入（选项） -fenable-matrix 以启用` 就没有引号）。
       如果按带引号的记号要求，就会逼着写成 `（选项） '-fno-rtti'`，很别扭。
    """
    taken = [False] * len(text)

    def free(a, b):
        return not any(taken[a:b])

    out = []
    for rx, kind in _CODE_RX:
        for m in rx.finditer(text):
            a, b = m.span()
            if not free(a, b):
                continue
            tok = m.group(0)
            if kind == "quoted":
                inner = tok[1:-1]
                if not inner.strip():
                    continue                  # '' 空引号，不是记号
                if inner != inner.strip():
                    continue                  # 首尾有空白 -> 跨散文配对，不是记号
                if _QUOTED_PLACEHOLDER.search(tok):
                    continue                  # '%1' 里的引号是排版，占位符归 check_zh 管
                if _QUOTED_SELECTOR.search(tok):
                    continue                  # 引号里的 %select 分支是要翻的正文
                if _PROSE_QUOTED.match(inner):
                    continue                  # 描述性英文短语，不是代码记号
            for i in range(a, b):
                taken[i] = True
            tok = tok.strip().rstrip(".,;:")
            if tok:
                out.append((tok, kind))

    # 后处理：带引号的选项统一按【裸选项】算。
    # 放在这里而不是上面那个分支里，是因为分支里做会遇到"同一段文字被
    # 两个模式各匹配一次"的先后顺序问题 —— 实测同一句里的两个选项，
    # 一个转成了一个没转。收口到一处，与匹配顺序无关。
    fixed = []
    for tok, kind in out:
        if kind == "quoted" and len(tok) > 2 and _FLAG_RX.fullmatch(tok[1:-1]):
            fixed.append((tok[1:-1], "flag"))
        else:
            fixed.append((tok, kind))
    return sorted(set(fixed))


# 少数条目引号里装的是【别的语言/DSL 的记号】，只是拼写碰巧和 C++ 关键字一样
# —— OpenMP/OpenACC 的子句名、map 类型取值、构造名。用户在 pragma 里必须
# 原样敲英文，所以这些【必须保留英文】，不能套「（关键字） 中文关键字」。
#
# 这是一份**显式名单**，不是启发式：机器判断不出「这个词在这里是不是关键字」，
# 宁可由人过目后写死。这批全部 217 处「引号内是关键字」的出现点已逐条过目
# （见 build\_p_kw_audit.txt），只有下面 6 处属于这一类。
KW_IS_DSL_TOKEN = {
    "err_acc_invalid_default_clause_kind": {"'default'"},   # OpenACC 子句名
    "err_omp_no_more_if_clause":           {"'if'"},        # OpenMP 子句名
    "err_omp_unknown_map_type":            {"'delete'"},    # map 类型取值
    "err_omp_wrong_cancel_region":         {"'for'"},       # OpenMP 构造名
    "warn_acc_if_self_conflict":           {"'if'"},        # OpenACC 子句名
    "warn_omp_default_deprecated":         {"'default'"},   # OpenMP 子句名
}


def check_protected_tokens(name, en, zh):
    """中文里必须保住英文正文里的代码记号。返回问题列表。

    【关键字】是唯一的例外，而且是有方向的例外：2026-09-24 用户裁定，
    诊断里提到的关键字一律写【中文关键字拼写】并前置 `（关键字） `，
    不放 `'typename'` 这种英文原拼写。理由是这是汉语编译器 ——
    用户敲进去的就是 `类型名`，诊断不该告诉他一个他不需要敲的词。
    实测 `自身` / `静态转换<int*>` / `[自身]` / `常量表达式` / `静态断言` 均可编译。

    这条规则原先在表里是矛盾的：6 处中文拼写，3 处英文拼写，其中两条诊断
    说的是同一句话（「改用 static_cast」），一条 `（关键字） 静态转换`、
    一条 `'static_cast'`。所以这里不是"两者皆可"，而是必须中文。
    关键字名单从 ChineseKeywords.def 现读，不手写。

    例外中的例外是 KW_IS_DSL_TOKEN：那几处引号里是别的 DSL 的记号，
    必须原样保留英文。
    """
    problems = []
    kw = keyword_cn_map()
    dsl = KW_IS_DSL_TOKEN.get(name, frozenset())
    for tok, _kind in protect_tokens(en):
        if tok in dsl:
            # 这是 DSL 记号，不是 C++ 关键字：必须原样保留英文
            if tok not in zh:
                problems.append(
                    "%s：%r 是别的语言的记号（不是 C++ 关键字），必须原样保留英文\n"
                    "      英文 %s\n      中文 %s" % (name, tok, en, zh))
            continue

        bare = tok[1:-1] if tok.startswith("'") and tok.endswith("'") else None
        cn = kw.get(bare) if bare else None

        if cn:
            # 约定是「（关键字） 中文关键字」，所以要求【整对】都在。
            # 只查「中文关键字在不在这段文字里」是不够的：`typename` 的中文是
            # `类型名`，而 `依赖类型名` 里就含这个子串 —— 于是把关键字整个删掉
            # 也能蒙混过关。写自检时正是这条用例（「关键字既没译也没留」）
            # 暴露了这个假通过。
            want = "（关键字） " + cn
            if want in zh:
                continue
            if tok in zh:
                problems.append(
                    "%s：关键字 %r 必须用中文拼写，写成 %r，不能保留英文原拼写\n"
                    "      英文 %s\n      中文 %s" % (name, tok, want, en, zh))
            else:
                problems.append(
                    "%s：关键字 %r 要写成 %r\n      英文 %s\n      中文 %s"
                    % (name, tok, want, en, zh))
            continue

        if tok in zh:
            continue
        problems.append(
            "%s：中文里丢了英文正文里的代码记号 %r\n      英文 %s\n      中文 %s"
            % (name, tok, en, zh))
    return problems


def check_percent_escapes(name, en, zh):
    """%% 是【字面百分号】的转义，数量必须一致。返回问题列表。

    为什么单独一条：%% 不是「代码记号」的任何一种形状，protect_tokens 抓不到它
    （写入自检时就撞出来了 —— 「%% 转义丢了」那条用例实际通过）。
    译文里漏掉一个 % 会让输出少一个字面 %；多写一个会让格式化器把它当成
    占位符开头。少写已经被 check_zh 的畸形转义检查兜住，漏写只有这里能抓。

    中文里该写全角「％」还是 `%%`：跟英文一样写 %% —— 那是输出内容，不是排版。
    """
    problems = []
    if en.count("%%") != zh.count("%%"):
        problems.append(
            "%s：%%%% 转义数量对不上（英文 %d 个，中文 %d 个）\n      英文 %s\n      中文 %s"
            % (name, en.count("%%"), zh.count("%%"), en, zh))
    return problems


# `（关键字） X` 里 X 的字符类。
# 必须排除 `{ } |`：写成 %select{…|（关键字） 新建}0 时，`}0` 会被一起吃进来，
# 于是报「'新建}0' 不在关键字表里」—— 那是排版问题，不是译错。
# 也排除引号和 `%`：`（关键字） '%0'` 是动态关键字（运行时才知道是哪个），
# 静态判不了，直接不捕获取。
# 只定义这一份，检查器和 build\_r_fixkw.py 共用 —— 这个项目已经栽过三次
# 「两份副本各说各话」。
KEYWORD_MARKER_RE = re.compile(
    r"（关键字）\s*([^\s（），。；：、？！…—{}|'\"%]+)")


def check_keyword_markers(name, en, zh):
    """`（关键字） ` 只能标在英文【加了引号】的关键字上。返回问题列表。

    为什么要有这条：批量翻译时有 88 处把**裸提及**也标成了 `（关键字） `，
    例如 `using declaration` → `（关键字） 使用 声明`、`declared static` →
    `声明为（关键字） 静态`。这些词在英文里是**普通散文**，不是"被指称的关键字"。

    gold 先例是决定性的：`class member cannot be redeclared` →
    `类中成员不能被重新声明` —— 裸的 `class` 当普通名词译成「类」，
    而不是关键字拼写「类型」。同理 `by default` 里的 `default` 显然也不该标。

    判据：中文里每处 `（关键字） X`，都能在关键字表里把 X 反查成英文拼写，
    且英文正文里确实有 `'那个拼写'`。
    """
    kw = keyword_cn_map()
    cn2en = {}
    for e, c in kw.items():
        cn2en.setdefault(c, set()).add(e)

    problems = []
    # `|` 也必须排除：%select/%plural 的分支分隔符不是正文。不排除时
    # `（关键字） 自动|'decltype(auto)'|...` 会把整段分支吃进"关键字"里，
    # 于是每个分支里出现一次的关键字都会被误判成"不在关键字表里"。
    for m in KEYWORD_MARKER_RE.finditer(zh):
        cn = m.group(1)
        ens = cn2en.get(cn)
        if not ens:
            problems.append(
                "%s：`（关键字） %s` 里的「%s」不在关键字表里\n      英文 %s\n      中文 %s"
                % (name, cn, cn, en, zh))
            continue
        if any(("'%s'" % e) in en for e in ens):
            continue
        problems.append(
            "%s：英文里没有加引号的关键字（%s），裸提及不该标 `（关键字） `\n"
            "      英文 %s\n      中文 %s"
            % (name, "/".join("'%s'" % e for e in sorted(ens)), en, zh))
    return problems


def check_table(inc, zh=None, raw=None):
    """校核整张中文表。返回 (报告行, 问题列表, 条目列表)。

    问题 = 一定要修（ID 不存在、占位符对不上、分支顺序对不上…）。
    报告行里还会列出"中文正文里混着英文词"的条目 —— 那**不一定**是错的
    （';' 与 'typename' 这种代码里的词就该保留），所以只报告、不判失败，
    由人确认。这一类正是独立复核者找出的 F3（`未使用的 typedef`）。

    **为什么要单独查"规模"和"收尾标记"**：逐条检查天然抓不到"表被改小"——
    条目少了，剩下的条目依然条条合法，于是校核器报 0 问题、退出码 0。
    独立复核者 2026-09-22 实测：把表砍到只剩 7 条（真表 32 条），
    `--check-table` 仍然静默通过（它的反例 A）。所以这里必须另外断言。
    """
    if zh is None:
        zh = parse_zh_def()
    if raw is None:
        try:
            raw = open(ZH_DEF, encoding="utf-8", errors="replace").read()
        except OSError:
            raw = ""
    lines, problems, seen = [], [], set()

    # ---- 结构性检查（防截断/防误删）--------------------------------------
    if not raw:
        problems.append("读不到中文表：%s" % ZH_DEF)
    else:
        if "#ifndef ZH_DIAG" not in raw:
            problems.append("表头缺少 `#ifndef ZH_DIAG` 守卫 —— 文件可能被改坏了")
        if "#undef ZH_DIAG" not in raw:
            problems.append("表尾缺少 `#undef ZH_DIAG` —— 文件很可能被截断了")
    if len(zh) < MIN_ENTRIES:
        problems.append(
            "表里只有 %d 条，少于下限 %d —— 被截断或被误删？"
            "（确实要减少条目时，请同时改 tools/diag_id_lookup.py 里的 MIN_ENTRIES，"
            "并在 docs\诊断汉化\诊断汉化清单.md 写明原因）"
            % (len(zh), MIN_ENTRIES))

    # 2026-09-24 起成立的一条更强的保证：**凡是有英文正文的诊断，都必须在表里**。
    # 在此之前只能靠 tests\12-diagnostics\10_fallback_english.cpp 挑一条"还没翻的"
    # 来观测回退路径 —— 而那个用例每加一批就失效一次（换过三次，最后一次无条可换）。
    # 改成表级断言后，它不会随着覆盖率上升而失效。
    # 白名单是 `"%0"` 这类直通条目：正文由后端给，本来就没有英语可翻。
    missing = []
    have = {n for n, _t, _l in zh}       # 直接用 zh 建集合：不要依赖 seen 的填充时机
    for _n, (_en, _sev, _line) in inc.items():
        if _n in have:
            continue
        if re.search(r"[A-Za-z]", re.sub(r"%[a-zA-Z]*\d+", "", _en)):
            missing.append(_n)
    if missing:
        problems.append(
            "有 %d 个诊断【有英文正文却不在中文表里】：%s%s"
            % (len(missing), "、".join(sorted(missing)[:10]),
               " …" if len(missing) > 10 else ""))

    for name, text, line in zh:
        if name in seen:
            problems.append("%s：重复条目（第 %d 行）" % (name, line))
        seen.add(name)
        p, en = check_zh(name, text, inc)
        problems.extend(p)
        rp, rn = check_role_table(name, text)
        problems.extend(rp)
        lines.extend(rn)
        if en is not None:
            problems.extend(check_protected_tokens(name, en, text))
            problems.extend(check_percent_escapes(name, en, text))
            problems.extend(check_keyword_markers(name, en, text))
            lines.append("")
            lines.append("  %s  (第 %d 行)" % (name, line))
            lines.append("    英文: %s" % en)
            lines.append("    中文: %s" % text)
        res = ascii_residue(text)
        if res:
            lines.append("    [待确认] 中文正文里的英文词: %s" % "、".join(res))
    return lines, problems, zh


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-corpus", action="store_true")
    ap.add_argument("--check-table", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    inc = parse_inc()
    if args.self_test:
        bad = self_test(inc)
        if bad:
            print("SELF-TEST FAILED:")
            for b in bad:
                print("  " + b.encode("ascii", "replace").decode("ascii"))
            return 1
        print("SELF-TEST OK: validator catches all planted errors")
        return 0
    td = parse_td()
    lines = []

    def say(s=""):
        lines.append(s)

    say("诊断反查报告（生成表 = 权威）")
    say("=" * 78)
    say("生成表 .inc：%d 条" % len(inc))
    say("源表   .td ：%d 条" % len(td))
    only_inc = sorted(set(inc) - set(td))
    say("只在 .inc 里、.td 找不到名字的：%d 条（多为 multiclass 实例化）" % len(only_inc))
    sub_names = [n for n in inc if n in td and inc[n][0] != td[n][0]]
    say("源表与生成表文字不同的：%d 条（%%sub / %%enum_select 被展开的结果）" % len(sub_names))
    say("  例：%s" % "、".join(sub_names[:4]))
    say()

    zh = parse_zh_def()
    say("中文表 ChineseDiagnostics.def：%d 条" % len(zh))
    tbl_lines, problems, _ = check_table(inc, zh)
    say("（已覆盖全部 %d 条内置诊断的 %.2f%%）" % (len(inc), 100.0 * len(zh) / max(1, len(inc))))
    for l in tbl_lines:
        say(l)
    say()
    if problems:
        say("❌ 校核不通过（%d 个问题）：" % len(problems))
        for p in problems:
            say("  - %s" % p)
    else:
        say("✅ 中文表校核通过：ID 都存在，占位符与英文一致")

    if not args.check_table and not args.no_corpus:
        say()
        say("=" * 78)
        compiled = []
        for name, (msg, src, line) in inc.items():
            try:
                compiled.append((name, re.compile("^" + template_to_regex(msg) + "$")))
            except re.error:
                pass
        msgs = run_corpus()
        say("实测诊断：%d 条（去重后 %d 条）" % (len(msgs), len(set(m[2] for m in msgs))))
        say("=" * 78)
        for frag, sev, msg in msgs:
            hits = [n for (n, rx) in compiled if rx.match(msg)]
            say("")
            say("[%s] %s: %s" % (frag, sev, msg))
            if len(hits) == 1:
                n = hits[0]
                tdsrc = "%s:%d" % (td[n][1], td[n][2]) if n in td else "（.td 里没有）"
                say("   -> %s   [%s:%d]   源 %s" % (n, inc[n][1], inc[n][2], tdsrc))
                say("   英文模板（抄这个翻）: %s" % inc[n][0])
            elif not hits:
                say("   -> 无命中")
            else:
                say("   -> %d 个候选: %s" % (len(hits), " | ".join(hits[:8])))

    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("diag table: %d entries, %d problems -> %s"
          % (len(zh), len(problems), REPORT))
    for p in problems:
        first = p.splitlines()[0]
        print("  PROBLEM: " + first.encode("ascii", "replace").decode("ascii"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
