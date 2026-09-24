#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""用**真实开源项目**的编译命令量覆盖率（校准 diag_coverage.py 的语料偏差）。

为什么需要这个
==============
`tools\diag_coverage.py` 的语料是 `clang/test` —— 那是**编译器开发者写的边界用例**，
不是典型用户代码。所以那个 77.8% 可能偏乐观，也可能偏悲观，没有依据。
这里换成语料：拿 third_party\ 下真实开源项目的 **compile_commands.json**，
**按项目自己的编译命令**重放，量同一件事。

命令怎么重放
============
  1. 程序员原样保留（-I -D -std -W… 全是项目真实使用的）
  2. **编译器只换目录、不换名字**：`...\bin\clang.exe` -> `E:\Chinese++\build\Release\bin\clang.exe`
     为什么不换成 chinese++.exe：**C 文件必须用 C 驱动**。chinese++.exe 是 clang++ 的
     硬链接，把 `.c` 当 C++ 编，会凭空产生一大堆假报错。
     诊断表在 clang/lib/Basic/Diagnostic.cpp 里，两个驱动共用，所以用我们的 clang.exe
     量的就是同一张中文表。
  3. 去掉 -c / -o / -MF / -MT / -MQ / -MD / -MMD，加 -fsyntax-only（只看诊断，不落目标文件）

口径与 diag_coverage.py 完全一致：**正文含汉字 = 已覆盖**。

用法
====
  python tools\diag_coverage_projects.py --db third_party\build\libuv-ours\compile_commands.json
  python tools\diag_coverage_projects.py --db a.json --db b.json --jobs 12
