# -*- coding: utf-8 -*-
"""
Sweep every Chinese preprocessor directive spelling against its English
counterpart and require the two to behave IDENTICALLY.

Why parity instead of "exit code 0":
  Some English directives are unimplemented or invalid in clang on purpose.
  `#assert` / `#unassert` hit `case tok::pp_assert: break;` and fall through to
  "invalid preprocessing directive" (see PPDirectives.cpp:1496). `#module` is
  rejected even in English (PPDirectives.cpp:1455 requires the introducer to be
  the module contextual keyword). A checker that demanded "no invalid-directive
  error" would either fail on those or have to whitelist them by hand.
  Comparing the CHINESE run against the ENGLISH run needs no whitelist: whatever
  the English spelling does, the Chinese spelling must do exactly the same.

Parity alone is not enough, though -- two equally broken runs would pass. So
every case also carries an EXPECTED exit status, and an explicit self-test
proves the comparator can report a difference.

Usage:
    python tests\\13-preprocessor\\sweep.py [path\\to\\clang.exe]
Exit code 0 = every spelling is recognised and at parity.
"""

import io
import os
import re
import subprocess
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DEFAULT_CLANG = os.path.join(ROOT, r"build\Release\bin\clang.exe")
CLANG = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CLANG

# (english spelling, chinese spelling, body template, extra flags, expect)
#   body uses {D} for the directive spelling and {H} for this directory.
#   expect: "ok"  -> clang must succeed (the directive really works)
#           "err" -> clang must fail (that is the English behaviour too)
#
# WHY THE CONDITIONAL CASES CARRY static_assert:
#   The first version of this sweep only checked the exit code. That made it
#   BLIND to the worst bug in this area: `#如果 0` is FALSE, so clang takes the
#   skip path (SkipExcludedConditionalBlock), which matches directive names as
#   RAW STRINGS and therefore did not recognise `#否则若` / `#结束如果`. The skip
#   then ran on to the next ENGLISH `#endif`, exited 0, and the test "passed"
#   while every branch in between was silently eaten.
#   A static_assert on WHICH BRANCH WAS TAKEN makes the exit code depend on the
#   skipping logic, so that bug cannot pass again.
CASES = [
    ("if",           "如果",           "#define T 0\n#{D} 1\n#  define T 1\n#endif\n"
                                        "static_assert(T == 1);\n", [], "ok"),
    ("ifdef",        "如果已定义",      "#define A 1\n#define T 0\n#{D} A\n"
                                        "#  define T 1\n#endif\nstatic_assert(T == 1);\n",
     [], "ok"),
    ("ifndef",       "如果未定义",      "#define T 0\n#{D} A\n#  define T 1\n#endif\n"
                                        "static_assert(T == 1);\n", [], "ok"),
    # The next four all force the SKIP path (the #if is false), which is the
    # path that broke.
    ("elif",         "否则若",         "#define T 0\n#if 0\n#  define T 1\n#{D} 1\n"
                                        "#  define T 2\n#endif\nstatic_assert(T == 2);\n",
     [], "ok"),
    ("elifdef",      "否则若已定义",    "#define A 1\n#define T 0\n#if 0\n#  define T 1\n"
                                        "#{D} A\n#  define T 2\n#endif\n"
                                        "static_assert(T == 2);\n", [], "ok"),
    ("elifndef",     "否则若未定义",    "#define T 0\n#if 0\n#  define T 1\n#{D} A\n"
                                        "#  define T 2\n#endif\nstatic_assert(T == 2);\n",
     [], "ok"),
    ("else",         "否则",           "#define T 0\n#if 0\n#  define T 1\n#{D}\n"
                                        "#  define T 2\n#endif\nstatic_assert(T == 2);\n",
     [], "ok"),
    ("endif",        "结束如果",       "#define T 0\n#if 1\n#  define T 1\n#{D}\n"
                                        "static_assert(T == 1);\n", [], "ok"),
    ("include",      "包含",           "#{D} \"inc_a.h\"\nint x;\n", ["-I", HERE], "ok"),
    ("define",       "定义",           "#{D} A 1\nstatic_assert(A == 1);\n", [], "ok"),
    ("undef",        "取消定义",       "#define A 1\n#{D} A\n#ifdef A\n"
                                        "static_assert(false);\n#endif\n", [], "ok"),
    ("line",         "行号",           "#{D} 5\nint x;\n", [], "ok"),
    ("error",        "错误",           "#{D} boom\nint x;\n", [], "err"),
    ("warning",      "警告",           "#{D} boom\nint x;\n", [], "ok"),
    ("pragma",       "编译指示",       "#{D} once\nint x;\n", [], "ok"),
    ("embed",        "嵌入",           "static const unsigned char d[] = {\n"
                                        "#{D} \"{H}/inc_a.h\"\n};\nint x;\n",
     ["-std=c++26"], "ok"),
    ("include_next", "包含下一个",      "#{D} \"inc_a.h\"\nint x;\n", ["-I", HERE], "ok"),
    ("ident",        "标识",           "#{D} \"x\"\nint x;\n", [], "ok"),
    ("assert",       "断言",           "#{D} machine(x)\nint x;\n", [], "err"),
    ("unassert",     "取消断言",       "#{D} x\nint x;\n", [], "err"),
    # module/import carry their Chinese spelling in ChineseKeywords.def too
    # (kw_module / kw_import); this checks the DIRECTIVE form stays at parity.
    ("module",       "模块",           "#{D} m;\nint x;\n", [], "err"),
    ("import",       "导入",           "#{D} \"inc_a.h\"\nint x;\n", [], "err"),
]

