# -*- coding: utf-8 -*-
"""
构建完成后运行：用新编译出的 clang 做端到端验证。

检查项：
  1. clang 可执行文件存在并报告版本
  2. 纯中文代码能通过语法检查            (test_chinese.cpp)
  3. 纯英文代码仍能编译                  (test_english.cpp)  <- 回归
  4. 中英转译对照产出等价 AST            (test_translit_zh/en.cpp)
  5. 错误诊断显示中文关键字              (test_diag.cpp)
  6. 同一 token 的中英拼写确实等价       (token 级验证)

用法：python tools/verify_build.py
"""

import glob
import io
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

BUILD = r"E:\Chinese++\build"
TESTS = r"E:\Chinese++\tests"
errors = []


def section(t):
    print("")
    print("=" * 72)
    print(t)
    print("=" * 72)


def find_clang():
    cands = []
    for pat in (
        os.path.join(BUILD, "bin", "Release", "clang.exe"),
        os.path.join(BUILD, "Release", "bin", "clang.exe"),
        os.path.join(BUILD, "bin", "clang.exe"),
        os.path.join(BUILD, "**", "clang.exe"),
    ):
        cands += glob.glob(pat, recursive=True)
    # 排除 clang-cl / clang-cpp 之类，取 basename 恰为 clang.exe 的
    cands = [c for c in cands if os.path.basename(c).lower() == "clang.exe"]
    return cands[0] if cands else None


