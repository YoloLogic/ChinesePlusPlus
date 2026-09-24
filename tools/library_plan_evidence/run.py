# -*- coding: utf-8 -*-
"""实测：标准库「复制一份加中文名」以后，能不能做到"用户想引用哪个就用哪个"。

这是 docs\\汉字第一公民-路线图.md 第 4.0 节那张表的证据脚本。
**为什么它不是 tests\\ 下的常规用例**：它验证的是 C++ 语言与头文件组织方式的
性质，不是我们编译器的行为。它是一次【设计决定的取证】，所以放在 tools\\ 下，
且不参与 run_all 的通过计数。

用法：
    python tools\\library_plan_evidence\\run.py

结论（脚本会断言，跑不过就说明结论变了）：
  1. 只引中文副本                              -> 通过
  2. 引"原库"+"中文副本"（守卫不同名）          -> 重定义错误（两个顺序都报）
  3. 引"原库"+"中文副本"（守卫同名，先引中文）  -> 通过
  4. 引"原库"+"中文副本"（守卫同名，先引原库）  -> 【缺 压入 成员】
  => 共用 guard 把"重定义"换成了【静默的顺序依赖】。
     `#include <vector>` 常被其它头间接带进来，顺序不在用户手里，
     所以成员级中文做不到"每个 include 各选各的"。
"""

import io
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLANG = os.path.join(ROOT, "build", "Release", "bin", "chinese++.exe")

CASES = [
    ("1. 只引中文副本", ["vec_zh.h"], True),
    ("2. 原库 + 中文副本（守卫不同名）", ["vec_orig.h", "vec_zh.h"], False),
    ("3. 中文副本 + 原库（守卫不同名）", ["vec_zh.h", "vec_orig.h"], False),
    ("4. 中文副本 + 原库（守卫同名，先中文）", ["vec_zh_sameguard.h", "vec_orig.h"], True),
    ("5. 原库 + 中文副本（守卫同名，先原库）", ["vec_orig.h", "vec_zh_sameguard.h"], False),
]

MAIN = "int main(){ my::V<int> v; v.压入(1); v.push_back(2); return 0; }"


def run(name, headers):
    body = "".join('#include "%s"\n' % h for h in headers) + MAIN + "\n"
    src = os.path.join(HERE, "_case.cpp")
    io.open(src, "w", encoding="utf-8").write(body)
    p = subprocess.run([CLANG, "-std=c++20", "-fsyntax-only", src],
                       capture_output=True)
    txt = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")
    first = ""
    for line in txt.splitlines():
        if "error:" in line:
            first = line.split("error:", 1)[1].strip()
            break
    return p.returncode, first


if not os.path.isfile(CLANG):
    print("找不到编译器：%s" % CLANG)
    sys.exit(2)

bad = 0
print("compiler: %s\n" % CLANG)
for name, headers, should_pass in CASES:
    rc, err = run(name, headers)
    ok = (rc == 0) == should_pass
    mark = "[符合预期]" if ok else "[!! 结论变了 !!]"
    if not ok:
        bad += 1
    print("  %s %-34s -> %s%s"
          % (mark, name, "通过" if rc == 0 else "失败", "" if rc == 0 else "：" + err))

print()
if bad:
    print("有 %d 项与文档结论不符 —— 第 4.0 节需要更新。" % bad)
    sys.exit(1)

print("全部符合 docs\\汉字第一公民-路线图.md 第 4.0 节的结论：")
print("  成员级中文做不到「每个 include 各选各的」；")
print("  共用 guard 换来的是静默的顺序依赖（第 5 项）。")

# 清理临时文件
try:
    os.remove(os.path.join(HERE, "_case.cpp"))
except OSError:
    pass
sys.exit(0)
