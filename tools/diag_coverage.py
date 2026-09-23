#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""B1：不碰编译器，直接量「用户真正看到多少中文报错」。

口径
====
    覆盖率 = 正文含汉字的诊断实例数 / 诊断实例总数

为什么这个口径**不需要**把消息反查回诊断 ID
============================================
中文表按 ID 查：命中就整句渲染成中文，没命中就整句英文（回退）。
所以「这句是不是中文」就是「这条有没有被翻」的**直接观测**，
不必经过「英文文本 -> ID」这一步 —— 也就没有反查失败那一堆的洞。

代价要说清楚：这个口径能回答「覆盖了多少」，**不能**回答「下一批该翻哪个 ID」。
后者靠 tools\diag_frequency.py（按 ID 排名）。本工具只用反查来**给未覆盖的
实例贴上 ID 标签**，贴不上不影响覆盖率的计算。

两个切法
========
  · 全部实例          —— 用户看到的每一条
  · 有源码位置的实例  —— 排除「clang: error: ...」这类驱动自身的消息
    （驱动的消息没有 文件:行:列，用它当判据，不需要知道 ID）

自带两条自检（不靠眼睛）
========================
  自检 1：中文表每一条渲染出来都必须含汉字 —— 否则那一条会被本口径误判成"没翻"。
  自检 2：正文是英文、却能唯一反查到**表里已经存在**的 ID
          —— 那是「表里有、却没渲染成中文」，属于 bug，必须报 0 条。

用法
====
  python tools\diag_coverage.py                     # 默认语料，-Wall
  python tools\diag_coverage.py --extra "-Wall -Wextra"
