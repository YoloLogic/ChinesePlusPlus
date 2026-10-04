#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""checks: 校核中文诊断表 ChineseDiagnostics.def。

这条检查回答两个问题，都是机器答案：

  1. 表里的每个诊断 ID 真的存在吗？
     （用生成的 Diagnostic*Kinds.inc 反查，而不是靠记忆）

  2. 占位符和英文对得上吗？
     （引用了哪几个参数、每个 %select 挂在哪个序号上、有几个分支）

它同时跑一次「校核器自检」：故意写坏几种占位符，确认校核器真的会报错。
一个永远返回「通过」的检查等于没有检查。

注意：这里【不】检查中文翻译得好不好 —— 那只能靠人读。
运行时是否真的显示了中文，由 tests\12-diagnostics\check.ps1 逐条断言。

被 tests\run_all.ps1 自动发现并执行（checks 目录里 .py 后缀）。
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TOOLS = os.path.join(ROOT, "tools")

sys.path.insert(0, TOOLS)
import diag_id_lookup as d  # noqa: E402


def load():
    inc = d.parse_inc()
    if not inc:
        print("FAIL: no generated Diagnostic*Kinds.inc found under")
        print("      " + d.INC_DIR)
        print("      configure/build the compiler first "
              "(tools\\rebuild_clang.ps1).")
        sys.exit(1)
    return inc


def main():
    inc = load()
    print("generated diagnostics: %d" % len(inc))

    # 1) 校核器自检：证明它抓得住写坏的占位符
    bad = d.self_test(inc)
    if bad:
        print("FAIL: validator self-test")
        for b in bad:
            print("  " + b.encode("ascii", "replace").decode("ascii"))
        return 1
    print("validator self-test: OK")

    # 2) 逐条校核中文表
    lines, problems, zh = d.check_table(inc)
    print("chinese table entries: %d" % len(zh))
    print("coverage: %.2f%% of all builtin diagnostics"
          % (100.0 * len(zh) / max(1, len(inc))))

    # 3) §18.13：未翻译的那几条必须"正文由运行时提供"（格式串恰好 `%0`）
    #    —— 把覆盖率的"还差 30 条"从"没做完"变成"**结构上翻不了**"，而且**是判据**。
    #    自检先跑（合成数据必须能被抓），再跑真表。
    bad_self = d.self_test_untranslated()
    if bad_self:
        print("FAIL: untranslated self-test")
        for b in bad_self:
            print("  " + b.encode("ascii", "replace").decode("ascii"))
        return 1
    missing, runtime_only, others = d.check_untranslated(inc, zh)
    print("untranslated: %d (runtime-supplied '%s': %d)"
          % (len(missing), "%0", len(runtime_only)))
    if others:
        print("FAIL: %d untranslated diagnostic(s) still have a real English body"
              % len(others))
        for o in others[:20]:
            print("  %s : %s" % (o, inc[o][0].encode("ascii", "replace").decode("ascii")))
        return 1
    total = len(inc)
    print("translatable coverage: 100.00%% (%d / %d; "
          "the other %d carry their text at runtime)"
          % (total - len(missing), total, len(missing)))

    if problems:
        print("FAIL: %d problem(s)" % len(problems))
        for p in problems:
            for ln in p.splitlines():
                print("  " + ln)
        return 1

    print("all Chinese diagnostics entries are valid "
          "(IDs exist, placeholders match English)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
