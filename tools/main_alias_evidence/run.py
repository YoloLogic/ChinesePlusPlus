# -*- coding: utf-8 -*-
"""实测：给入口点 `main` 加中文拼写，有几条路、各自代价是什么。

证据脚本，对应 docs\\汉字第一公民-路线图.md 第 2.1 节。
**为什么不是 tests\\ 下的常规用例**：它验证的是"某条写法能不能编过"这类
一次性设计取证，不是我们编译器的长期行为契约。放 tools\\，不参与 run_all 计数。

用法：
    python tools\\main_alias_evidence\\run.py

四条断言（跑不过就说明文档里的结论变了）：
  1. 路1 宏 `#定义 主函数 main`                      -> 编译 + 链接 + 运行通过
  2. 路2 汇编标号（声明上）                           -> 编译 + 链接 + 运行通过
  3. 路2 的代价：`空型 主函数() 汇编("main")`         -> **无诊断**（本该被拒）
  4. 对照：`空型 main()`                             -> 报错 'main' 必须返回 int
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
bad = 0


def run(name, body, link=True):
    src = os.path.join(HERE, name + ".cpp")
    io.open(src, "w", encoding="utf-8").write(body)
    if not link:
        p = subprocess.run([CLANG, "-std=c++20", "-fsyntax-only", src],
                           capture_output=True, cwd=HERE)
        rc = p.returncode
    else:
        exe = os.path.join(HERE, name + ".exe")
        p = subprocess.run([CLANG, "-std=c++20", "-o", exe, src],
                           capture_output=True, cwd=HERE)
        rc = p.returncode
        if rc == 0:
            p = subprocess.run([exe], capture_output=True, cwd=HERE)
            rc = p.returncode
    txt = (p.stdout + p.stderr).decode("utf-8", "replace")
    return rc, txt


def report(label, ok, detail):
    global bad
    if not ok:
        bad += 1
    print("  %s %-46s %s" % ("[符合预期]" if ok else "[!! 结论变了 !!]",
                             label, detail))


if not os.path.isfile(CLANG):
    print("找不到编译器：%s" % CLANG)
    sys.exit(2)
print("compiler: %s\n" % CLANG)

# 路 1：宏
MACRO = ('#定义 主函数 main\n'
         '#包含 <cstdio>\n'
         '整数 主函数(){ std::printf("route1\\n"); 返回 0; }\n')
rc, txt = run("_r1", MACRO)
report("路1 宏 `#定义 主函数 main`", rc == 0,
       "编译+链接+运行通过" if rc == 0 else "失败")

# 路 2：汇编标号写在【声明】上（写在定义上不合法）
# 第一版把标号写在定义上，报 `缺少（符号） '}'` —— 位置错了，不是编译器的问题。
ASM = ('#包含 <cstdio>\n'
       '整数 主函数() 汇编("main");       // 标号必须在声明上\n'
       '整数 主函数(){ std::printf("route2\\n"); 返回 0; }\n')
rc, txt = run("_r2", ASM)
report("路2 汇编标号（声明上）", rc == 0,
       "编译+链接+运行通过" if rc == 0 else "失败：" + txt.strip()[:80])

# 路 2 的代价：main 的专属检查是按【名字】做的，汇编标号能把它绕过去。
#
# 2026-09-25 更新：路 3 落地后，`主函数` 会被解析成 `main` 的同一个标识符，
# 所以 `空型 主函数() 汇编("main")` 现在【会报错】—— 检查生效了。
# 这条断言因此从"应当无诊断"翻转为"应当报错"。
# 换句话说：路 3 不只是多了一个拼写，它还【关掉了这条洞】。
# （一般的汇编标号绕过仍然存在，但那是上游特性，与我们无关：
#   `空型 别的名() 汇编("main")` 依旧不会被 main 的检查覆盖。）
BAD1 = '空型 主函数() 汇编("main");\n空型 主函数(){ }\n'
rc, txt = run("_r3", BAD1, link=False)
report("路2 的洞已被路3 关掉：`空型 主函数() 汇编(\"main\")` 现在报错",
       rc != 0,
       "已报错（主函数 = main，专属检查生效）" if rc != 0
       else "仍然无诊断（路 3 没生效？）")

BAD2 = '空型 main(){ }\n'
rc, txt = run("_r4", BAD2, link=False)
report("对照：`空型 main()` 应当报错", rc != 0,
       "已报错（说明检查确实按名字做）" if rc != 0 else "竟然没报错")

# 清理
for f in ("_r1.cpp", "_r2.cpp", "_r3.cpp", "_r4.cpp",
          "_r1.exe", "_r2.exe"):
    try:
        os.remove(os.path.join(HERE, f))
    except OSError:
        pass

print()
if bad:
    print("有 %d 项与文档结论不符 —— 第 2.1 节需要更新。" % bad)
    sys.exit(1)
print("A/B 两条路的表现如上（路1 宏可用；路2 汇编标号可用，但见第 3 条）。")
print("")
print("路 3（改编译器）已于 2026-09-25 实现，走的是【标识符别名】而不是汇编标号：")
print("  IdentifierTable::get() 把 `主函数` 解析成 `main` 的同一个 IdentifierInfo。")
print("  见 docs\\汉字第一公民-路线图.md 第 2.2 节；常规测试在 tests\\14-main-alias\\。")
print("")
print("为什么保留本脚本：它记录了【当初为什么选别名】。")
print("  在路 3 落地之前，第 3 条断言是「无诊断」—— 汇编标号会静默丢掉 main 的")
print("  专属检查。别名路线没有这个洞，而且路 3 落地后连汇编标号那条也一并关掉了")
print("  （因为 `主函数` 从此就是 main，检查按名字生效）。")
sys.exit(0)