"""

import argparse
import collections
import json
import os
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import diag_id_lookup as d          # noqa: E402
import diag_frequency as freq       # noqa: E402

REPORT = os.path.join(ROOT, "build", "_diag_coverage_projects.txt")
OUR_BIN = os.path.join(ROOT, "build", "Release", "bin")
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")

# 只看诊断，不产出目标文件；这些参数由我们接管或必须去掉
DROP_FLAGS = {"-c", "-o", "-MF", "-MT", "-MQ", "-MD", "-MMD"}


def build_argv(cmd):
    """把项目原始命令改造成一条 -fsyntax-only 的只读编译。"""
    toks = [t.strip('"') for t in shlex.split(cmd, posix=False)]
    out = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if i == 0:
            # 编译器：只换目录，保留 basename（clang.exe / clang++.exe）
            base = os.path.basename(t.replace("/", os.sep))
            out.append(os.path.join(OUR_BIN, base))
            i += 1
            continue
        if t in DROP_FLAGS:
            i += 2 if t in ("-o", "-MF", "-MT", "-MQ") else 1
            continue
        if t.startswith("-o") and len(t) > 2:      # -ofoo
            i += 1
            continue
        out.append(t)
        i += 1
    out.insert(1, "-fsyntax-only")
    return out


def run_one(entry):
    argv = build_argv(entry["command"])
    try:
        p = subprocess.run(argv, cwd=entry.get("directory") or ROOT,
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=180)
    except (subprocess.TimeoutExpired, OSError):
        return []
    msgs = []
    for line in p.stderr.decode("utf-8", errors="replace").splitlines():
        m = freq.DIAG_LINE.match(line)
        if m:
            msgs.append((m.group("sev"), m.group("msg").strip(), m.group("loc").strip()))
    return msgs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", action="append", required=True)
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--limit", type=int, default=0, help="每个 db 最多取多少条（0=全部）")
    args = ap.parse_args()

    entries = []
    per_db = []
    for path in args.db:
        full = path if os.path.isabs(path) else os.path.join(ROOT, path)
        db = json.load(open(full, encoding="utf-8"))
        if args.limit:
            db = db[:args.limit]
        per_db.append((os.path.basename(os.path.dirname(full)), len(db)))
        entries.extend(db)

    # 反查表（英文 + 中文模板）
    compiled, zh_ids = [], set()
    for name, (msg, _s, _l) in d.parse_inc().items():
        try:
            compiled.append((name, re.compile("^" + d.template_to_regex(msg) + "$")))
        except re.error:
            pass
    for name, text, _l in d.parse_zh_def():
        zh_ids.add(name)
        try:
            compiled.append((name, re.compile("^" + d.template_to_regex(text) + "$")))
        except re.error:
            pass

    allc, per_sev = {"n": 0, "cjk": 0}, collections.defaultdict(lambda: {"n": 0, "cjk": 0})
    left = collections.Counter()
    left_ids = {}
    bug = []
    done = 0
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for msgs in ex.map(run_one, entries):
            done += 1
            if done % 100 == 0:
                print("  ... %d/%d" % (done, len(entries)))
            for sev, msg, _loc in msgs:
                is_cjk = bool(CJK.search(msg))
                for c in (allc, per_sev[sev]):
                    c["n"] += 1
                    c["cjk"] += is_cjk
                if is_cjk:
                    continue
                key = re.sub(r"'[^']*'", "'…'", msg)
                key = re.sub(r"\s+", " ", key).strip()
                left[key] += 1
                if key not in left_ids:
                    hits = [n for (n, rx) in compiled if rx.match(msg)]
                    left_ids[key] = hits or None
                    if len(hits) == 1 and hits[0] in zh_ids:
                        bug.append((hits[0], msg))

    def pct(a, b):
        return "%5.1f%%" % (100.0 * a / b) if b else "   n/a"

    L = []
    L.append("诊断覆盖率报告 —— 语料：真实开源项目（按项目自己的编译命令重放）")
    for name, cnt in per_db:
        L.append("  %-24s %d 条编译命令" % (name, cnt))
    L.append("=" * 78)
    L.append("  诊断实例总数      : %d" % allc["n"])
    L.append("  其中正文含汉字    : %d" % allc["cjk"])
    L.append("  覆盖率            : %s   (%d/%d)"
             % (pct(allc["cjk"], allc["n"]), allc["cjk"], allc["n"]))
    L.append("")
    L.append("按等级：")
    for sev in ("fatal error", "error", "warning", "note", "remark"):
        c = per_sev.get(sev)
        if c and c["n"]:
            L.append("  %-12s %5d / %-5d = %s" % (sev, c["cjk"], c["n"], pct(c["cjk"], c["n"])))
    L.append("")
    L.append("[自检] 正文是英文却反查到「表里已有」的 ID: %d 条 %s"
             % (len(bug), "(OK)" if not bug else "(BUG)"))
    for n, m in bug[:10]:
        L.append("    %s  <-  %s" % (n, m[:70]))
    L.append("")
    L.append("=" * 78)
    L.append("未覆盖的实例（按正文归并，前 30）")
    L.append("  次数  诊断 ID（多个用 | 分隔）                正文")
    L.append("-" * 78)
    for key, cnt in left.most_common(30):
        ids = left_ids.get(key)
        tag = "|".join(ids) if ids else "(匹配不上)"
        L.append("  %-5d %-38s %s" % (cnt, tag[:38], key[:48]))
    L.append("")
    by_id = collections.Counter()
    for key, cnt in left.items():
        ids = left_ids.get(key)
        if ids and len(ids) == 1:
            by_id[ids[0]] += cnt
    L.append("未覆盖里【ID 唯一】的按 ID 排名（前 25）：")
    for name, cnt in by_id.most_common(25):
        L.append("  %-5d %s" % (cnt, name))
    L.append("  合计 %d 条 / %d 个 ID" % (sum(by_id.values()), len(by_id)))

    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")

    print("")
    for l in L[:14]:
        print(l.encode("ascii", "replace").decode("ascii"))
    print("")
    print("full report (UTF-8): %s" % REPORT)
    return 2 if bug else 0


if __name__ == "__main__":
    sys.exit(main())
