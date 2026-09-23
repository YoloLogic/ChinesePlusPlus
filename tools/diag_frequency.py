#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""量真实频次：拿一大片真实代码编一遍，统计**哪条诊断实际出现得最多**。

这是《汉字第一公民-路线图》第 4 步。目的只有一个：
**决定下一批该翻哪些句子** —— 不是按数量平均翻，而是按真实出现频率翻。

做法：
  1. 收集一堆真实源文件（默认 clang/test 下的 .c/.cpp，那里全是"真实会写错的代码"）
  2. 用我们的 chinese++.exe 逐个 -fsyntax-only 编一遍，抓诊断正文
  3. 用 diag_id_lookup 的模板反查回诊断 ID
  4. 按 ID 统计次数，输出排名 + 英文样例

注意（诚实说明，别把结论说大）：
  * 这是"**编译真实代码**得到的频次"，不是"人写代码时的犯错频次"。
    clang/test 里的代码是编译器开发者写的**边界用例**，会高估冷门诊断。
  * 但它是**可复现的真实测量**，比拍脑袋强；等有了真实项目语料再校正。
  * 用它做**下界**判断最稳妥：排名靠前的，一定是真会出现的。

用法：
  python tools/diag_frequency.py                      # 默认语料
  python tools/diag_frequency.py --limit 300 --jobs 12
  python tools/diag_frequency.py --dir E:\some\project --extra "-Wall -Wextra"
"""

import argparse
import collections
import glob
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import diag_id_lookup as d  # noqa: E402

CLANGXX = os.path.join(ROOT, "build", "Release", "bin", "chinese++.exe")
REPORT = os.path.join(ROOT, "build", "_diag_freq.txt")

DEFAULT_DIRS = [
    os.path.join(ROOT, "LLVM-main", "clang", "test"),
]
DEFAULT_INCLUDES = [
    os.path.join(ROOT, "LLVM-main", "clang", "test"),
    os.path.join(ROOT, "LLVM-main", "clang", "include"),
    os.path.join(ROOT, "LLVM-main", "llvm", "include"),
    os.path.join(ROOT, "build", "include"),
    os.path.join(ROOT, "build", "tools", "clang", "include"),
]

DIAG_LINE = re.compile(
    r"^(.*?):\s*(error|warning|note|remark|fatal error):\s*(.*?)(?:\s*\[-W[\w\-\+=,]+\])?\s*$"
)

# 这些不是"内容诊断"，统计进来会污染排名
IGNORE_IDS = {
    "err_expected",            # 单独看没意义，到处都是
    "err_expected_semi_declaration",
}


def collect(dirs, exts, limit):
    out = []
    for base in dirs:
        if not os.path.isdir(base):
            continue
        for ext in exts:
            out.extend(glob.glob(os.path.join(base, "**", "*." + ext), recursive=True))
    out = sorted(set(out))
    if limit and len(out) > limit:
        step = len(out) / float(limit)
        out = [out[int(i * step)] for i in range(limit)]
    return out


def compile_one(path, extra, includes):
    cmd = [CLANGXX, "-fsyntax-only", "-fno-caret-diagnostics",
           "-fno-diagnostics-fixit-info", "-fno-color-diagnostics",
           "-ferror-limit=0"]
    cmd += ["-I" + p for p in includes]
    # 按扩展名给对语言，否则 .c 会被当成 C++ 编，
    # 平白多出一堆 warn_drv_treating_input_as_cxx（那是我们调用的锅，不是代码的锅）
    ext = os.path.splitext(path)[1].lower()
    if ext == ".c":
        cmd += ["-x", "c"]
    cmd += extra
    cmd.append(path)
    try:
        p = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                           timeout=120)
    except subprocess.TimeoutExpired:
        return []
    msgs = []
    for line in p.stderr.decode("utf-8", errors="replace").splitlines():
        m = DIAG_LINE.match(line)
        if m:
            msgs.append((m.group(2), m.group(3).strip()))
    return msgs


# 驱动自身/环境造成的诊断，与"用户代码写错了"无关，统计进来会污染排名
NOISE_ID_PREFIX = ("warn_drv_", "err_drv_", "err_fe_")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", action="append", default=[])
    ap.add_argument("--ext", default="c,cpp,cc,cxx")
    ap.add_argument("--limit", type=int, default=400)
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--extra", default="-Wall")
    args = ap.parse_args()

    dirs = args.dir or DEFAULT_DIRS
    files = collect(dirs, args.ext.split(","), args.limit)
    if not files:
        print("no source files found under: %s" % ", ".join(dirs))
        return 1

    inc = d.parse_inc()
    compiled = []
    for name, (msg, _src, _line) in inc.items():
        try:
            compiled.append((name, re.compile("^" + d.template_to_regex(msg) + "$")))
        except re.error:
            pass
    # 已经翻成中文的条目：中文输出也必须能反查回同一个 ID。
    # 否则它们会整批掉进"未能反查"那一堆 —— 实测踩过：第一批上线后，
    # 出现次数最多的一条（使用了未声明的标识符，552 次）就被藏在那里，
    # 排名表看起来像是"英文诊断最常出现"，完全是假象。
    for name, text, _line in d.parse_zh_def():
        try:
            compiled.append((name, re.compile("^" + d.template_to_regex(text) + "$")))
        except re.error:
            pass

    extra = args.extra.split() if args.extra else []
    print("corpus: %d files   extra args: %s   jobs: %d"
          % (len(files), args.extra or "(none)", args.jobs))

    # 先建模板索引（一次性），再并行编译
    per_id = collections.Counter()
    per_id_sample = {}
    unmatched = collections.Counter()
    sev_of = {}
    done = 0

    def work(path):
        return path, compile_one(path, extra, DEFAULT_INCLUDES)

    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for path, msgs in ex.map(work, files):
            done += 1
            if done % 50 == 0:
                print("  ... %d/%d" % (done, len(files)))
            for sev, msg in msgs:
                hits = [n for (n, rx) in compiled if rx.match(msg)]
                if len(hits) == 1 and not hits[0].startswith(NOISE_ID_PREFIX):
                    per_id[hits[0]] += 1
                    sev_of.setdefault(hits[0], sev)
                    per_id_sample.setdefault(hits[0], msg)
                elif len(hits) != 1:
                    unmatched[msg] += 1

    lines = []
    lines.append("诊断真实频次报告（编译 %d 个真实文件得到）" % len(files))
    lines.append("额外参数: %s" % (args.extra or "(none)"))
    lines.append("=" * 78)
    total = sum(per_id.values())
    lines.append("识别出的诊断实例: %d 条，涉及 %d 个诊断 ID" % (total, len(per_id)))
    lines.append("")
    lines.append("%-6s %-5s %-42s %s" % ("次数", "等级", "诊断 ID", "英文样例"))
    lines.append("-" * 78)
    for name, cnt in per_id.most_common(60):
        lines.append("%-6d %-5s %-42s %s"
                     % (cnt, sev_of.get(name, "?")[:5], name,
                        per_id_sample.get(name, "")[:60]))

    lines.append("")
    lines.append("=" * 78)
    lines.append("未能反查到的消息（前 30，通常是 note 或模板含 %sub 之外的形态）")
    lines.append("-" * 78)
    for msg, cnt in unmatched.most_common(30):
        lines.append("%-6d %s" % (cnt, msg[:90]))

    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("")
    for l in lines[:40]:
        print(l.encode("ascii", "replace").decode("ascii"))
    print("")
    print("full report (UTF-8): %s" % REPORT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