"""

import argparse
import collections
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import diag_id_lookup as d          # noqa: E402
import diag_frequency as freq       # noqa: E402

REPORT = os.path.join(ROOT, "build", "_diag_coverage.txt")

# 汉字（CJK 统一表意文字，含扩展 A）。中文表里每一条都至少有一个，
# 由自检 1 保证 —— 这个假设是被验证的，不是被假设的。
CJK = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")

# 驱动自身的消息没有 文件:行[:列]，用这个判据把它们摘出去，不需要知道 ID。
HAS_LOC = re.compile(r":\d+(:\d+)?$")


def pct(a, b):
    return "%5.1f%%" % (100.0 * a / b) if b else "   n/a"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", action="append", default=[])
    ap.add_argument("--ext", default="c,cpp,cc,cxx")
    ap.add_argument("--limit", type=int, default=400)
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--extra", default="-Wall")
    args = ap.parse_args()

    dirs = args.dir or freq.DEFAULT_DIRS
    files = freq.collect(dirs, args.ext.split(","), args.limit)
    if not files:
        print("no source files found under: %s" % ", ".join(dirs))
        return 1

    # ---- 自检 1：中文表每条都必须含汉字 -------------------------------
    zh = d.parse_zh_def()
    no_cjk = [(n, t) for (n, t, _l) in zh if not CJK.search(t)]
    self1_ok = not no_cjk

    # ---- 反查表：模板 -> ID（英文 + 中文两套都编进去）------------------
    compiled = []
    inc = d.parse_inc()
    for name, (msg, _src, _line) in inc.items():
        try:
            compiled.append((name, re.compile("^" + d.template_to_regex(msg) + "$")))
        except re.error:
            pass
    zh_ids = set()
    for name, text, _line in zh:
        zh_ids.add(name)
        try:
            compiled.append((name, re.compile("^" + d.template_to_regex(text) + "$")))
        except re.error:
            pass

    extra = args.extra.split() if args.extra else []
    print("corpus: %d files   extra: %s   jobs: %d" % (len(files), args.extra, args.jobs))

    def zero():
        return {"n": 0, "cjk": 0}

    allc, locc = zero(), zero()
    per_sev = collections.defaultdict(zero)
    left = collections.Counter()        # 归并正文 -> 次数
    left_ids = {}                       # 归并正文 -> (单个 ID) / (多个 ID 的字符串) / None
    bug = []                            # 自检 2

    done = 0
    for path in files:
        for sev, msg, loc in freq.compile_one_full(path, extra, freq.DEFAULT_INCLUDES):
            is_cjk = bool(CJK.search(msg))
            has_loc = bool(HAS_LOC.search(loc))
            for c in (allc, per_sev[sev]):
                c["n"] += 1
                c["cjk"] += is_cjk
            if has_loc:
                locc["n"] += 1
                locc["cjk"] += is_cjk
            if is_cjk:
                continue
            # 未覆盖：归并（把 'xxx' 形式的引号内容换成 '…'）
            key = re.sub(r"'[^']*'", "'…'", msg)
            key = re.sub(r"\s+", " ", key).strip()
            left[key] += 1
            if key not in left_ids:
                hits = [n for (n, rx) in compiled if rx.match(msg)]
                left_ids[key] = hits or None
                # 自检 2 只在【唯一匹配】时才成立。err_expected 的英文
                # "expected %0" 泛到会把 "expected expression"（其实属于
                # err_expected_expression）也匹配上 —— 不要求唯一就是假阳性，
                # 这条检查自己踩过一次，写在这里免得下次又踩。
                if len(hits) == 1 and hits[0] in zh_ids:
                    bug.append((hits[0], msg, path))
        done += 1
        if done % 50 == 0:
            print("  ... %d/%d" % (done, len(files)))

    n_left = sum(left.values())
    # 未覆盖实例按"能不能贴上 ID"分三类 —— 这三类含义完全不同，不能混着说
    cls = collections.Counter()
    for key, cnt in left.items():
        ids = left_ids.get(key)
        cls["贴上一个 ID" if (ids and len(ids) == 1)
            else "多个 ID 共用同一句英文" if ids
            else "连模板都匹配不上"] += cnt

    L = []
    L.append("诊断覆盖率报告（口径：正文含汉字 = 已覆盖）")
    L.append("语料: %d 个真实文件   参数: %s" % (len(files), args.extra))
    L.append("=" * 78)
    L.append("【全部实例】")
    L.append("  诊断实例总数      : %d" % allc["n"])
    L.append("  其中正文含汉字    : %d" % allc["cjk"])
    L.append("  覆盖率            : %s   (%d/%d)"
             % (pct(allc["cjk"], allc["n"]), allc["cjk"], allc["n"]))
    L.append("")
    L.append("【只算有源码位置的实例】（排除「clang: error: ...」这类驱动自身消息）")
    L.append("  实例总数          : %d" % locc["n"])
    L.append("  其中正文含汉字    : %d" % locc["cjk"])
    L.append("  覆盖率            : %s   (%d/%d)"
             % (pct(locc["cjk"], locc["n"]), locc["cjk"], locc["n"]))
    L.append("")
    L.append("按等级（全部实例）：")
    for sev in ("fatal error", "error", "warning", "note", "remark"):
        c = per_sev.get(sev)
        if c and c["n"]:
            L.append("  %-12s %5d / %-5d = %s" % (sev, c["cjk"], c["n"], pct(c["cjk"], c["n"])))
    L.append("")
    L.append("=" * 78)
    L.append("[自检 1] 中文表每条都至少含一个汉字: %s" % ("OK" if self1_ok else "失败"))
    for n, t in no_cjk:
        L.append("    没有汉字的条目: %s = %r" % (n, t[:60]))
    L.append("[自检 2] 正文是英文却反查到「表里已有」的 ID: %d 条 %s"
             % (len(bug), "(OK)" if not bug else "(BUG)"))
    for n, m, p in bug[:20]:
        L.append("    %s  <-  %s  (%s)" % (n, m[:60], os.path.basename(p)))
    L.append("")
    L.append("=" * 78)
    L.append("未覆盖实例合计: %d，按「能不能贴上诊断 ID」分三类：" % n_left)
    for k in ("贴上一个 ID", "多个 ID 共用同一句英文", "连模板都匹配不上"):
        L.append("  %-24s %5d  (%s)" % (k, cls[k], pct(cls[k], n_left)))
    L.append("  （前两类是「知道是哪条、只是没翻」；第三类才需要单独查）")
    L.append("")
    L.append("=" * 78)
    L.append("未覆盖的实例（按正文归并，前 40）")
    L.append("  次数  诊断 ID（多个用 | 分隔）                正文")
    L.append("-" * 78)
    for key, cnt in left.most_common(40):
        ids = left_ids.get(key)
        tag = "|".join(ids) if ids else "(匹配不上)"
        L.append("  %-5d %-38s %s" % (cnt, tag[:38], key[:48]))
    L.append("")
    L.append("=" * 78)
    L.append("未覆盖里【能唯一贴上 ID】的，按 ID 排名（前 30）")
    L.append("-" * 78)
    by_id = collections.Counter()
    for key, cnt in left.items():
        ids = left_ids.get(key)
        if ids and len(ids) == 1:
            by_id[ids[0]] += cnt
    for name, cnt in by_id.most_common(30):
        L.append("  %-5d %s" % (cnt, name))
    L.append("")
    L.append("未覆盖里【ID 唯一】的合计: %d 条，涉及 %d 个诊断 ID"
             % (sum(by_id.values()), len(by_id)))
    L.append("这些就是下一批的候选（另有 %d 条因多个 ID 共用同一句英文而无法归属，"
             % cls["多个 ID 共用同一句英文"])
    L.append(" 但它们句子的英文是已知的，翻的时候要一并处理同句的全部 ID）")
    L.append("")
    L.append("=" * 78)
    L.append("旧口径（diag_frequency.py）静默丢弃的那批 —— 查清楚它们是什么")
    L.append("-" * 78)
    L.append("diag_frequency.py 里这一段：")
    L.append("    if len(hits) == 1 and not hits[0].startswith(NOISE_ID_PREFIX): ...")
    L.append("    elif len(hits) != 1: unmatched[msg] += 1")
    L.append("命中唯一但 ID 带驱动/前端前缀时，两个分支都不走 —— 这条实例凭空消失，")
    L.append("既不在排名里、也不在「未能反查」里。下面的计数就是那批的去向。")
    noise = collections.Counter()
    for key, cnt in left.items():
        ids = left_ids.get(key)
        if ids and len(ids) == 1 and ids[0].startswith(freq.NOISE_ID_PREFIX):
            noise[ids[0]] += cnt
    L.append("  未覆盖且属于驱动/前端前缀: %d 条，涉及 %d 个 ID" % (sum(noise.values()), len(noise)))
    for name, cnt in noise.most_common(10):
        L.append("    %-5d %s" % (cnt, name))

    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")

    print("")
    for l in L[:24]:
        print(l.encode("ascii", "replace").decode("ascii"))
    print("")
    print("full report (UTF-8): %s" % REPORT)
    return 2 if (not self1_ok or bug) else 0


if __name__ == "__main__":
    sys.exit(main())
