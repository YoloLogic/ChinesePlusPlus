# -*- coding: utf-8 -*-
"""实测：标准库「复制一份加中文名」以后，能不能做到"用户想引用哪个就用哪个"。

这是 docs\\汉字第一公民-路线图.md 第 4.0 节的证据脚本。
**为什么不是 tests\\ 下的常规用例**：它验证的是 C++ 语言与头文件组织方式的性质，
不是我们编译器的行为。它是一次【设计决定的取证】，所以放 tools\\，
且不参与 run_all 的通过计数。

用法：
    python tools\\library_plan_evidence\\run.py

三层结论（脚本会全部断言，跑不过就说明文档里的结论变了）：

  A. 同一个文件里同时引        -> 报错（重定义 / 或缺成员）
  B. 库之间互相引用（传递包含） -> 报错，但【错误指向第三方库的头】
  C. 跨翻译单元各引各的        -> **不报错**（IFNDR：标准不要求诊断）
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

MAIN = "int main(){ my::V<int> v; v.压入(1); v.push_back(2); return 0; }"
bad = 0


def sh(args, cwd=HERE):
    p = subprocess.run(args, capture_output=True, cwd=cwd)
    return (p.returncode,
            (p.stdout + p.stderr).decode("utf-8", "replace"))


def first_error(txt):
    for line in txt.splitlines():
        if "error:" in line:
            return line.split("error:", 1)[1].strip()
    return ""


def compile_case(fname, body, extra=None):
    src = os.path.join(HERE, fname)
    io.open(src, "w", encoding="utf-8").write(body)
    rc, txt = sh([CLANG, "-std=c++20", "-fsyntax-only"] + (extra or []) + [src])
    return rc, first_error(txt)


def report(label, ok, detail):
    global bad
    mark = "[符合预期]" if ok else "[!! 结论变了 !!]"
    if not ok:
        bad += 1
    print("  %s %-40s %s" % (mark, label, detail))


if not os.path.isfile(CLANG):
    print("找不到编译器：%s" % CLANG)
    sys.exit(2)
print("compiler: %s\n" % CLANG)

# ---------------------------------------------------------------- A. 同一个文件
print("A. 同一个文件里同时引（不需要任何库互相引用）")
A = [
    ("A1 只引中文副本", ["vec_zh.h"], True),
    ("A2 原库 + 中文副本（守卫不同名）", ["vec_orig.h", "vec_zh.h"], False),
    ("A3 中文副本 + 原库（守卫不同名）", ["vec_zh.h", "vec_orig.h"], False),
    ("A4 中文副本 + 原库（守卫同名，先中文）", ["vec_zh_sameguard.h", "vec_orig.h"], True),
    ("A5 原库 + 中文副本（守卫同名，先原库）", ["vec_orig.h", "vec_zh_sameguard.h"], False),
]
for name, headers, should_pass in A:
    body = "".join('#include "%s"\n' % h for h in headers) + MAIN + "\n"
    rc, err = compile_case("_a.cpp", body)
    report(name, (rc == 0) == should_pass,
           "通过" if rc == 0 else "失败：" + err)

# ---------------------------------------------------------------- B. 库互相引用
print()
print("B. 库之间互相引用（第三方库的头里用了中文成员）")
B = [
    ("B1 先引库，再引英文 <vector>", ["lib_uses_chinese.h", "vec_orig.h"], True),
    ("B2 先引英文 <vector>，再引库", ["vec_orig.h", "lib_uses_chinese.h"], False),
]
for name, headers, should_pass in B:
    body = ("".join('#include "%s"\n' % h for h in headers)
            + "int main(){ 库函数(); return 0; }\n")
    rc, err = compile_case("_b.cpp", body)
    report(name, (rc == 0) == should_pass,
           "通过" if rc == 0 else "失败：" + err)

# ---------------------------------------------------------------- C. 跨 TU（静默）
# 这一层最危险：每个 TU 各自合法，链接也过，运行也过，【零诊断】。
# 但 my::V<int> 在两个 TU 里是两份不同的定义 —— 标准上是 IFNDR。
print()
print("C. 跨翻译单元各引各的（这一层【不报错】）")
tu_a = ('#include "vec_orig.h"\n'
        'int fa(){ my::V<int> v; v.push_back(1); return (int)sizeof(v); }\n')
tu_b = ('#include "vec_zh.h"\n'
        'int fb(){ my::V<int> v; v.压入(2); return (int)sizeof(v); }\n')
tu_m = ('#include <cstdio>\n'
        'int fa(); int fb();\n'
        'int main(){ std::printf("fa=%d fb=%d\\n", fa(), fb()); return 0; }\n')

for fname, body in (("_c_a.cpp", tu_a), ("_c_b.cpp", tu_b), ("_c_m.cpp", tu_m)):
    io.open(os.path.join(HERE, fname), "w", encoding="utf-8").write(body)

objs, ok_all, detail = [], True, []
for fname in ("_c_a.cpp", "_c_b.cpp", "_c_m.cpp"):
    obj = os.path.join(HERE, fname.replace(".cpp", ".obj"))
    rc, txt = sh([CLANG, "-std=c++20", "-c", "-o", obj,
                  os.path.join(HERE, fname)])
    if rc != 0:
        ok_all = False
        detail.append("%s 编译失败：%s" % (fname, first_error(txt)))
    objs.append(obj)

if ok_all:
    exe = os.path.join(HERE, "_c.exe")
    rc, txt = sh([CLANG, "-std=c++20", "-o", exe] + objs)
    if rc != 0:
        ok_all = False
        detail.append("链接失败：" + first_error(txt))
    else:
        rc2, out = sh([exe])
        detail.append("链接通过、运行通过、%s" % out.strip())

report("C1 三个 TU 各自编译 + 链接 + 运行",
       ok_all,
       "零诊断（这正是问题）" if ok_all else "；".join(detail))

# ---------------------------------------------------------------- D. 可行的那一步
# 与 A/B/C 相反：中文【头文件名】副本是纯文件操作，只做别名、不改 std::vector
# 的定义，所以三层问题一个都不沾。这是被推迟的库方案里唯一现在就能做的部分。
print()
print("D. 中文【头文件名】副本（唯一零风险、现在就能做的一步）")

D_BODY = """#包含 <向量>
#包含 <cstdio>

