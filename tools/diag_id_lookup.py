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
MIN_ENTRIES = 42
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
    if zh_bad:
        problems.append("%s：中文里有畸形的 %% 转义" % name)
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
    return bad


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

    for name, text, line in zh:
        if name in seen:
            problems.append("%s：重复条目（第 %d 行）" % (name, line))
        seen.add(name)
        p, en = check_zh(name, text, inc)
        problems.extend(p)
        if en is not None:
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