# All-Chinese nested conditional: both the dispatch path and the skip path, at
# depth 2. This is the shape real code has, and the shape the first sweep missed.
NESTED = ("#define T 0\n"
          "#如果 1\n"
          "#  如果 0\n"
          "#    定义 T 1\n"
          "#  否则\n"
          "#    定义 T 2\n"
          "#  结束如果\n"
          "#结束如果\n"
          "static_assert(T == 2);\n")

# Lines that necessarily differ between the two runs and carry no behaviour:
#   t.cpp:1:2: error: ...        <- file name and column differ
#       1 | #如果 1               <- the echoed source line
#         |  ^                     <- the caret underline
_ECHO = re.compile(r"^\s*\d+\s*\|")
_CARET = re.compile(r"^\s*\|")


def norm(text, spelling):
    """Reduce diagnostics to a comparable core.

    Three normalisations matter, and the first two were got WRONG on the first
    attempt (2026-09-24), producing false "behaviour differs" reports:

      1. The source path must be masked WHOLE. A Windows path contains ':',
         so `^[^:]+:\\d+:` matched only the drive letter. Mask `...\\*.cpp`
         first, then whatever `:line:col:` survives elsewhere.
      2. Replacing the bare spelling rewrote the diagnostic SEVERITY word:
         `#error`'s message starts with `error:` and the splitter turned it into
         `@D@:`. Only `#` + spelling identifies the directive -- and it must be
         word-bounded, because clang's warning GROUP for `#warning` is literally
         `-W#warnings`, where `#warning` is a prefix of the flag name.
      3. Warning-group names are masked wholesale; they are build-system
         identifiers, not user-visible behaviour.
    """
    out = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        line = raw.rstrip()
        if not line:
            continue
        if _ECHO.match(line) or _CARET.match(line):
            continue
        line = re.sub(r"[^\s]*\.cpp", "@F@", line)
        line = re.sub(r":\d+:\d+:", ":@L@:", line)
        line = re.sub(r"-W[-\w#]*", "@W@", line)
        # Mask EVERY directive mention, spelling-agnostically.
        #
        # This has to include the CHINESE spellings, and that is not cosmetic:
        # since 2026-09-24 the diagnostic names the directive in Chinese no
        # matter what the user typed (same policy as keywords, where English
        # `static_assert` still prints `静态断言`). So the English run's
        # diagnostic now contains `#否则若已定义` -- masking only `#elifdef`
        # would leave the two runs looking different when they are in fact
        # identical, which is exactly the false positive this mask prevents.
        #
        # `-W...` is masked first, so `-W#warnings` never reaches this rule.
        line = re.sub(r"#[^\s'\"]+", "#@D@", line)
        # summary lines only count what is already listed
        if line.startswith("生成了"):
            continue
        out.append(line)
    return out


def run(src_name, body, extra):
    path = os.path.join(WORK, src_name)
    with io.open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    cmd = [CLANG, "-fsyntax-only", "-std=c++23"] + extra + [path]
    p = subprocess.run(cmd, capture_output=True)
    txt = p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")
    return p.returncode, txt


WORK = tempfile.mkdtemp(prefix="zhdir_")
HERE_FWD = HERE.replace("\\", "/")
if not os.path.isfile(CLANG):
    print("找不到编译器：%s" % CLANG)
    sys.exit(2)

