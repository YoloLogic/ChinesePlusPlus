# -*- coding: utf-8 -*-
"""清点这套工具链到底「自带」了哪些库。

为什么需要这个脚本
------------------
`docs\\汉字第一公民-路线图.md` 第五节给了一张「自带库 = 0 个」的表。
那是一句**可测量的断言**，所以必须有能复跑的工具 —— 否则它和
"文档说会查角色表而检查并不存在"是同一类东西（本项目栽过多次）。

三件事分开数，因为混在一起会得出错误结论：
  1. build\\Release\\lib 下的 .lib      —— 全是【编译器自己的构建产物】
  2. clang 的 resource dir 里的头      —— 除 19 个 freestanding 头外都不是「标准库」
  3. 真正被 #include <vector> 命中的目录 —— 【别人的库】（MSVC STL / Windows UCRT）

用法：
    python tools\\inventory_libraries.py
    python tools\\inventory_libraries.py --json out.json
"""

import io
import os
import re
import sys
import json
import argparse
import collections
import subprocess

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUILD = os.path.join(ROOT, "build", "Release")
CLANG = os.path.join(BUILD, "bin", "clang.exe")

# 标准规定的 freestanding 头：这是【编译器的最低义务】，任何实现都得提供，
# 不是「我们的标准库」。名单来自 C 标准 4p6 + C++ 标准 [support]。
FREESTANDING = {
    "stddef.h", "stdarg.h", "stdbool.h", "stdalign.h", "stdnoreturn.h",
    "stdatomic.h", "stdckdint.h", "float.h", "limits.h", "stdint.h",
    "inttypes.h", "iso646.h", "varargs.h", "tgmath.h",
}
# clang 额外自带的、不在上面那批、但也不是 GPU/内建函数包装的
EXTRA_C = {"unwind.h", "ptrauth.h", "opencl-c.h", "opencl-c-base.h",
           "mm3dnow.h"}


def walk_files(base, exts):
    out = []
    for dp, _dn, fn in os.walk(base):
        for f in fn:
            if os.path.splitext(f)[1].lower() in exts:
                out.append(os.path.join(dp, f))
    return out


def count_libs():
    libs = walk_files(BUILD, {".lib", ".a", ".dll"})
    pref = collections.Counter()
    for p in libs:
        n = os.path.basename(p).lower()
        for k in ("clangd", "clang", "lld", "llvm", "libclang"):
            if n.startswith(k):
                pref[k] += 1
                break
        else:
            pref["其他"] += 1
    # 面向用户的库（标准库 / 运行时 / C API）
    user_pat = re.compile(r"libclang|c\+\+|cxx|compiler-rt|clang_rt|libc\."
                          r"|msvcrt|unwind", re.I)
    user = [os.path.basename(p) for p in libs
            if user_pat.search(os.path.basename(p))]
    return {"total": len(libs), "by_prefix": dict(pref),
            "user_facing": user}


def count_headers():
    if not os.path.isfile(CLANG):
        return {"error": "clang.exe not found: %s" % CLANG}
    try:
        rd = subprocess.run([CLANG, "-print-resource-dir"],
                            capture_output=True).stdout.decode("utf-8", "replace").strip()
    except OSError as e:
        return {"error": str(e)}
    inc = os.path.join(rd, "include")
    if not os.path.isdir(inc):
        return {"error": "no include dir under %s" % rd}

    top = [f for f in os.listdir(inc) if os.path.isfile(os.path.join(inc, f))]
    dirs = sorted(d for d in os.listdir(inc) if os.path.isdir(os.path.join(inc, d)))
    sub = {d: len(walk_files(os.path.join(inc, d), {".h", ".hpp", ".def", ".inc",
                                                    ".modulemap", ".txt"}))
           for d in dirs}

    cat = collections.Counter()
    free = []
    for f in top:
        if f.startswith(("__clang_cuda", "__clang_hip", "__clang_gpu",
                         "__clang_spirv", "__clang_openmp_device")):
            cat["GPU/OpenMP/SPIRV 设备端包装"] += 1
        elif f.endswith("intrin.h") or f in ("cpuid.h", "module.modulemap"):
            cat["x86/ARM 内建函数头"] += 1
        elif f in FREESTANDING or f in EXTRA_C:
            cat["C 语言 freestanding 头"] += 1
            free.append(f)
        else:
            cat["拼装碎片 / 其他"] += 1
    return {"resource_dir": rd, "include_dir": inc,
            "top_level_files": len(top), "top_level_categories": dict(cat),
            "freestanding": sorted(free),
            "subdirs": sub, "subdir_total": sum(sub.values())}