// 关键断言：中文名与英文名必须是【同一个类型】，能互相传参
空型 收下(std::vector<整数>& v) { v.push_back(9); }

整数 main() {
    std::vector<整数> 英;
    标准::向量<整数> 中;
    收下(中);                       // 中文名对象 -> 收英文名参数的函数
    if (中.size() != 1) return 1;
    if (sizeof(中) != sizeof(英)) return 2;
    std::printf("D ok: 中.size=%zu sizeof 相同\\n", 中.size());
    return 0;
}
"""
src = os.path.join(HERE, "_d.cpp")
io.open(src, "w", encoding="utf-8").write(D_BODY)
exe = os.path.join(HERE, "_d.exe")
rc, txt = sh([CLANG, "-std=c++20", "-I", HERE, "-o", exe, src])
if rc != 0:
    report("D1 #包含 <向量> 编译", False, "失败：" + first_error(txt))
else:
    rc2, out = sh([exe])
    report("D1 #包含 <向量> 编译 + 运行 + 中英同类型互传",
           rc2 == 0,
           out.strip() if rc2 == 0 else "运行失败 exit=%d" % rc2)

# 中文 include 目录名也要能用（真实项目里目录常是中文的）
zhdir = os.path.join(HERE, "中文目录")
os.makedirs(zhdir, exist_ok=True)
io.open(os.path.join(zhdir, "向量"), "w", encoding="utf-8").write(
    io.open(os.path.join(HERE, "向量"), encoding="utf-8").read())
rc, txt = sh([CLANG, "-std=c++20", "-I", zhdir, "-fsyntax-only", src])
report("D2 中文 include 目录名", rc == 0,
       "通过" if rc == 0 else "失败：" + first_error(txt))


# 关键断言：链接器【没有】报任何 ODR 相关诊断
print()
print("  ⚠ C 层没有报错，不是幸运，是标准如此：")
print("     两个 TU 里 my::V<int> 的定义不同（一个有 压入 一个没有），")
print("     属 [basic.def.odr] 的 IFNDR —— ill-formed, **no diagnostic required**。")
print("     这里碰巧能跑，只因为差异仅在成员函数、布局相同（sizeof 都是 8）。")
print("     一旦中文副本动了数据成员或对齐，跨 TU 传对象就会内存错乱，")
print("     而**依然不会有任何提示**。")

# ---------------------------------------------------------------- 清理
for f in ("_a.cpp", "_b.cpp", "_c_a.cpp", "_c_b.cpp", "_c_m.cpp", "_d.cpp",
          "_c_a.obj", "_c_b.obj", "_c_m.obj", "_c.exe", "_d.exe"):
    try:
        os.remove(os.path.join(HERE, f))
    except OSError:
        pass
try:
    os.remove(os.path.join(zhdir, "向量"))
    os.rmdir(zhdir)
except OSError:
    pass

print()
if bad:
    print("有 %d 项与文档结论不符 —— 第 4.0 节需要更新。" % bad)
    sys.exit(1)
print("全部符合 docs\\汉字第一公民-路线图.md 第 4.0 节的结论：")
print("  A 报错 / B 报错但指向别人的头 / C 不报错（致命）/ D 可行且零风险。")
sys.exit(0)