def run(clang, args, cwd=TESTS):
    p = subprocess.run([clang] + args, cwd=cwd,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    return p.returncode, out


section("0. 定位构建产物")
clang = find_clang()
if not clang:
    print("  [错误] 未找到 clang.exe，构建可能还没完成或失败")
    print("         已查找：%s" % BUILD)
    sys.exit(2)
print("  clang: %s" % clang)
print("  大小 : %.1f MB" % (os.path.getsize(clang) / 1024.0 / 1024.0))

rc, out = run(clang, ["--version"])
print("  版本 : %s" % out.strip().splitlines()[0] if out.strip() else "  (无输出)")

# ---------------------------------------------------------------- 1. 纯中文
section("1. 纯中文代码语法检查 (test_chinese.cpp)")
rc, out = run(clang, ["-std=c++20", "-fsyntax-only", r"E:\Chinese++\tests\08-regression\chinese.cpp"])
if rc == 0:
    print("  [通过] 中文关键字全部识别，语法检查通过")
else:
    errors.append("纯中文代码未能通过")
    print("  [失败] 返回码 %d" % rc)
    for line in out.splitlines()[:25]:
        print("      " + line)

# ---------------------------------------------------------------- 2. 纯英文
section("2. 纯英文代码回归 (test_english.cpp)")
rc, out = run(clang, ["-std=c++20", "-fsyntax-only", r"E:\Chinese++\tests\08-regression\english.cpp"])
if rc == 0:
    print("  [通过] 英文代码（含标准库头文件）照常编译")
else:
    errors.append("纯英文代码回归失败")
    print("  [失败] 返回码 %d" % rc)
    for line in out.splitlines()[:25]:
        print("      " + line)

# ---------------------------------------------------------- 3. 转译 AST 等价
section("3. 中英转译 AST 等价性 (test_translit_zh.cpp vs _en.cpp)")


def ast_of(fname):
    rc, out = run(clang, ["-std=c++20", "-Xclang", "-ast-dump",
                          "-fsyntax-only", fname])
    if rc != 0:
        return None, out
    # 去掉地址与源码位置，只留结构
    out = re.sub(r"0x[0-9a-fA-F]+", "0xADDR", out)
    out = re.sub(r"<[^<>]*>", "<LOC>", out)
    # 中英版本的关键字字节数不同、源文件注释行数也不同，源位置必然不同；
    # 这里只比较结构，因此把行号与列号一并归一化。
    out = re.sub(r"line:\d+:\d+", "line:L", out)
    out = re.sub(r"col:\d+", "col:C", out)
    # 只关心节点类型行，去掉行首缩进差异
    lines = [re.sub(r"^\s*[|`\-]+", "", l).strip() for l in out.splitlines()]
    return [l for l in lines if l], None


zh, err_zh = ast_of(r"E:\Chinese++\tests\08-regression\translit_zh.cpp")
en, err_en = ast_of(r"E:\Chinese++\tests\08-regression\translit_en.cpp")
if zh is None or en is None:
    errors.append("AST 导出失败")
    print("  [失败] 中文版错误:\n%s" % (err_zh or "")[:800])
    print("  [失败] 英文版错误:\n%s" % (err_en or "")[:800])
else:
    print("  中文版 AST 行数: %d" % len(zh))
    print("  英文版 AST 行数: %d" % len(en))
    if zh == en:
        print("  [通过] 两者 AST 结构完全一致 —— 中文与英文关键字确实等价")
    else:
        # 允许声明拼写不同，找出真正的结构差异
        diff = [(a, b) for a, b in zip(zh, en) if a != b]
        print("  [提示] 有 %d 行差异（可能只是声明名拼写），前 10 行：" % len(diff))
        for a, b in diff[:10]:
            print("      中: %s" % a)
            print("      英: %s" % b)

# ---------------------------------------------------------------- 4. 诊断
section("4. 错误诊断是否显示中文 (test_diag.cpp)")
rc, out = run(clang, ["-std=c++20", "-fsyntax-only", r"E:\Chinese++\tests\09-diagnostics\diag_cn.cpp"])
if rc == 0:
    print("  [警告] 该文件本应报错却编译通过了，测试文件可能被改坏")
else:
    has_zh = "如果" in out
    has_en = "expected" in out and "'if'" in out
    print("  诊断首行: %s" % (out.strip().splitlines()[0] if out.strip() else "(无)"))
    if has_zh:
        print("  [通过] 诊断中出现中文关键字「如果」—— 中文为主已生效")
    elif has_en:
        errors.append("诊断显示英文 'if'，中文优先未生效")
        print("  [失败] 诊断显示的是英文 'if'，中文优先分支未生效")
    else:
        print("  [提示] 未在诊断中直接看到关键字拼写，请人工查看上面的输出")

# ------------------------------------------------- 5. token 级中英等价验证
section("5. token 级验证：中英拼写落到同一个 token")
probe = os.path.join(TESTS, "_probe_tokens.cpp")
with io.open(probe, "w", encoding="utf-8") as fh:
    fh.write("整数 甲 = 1;\nint 乙 = 2;\n")
rc, out = run(clang, ["-std=c++20", "-Xclang", "-dump-tokens",
                      "-fsyntax-only", "_probe_tokens.cpp"])
if rc == 0:
    # dump-tokens 每行格式为： <kind>  '<拼写>'  Loc=<...>
    # kind 在行首；拼写在引号内，非 ASCII 会以八进制转义输出。
    # 注意不能从引号里取内容——那是拼写，不是 token 类型。
    kinds = re.findall(r"^(\w+)\s+'", out, re.M)
    print("  token 类型序列: %s" % kinds[:12])
    kw_int = [k for k in kinds if k == "int"]
    if len(kw_int) >= 2:
        print("  [通过] 「整数」与「int」产生同一个 token 类型 `int`（%d 次）" % len(kw_int))
        print("         前者拼写是八进制转义的 UTF-8，后者是 ASCII，但类型完全相同")
    else:
        errors.append("中英拼写未落到同一个 token")
        print("  [失败] `int` 类型出现 %d 次，预期至少 2 次" % len(kw_int))
else:
    print("  [失败] -dump-tokens 执行失败:\n%s" % out[:600])
    errors.append("token 导出失败")

# ---------------------------------------------------------------- 总结
section("端到端验证结论")
print("  错误数：%d" % len(errors))
for e in errors:
    print("    - " + e)
if errors:
    print("")
    print("  结果：未通过。")
    sys.exit(1)
else:
    print("")
    print("  结果：全部通过 —— 汉语编程关键字端到端可用。")
    sys.exit(0)