# ---------------------------------------------------------------- 自测
# The comparator must be able to report a DIFFERENCE, otherwise every case
# "passes" vacuously. Same discipline as the self-tests in
# tests\checks\verify_chinese_keywords.py.
_a = norm("t.cpp:1:2: warning: boom [-W#warnings]\n"
          "    1 | #warning boom\n      |  ^\n生成了 1 个警告。\n", "warning")
_b = norm("t.cpp:1:2: error: boom\n"
          "    1 | #warning boom\n      |  ^\n生成了 1 个错误。\n", "warning")
_c = norm("t.cpp:1:2: warning: boom [-W#warnings]\n"
          "    1 | #warning boom\n      |  ^\n生成了 1 个警告。\n", "warning")
if _a != _b and _a == _c:
    print("  [通过] 归一化自测：severity 不同的诊断被区分，相同的被认作相同")
else:
    print("  [错误] 归一化自测失败：a=%r b=%r c=%r" % (_a, _b, _c))
    sys.exit(1)

# ---------------------------------------------------------------- 逐条扫描
print("compiler: %s" % CLANG)
print("")

bad = []
for en, zh, template, extra, expect in CASES:
    want_rc = 0 if expect == "ok" else 1
    rc_e, txt_e = run("en_%s.cpp" % en, template.replace("{D}", en).replace("{H}", HERE_FWD), extra)
    rc_z, txt_z = run("zh_%s.cpp" % zh, template.replace("{D}", zh).replace("{H}", HERE_FWD), extra)
    ne = norm(txt_e, en)
    nz = norm(txt_z, zh)
    tag = "%-13s -> %-13s" % ("#" + en, "#" + zh)

    problems = []
    if rc_z != want_rc:
        problems.append("中文 exit=%d，期望 %d" % (rc_z, want_rc))
    if rc_e != want_rc:
        problems.append("英文 exit=%d，期望 %d" % (rc_e, want_rc))
    if ne != nz:
        problems.append("中英诊断不同")
    if rc_e != rc_z:
        problems.append("中英 exit 不同")

    if not problems:
        note = nz[0] if nz else "(无诊断)"
        print("  [通过] %s  exit=%d  %s" % (tag, rc_z, note))
    else:
        bad.append((en, zh, problems, rc_e, rc_z, ne, nz))
        print("  [错误] %s  %s" % (tag, "；".join(problems)))
        if ne != nz:
            print("        英文: %r" % (ne,))
            print("        中文: %r" % (nz,))

print("")
print("=" * 72)
if bad:
    print("  %d / %d 条指令未通过" % (len(bad), len(CASES)))
    for en, zh, problems, *_ in bad:
        print("   - #%s vs #%s：%s" % (en, zh, "；".join(problems)))
    sys.exit(1)
print("  %d / %d 条指令：中文拼写全部被识别，且与英文行为、诊断完全一致"
      % (len(CASES), len(CASES)))

# ---------------------------------------------------------------- 嵌套用例
# 纯中文的嵌套条件编译，同时走「求值」与「跳过」两条路径。第一版扫描漏掉的
# 正是这一类：单条指令的退出码在跳过路径上永远是 0，看不出问题。
rc_n, txt_n = run("nested_zh.cpp", NESTED, [])
if rc_n == 0:
    print("  [通过] 纯中文嵌套条件编译（深度 2，#否则 + #结束如果）"
          "static_assert(T == 2) 成立")
else:
    print("  [错误] 纯中文嵌套条件编译失败（exit=%d）" % rc_n)
    for line in txt_n.replace("\r\n", "\n").split("\n")[:6]:
        if line.strip():
            print("        %s" % line)
    sys.exit(1)

# 反向锚点：把同一段代码的指令换成英文，也必须成立。否则「中文通过」可能只是
# 因为 static_assert 根本没被编到。
NESTED_EN = (NESTED.replace("#如果", "#if").replace("#否则", "#else")
             .replace("#结束如果", "#endif").replace("#    定义", "#    define"))
rc_ne, txt_ne = run("nested_en.cpp", NESTED_EN, [])
if rc_ne == 0:
    print("  [通过] 同一段代码改用英文指令也成立（反向锚点）")
else:
    print("  [错误] 英文对照版不成立，说明锚点本身有问题（exit=%d）" % rc_ne)
    sys.exit(1)

print("")
print("  结果：全部通过。")
sys.exit(0)