def include_search_paths():
    """问 clang 自己：#include <vector> / <stdio.h> 会去哪些目录找。"""
    if not os.path.isfile(CLANG):
        return {"error": "clang.exe not found"}
    tmp = os.path.join(BUILD, "_inventory_probe.cpp")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)
    io.open(tmp, "w", encoding="utf-8").write(
        "#include <vector>\n#include <stdio.h>\nint main(){return 0;}\n")
    p = subprocess.run([CLANG, "-std=c++20", "-E", "-v", "-fsyntax-only", tmp],
                       capture_output=True)
    txt = p.stderr.decode("utf-8", "replace")
    inside, paths = False, []
    for line in txt.splitlines():
        if "search starts here" in line:
            inside = True
            continue
        if "End of search list" in line:
            inside = False
            continue
        if inside:
            paths.append(line.strip())
    return {"paths": paths}


def compiler_runtime_sources():
    out = {}
    for d in ("libcxx", "libcxxabi", "libc", "compiler-rt", "runtimes"):
        out[d] = os.path.isdir(os.path.join(ROOT, "LLVM-main", d))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    a = ap.parse_args()

    libs = count_libs()
    hdrs = count_headers()
    paths = include_search_paths()
    srcs = compiler_runtime_sources()

    print("=" * 72)
    print("1. build\\Release 下的 .lib/.a/.dll —— 编译器自己的构建产物")
    print("=" * 72)
    print("  总计: %d" % libs["total"])
    for k, v in sorted(libs["by_prefix"].items(), key=lambda x: -x[1]):
        print("    %-10s %d" % (k, v))
    print("  面向用户的库（标准库/运行时/C API）命中: %d %s"
          % (len(libs["user_facing"]), libs["user_facing"]))

    print()
    print("=" * 72)
    print("2. clang 自带的头（resource dir）")
    print("=" * 72)
    if "error" in hdrs:
        print("  [错误] %s" % hdrs["error"])
    else:
        print("  %s" % hdrs["include_dir"])
        print("  顶层文件: %d    子目录: %d 个共 %d 个文件"
              % (hdrs["top_level_files"], len(hdrs["subdirs"]),
                 hdrs["subdir_total"]))
        for k, v in sorted(hdrs["top_level_categories"].items(), key=lambda x: -x[1]):
            print("    %-28s %3d" % (k, v))
        print("  C freestanding 头 %d 个:" % len(hdrs["freestanding"]))
        print("    " + " ".join(hdrs["freestanding"]))
        print("  子目录: " + "  ".join("%s %d" % (k, v)
                                      for k, v in hdrs["subdirs"].items()))

    print()
    print("=" * 72)
    print("3. #include <vector> / <stdio.h> 实际解析到哪里 —— 别人的库")
    print("=" * 72)
    if "error" in paths:
        print("  [错误] %s" % paths["error"])
    else:
        for p in paths["paths"]:
            tag = ""
            if os.path.normcase(p).startswith(os.path.normcase(hdrs.get("include_dir", "\0"))):
                tag = "   <- clang 自带"
            elif "MSVC" in p:
                tag = "   <- MSVC STL（C++ 标准库）"
            elif "ucrt" in p.lower():
                tag = "   <- Windows UCRT（C 标准库）"
            print("  %s%s" % (p, tag))

    print()
    print("=" * 72)
    print("4. libc++ / libc / compiler-rt 源码在不在、构建了没")
    print("=" * 72)
    for k, v in srcs.items():
        print("  %-12s 源码%s   构建%s"
              % (k, "有" if v else "无", "（本工具未检测到产物，见第 1 节）"))

    print()
    print("结论：自带库 = %d 个。C/C++ 标准库来自 MSVC STL 与 Windows UCRT。"
          % len(libs["user_facing"]))

    if a.json:
        io.open(a.json, "w", encoding="utf-8").write(json.dumps(
            {"libs": libs, "headers": hdrs, "search_paths": paths,
             "runtime_sources": srcs}, ensure_ascii=False, indent=2))
        print("JSON -> %s" % a.json)

    return 0


if __name__ == "__main__":
    sys.exit(main())
