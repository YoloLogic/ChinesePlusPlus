# -*- coding: utf-8 -*-
"""
验证中文关键字别名表（ChineseKeywords.def）。

本脚本不依赖编译，直接对源码做交叉校验，检查四件事：

  1. 【名称存在】表中每个英文名，都必须真实存在于 clang 的关键字来源里
     （TokenKinds.def 或 Traits.td）。否则生成的 tok::kw_xxx 会编译失败。
  2. 【译名唯一】中文译名不得重复。重复会让后注册者覆盖先注册者。
  3. 【标志合法】FLAGS 中的每个标志都必须是 clang TokenKey 中已定义的枚举。
  4. 【可切分】每个中文译名的首字符必须具有 clang 所采用的 Unicode 18.0
     XID_Start 属性，其余字符必须具有 XID_Continue 属性。否则 clang 的词法
     分析器根本不会把该词切分成一个标识符，中文关键字永远不会生效。
     这一项直接解析 clang/lib/Lex/UnicodeCharSets.h，与编译器实际使用的
     数据表一致（比 Python 自带的 isidentifier() 更权威）。

用法：python tools/verify_chinese_keywords.py
"""

import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = r"E:\Chinese++\LLVM-main"
P_TK = os.path.join(ROOT, r"clang\include\clang\Basic\TokenKinds.def")
P_TR = os.path.join(ROOT, r"clang\include\clang\Basic\Traits.td")
P_ZH = os.path.join(ROOT, r"clang\include\clang\Basic\ChineseKeywords.def")
P_UCS = os.path.join(ROOT, r"clang\lib\Lex\UnicodeCharSets.h")
P_TKH = os.path.join(ROOT, r"clang\include\clang\Basic\TokenKinds.h")

errors = []
warnings = []


def read(path):
    with io.open(path, encoding="utf-8") as fh:
        return fh.read()


def section(title):
    print("")
    print("=" * 72)
    print(title)
    print("=" * 72)


# ---------------------------------------------------------------- 关键字来源
tk = read(P_TK)
tr = read(P_TR)

known = {}

# TokenKinds.def：普通关键字宏
for m in re.finditer(
    r"^(?:KEYWORD|CXX11_KEYWORD|CXX20_KEYWORD|C99_KEYWORD|C23_KEYWORD"
    r"|MODULES_KEYWORD|COROUTINES_KEYWORD)\(\s*([A-Za-z_]\w*)",
    tk,
    re.M,
):
    known.setdefault(m.group(1), "TokenKinds.def")

# TokenKinds.def：UNARY_EXPR_OR_TYPE_TRAIT 形式
for m in re.finditer(r"^UNARY_EXPR_OR_TYPE_TRAIT\(\s*([A-Za-z_]\w*)", tk, re.M):
    known.setdefault(m.group(1), "TokenKinds.def")

# Traits.td：tablegen 生成的 Traits.inc 里的拼写
for m in re.finditer(r'let Spelling = "([^"]+)"', tr):
    known.setdefault(m.group(1), "Traits.td")

# ------------------------------------------------------------------ 中文表
zh = read(P_ZH)
rows = []
for lineno, line in enumerate(zh.splitlines(), 1):
    m = re.match(
        r"\s*ZH_KEYWORD\(\s*([A-Za-z_]\w*)\s*,\s*(\S+?)\s*,\s*(.+?)\s*\)\s*(?://.*)?$",
        line,
    )
    if m:
        rows.append((lineno, m.group(1), m.group(2), m.group(3)))

# 另外两个宏族。它们【不在】上面的 rows 里 —— 因此长期没被任何检查覆盖：
#   ZH_VIRT_SPECIFIER(override, 重写)    上下文关键字（只增不改，英文依旧可用）
#   ZH_OPERATOR_KEYWORD(并且, ampamp)    运算符替代拼写（&& || ! … 的中文拼写）
# 2026-09-23 实测：只数 ZH_KEYWORD 会报 86，而真实译名总数是 99。
# 一个"只数了一族"的校核器会一直打印"全部通过" —— 与它本来要防的毛病同类
# （"校核器会查角色表"而检查并不存在；用例文件放进目录却没注册）。
virt_rows, op_rows = [], []
for lineno, line in enumerate(zh.splitlines(), 1):
    m = re.match(r"\s*ZH_VIRT_SPECIFIER\(\s*([A-Za-z_]\w*)\s*,\s*(\S+?)\s*\)", line)
    if m:
        virt_rows.append((lineno, m.group(1), m.group(2), "(virt-specifier)"))
        continue
    m = re.match(r"\s*ZH_OPERATOR_KEYWORD\(\s*(\S+?)\s*,\s*([A-Za-z_]\w*)\s*\)", line)
    if m:
        op_rows.append((lineno, m.group(2), m.group(1), "(operator-alias)"))
all_rows = rows + virt_rows + op_rows
print("  宏族统计：ZH_KEYWORD %d ＋ ZH_VIRT_SPECIFIER %d ＋ ZH_OPERATOR_KEYWORD %d"
      " ＝ %d 条译名" % (len(rows), len(virt_rows), len(op_rows), len(all_rows)))

# 运算符替代拼写的别名必须真的出现在 TokenKinds.def 的 CXX_KEYWORD_OPERATOR 里。
# （这条以前也从来没查过 —— 那 11 个译名此前不在任何检查的视野里。）
tk_aliases = set(m.group(1) for m in
                 re.finditer(r"CXX_KEYWORD_OPERATOR\(\s*[A-Za-z_]\w*\s*,\s*([A-Za-z_]\w*)", tk))
bad_alias = [(ln, name, zh) for ln, name, zh, _f in op_rows if name not in tk_aliases]
if bad_alias:
    for ln, name, zh in bad_alias:
        errors.append("第 %d 行：运算符别名 `%s`（%s）在 TokenKinds.def 里找不到" % (ln, name, zh))
        print("  [错误] 第 %d 行：`%s`（%s）不是 TokenKinds.def 里的运算符别名" % (ln, name, zh))
else:
    print("  [通过] %d 个运算符替代拼写的别名都能在 TokenKinds.def 中找到" % len(op_rows))

# ------------------------------------------------------------------ 1. 名称
section("1. 英文名存在性检查")
unknown = [r for r in rows if r[1] not in known]
if unknown:
    for lineno, name, zhname, flags in unknown:
        errors.append("第 %d 行：英文名 `%s` 在 TokenKinds.def / Traits.td 中不存在" % (lineno, name))
        print("  [错误] 第 %d 行：`%s` 不存在，tok::kw_%s 会编译失败" % (lineno, name, name))
else:
    print("  [通过] 全部 %d 个英文名均可在 clang 关键字来源中找到" % len(rows))

by_src = {}
for _, name, _, _ in rows:
    by_src[known.get(name, "?")] = by_src.get(known.get(name, "?"), 0) + 1
for src, cnt in sorted(by_src.items()):
    print("        来源 %-16s %d 个" % (src, cnt))

# ------------------------------------------------------------------ 2. 唯一性
section("2. 译名唯一性检查（覆盖全部三个宏族）")
seen = {}
dups = []
for lineno, name, zhname, flags in all_rows:
    if zhname in seen:
        dups.append((zhname, seen[zhname], name, lineno))
    else:
        seen[zhname] = name
if dups:
    for zhname, first, second, lineno in dups:
        errors.append("译名 `%s` 重复：%s 与 %s" % (zhname, first, second))
        print("  [错误] 译名 `%s` 重复：先注册为 %s，第 %d 行又注册为 %s" % (zhname, first, lineno, second))
else:
    print("  [通过] %d 个译名互不重复（三个宏族一起比）" % len(all_rows))

# ------------------------------------------------------------------ 3. 标志
section("3. FLAGS 合法性检查")
tkh = read(P_TKH)
enum_block = tkh.split("enum TokenKey", 1)[1].split("};", 1)[0]
valid_flags = set(re.findall(r"\b(KEY[A-Z0-9_]*|BOOLSUPPORT|WCHARSUPPORT|CHAR8SUPPORT|HALFSUPPORT)\b", enum_block))
bad_flags = []
for lineno, name, zhname, flags in rows:
    for tok in re.findall(r"[A-Za-z_]\w*", flags):
        if tok not in valid_flags:
            bad_flags.append((lineno, name, tok))
if bad_flags:
    for lineno, name, tok in bad_flags:
        errors.append("第 %d 行（%s）：未知标志 `%s`" % (lineno, name, tok))
        print("  [错误] 第 %d 行（%s）：未知标志 `%s`" % (lineno, name, tok))
else:
    print("  [通过] 全部 FLAGS 均为 TokenKey 中已定义的枚举")

# ------------------------------------------------------- 4. Unicode 可切分性
section("4. Unicode 可切分性检查（对照 clang 实际使用的 XID 表）")
ucs = read(P_UCS)
start_block = ucs.split("XIDStartRanges[] = {", 1)[1].split("};", 1)[0]
cont_block = ucs.split("XIDContinueRanges[] = {", 1)[1].split("};", 1)[0]


def parse_ranges(block):
    return [
        (int(a, 16), int(b, 16))
        for a, b in re.findall(r"\{\s*0x([0-9A-Fa-f]+)\s*,\s*0x([0-9A-Fa-f]+)\s*\}", block)
    ]


XS = parse_ranges(start_block)
XC = parse_ranges(cont_block)
print("  XID_Start 区间数：%d    XID_Continue 区间数：%d" % (len(XS), len(XC)))


def in_ranges(cp, ranges):
    for lo, hi in ranges:
        if lo <= cp <= hi:
            return True
    return False


bad_chars = []
for lineno, name, zhname, flags in all_rows:
    for idx, ch in enumerate(zhname):
        cp = ord(ch)
        if idx == 0:
            ok = in_ranges(cp, XS)
            kind = "XID_Start"
        else:
            ok = in_ranges(cp, XS) or in_ranges(cp, XC)
            kind = "XID_Continue"
        if not ok:
            bad_chars.append((lineno, name, zhname, ch, cp, kind, idx))

if bad_chars:
    for lineno, name, zhname, ch, cp, kind, idx in bad_chars:
        errors.append("译名 `%s`（%s）第 %d 个字符 U+%04X 不具有 %s 属性" % (zhname, name, idx + 1, cp, kind))
        print("  [错误] `%s`（%s）第 %d 字 U+%04X 缺少 %s 属性，clang 无法切分" % (zhname, name, idx + 1, cp, kind))
else:
    print("  [通过] 全部译名的每个字符都能被 clang 词法分析器识别为标识符")

# 去重后的字符集规模
allchars = sorted({ch for _, _, zhname, _ in all_rows for ch in zhname})
print("  涉及的不同汉字数：%d" % len(allchars))

# ---------------------------------------------------------- 前缀关系提示
section("5. 译名前缀关系提示（信息，非错误）")
names_sorted = sorted(seen.keys(), key=len)
prefix_pairs = []
for i, a in enumerate(names_sorted):
    for b in names_sorted[i + 1:]:
        if b != a and b.startswith(a):
            prefix_pairs.append((a, seen[a], b, seen[b]))
if prefix_pairs:
    print("  以下译名互为前缀。clang 按“最长连续标识符”切分，因此只要写出")
    print("  完整词即可正确识别；但关键字与相邻标识符之间必须保留空格。")
    for a, na, b, nb in prefix_pairs:
        print("    %s(%s)  ⊂  %s(%s)" % (a, na, b, nb))
else:
    print("  无前缀关系")

# ------------------------------------------------------------- 展开样例
section("6. 宏展开结果抽样（模拟 IdentifierTable.cpp 的展开）")
print("  ZH_KEYWORD(NAME, ZH, FLAGS) 展开为：")
print("    AddKeyword(#ZH, tok::kw_##NAME, FLAGS, LangOpts, *this);")
print("")
sample = ["if", "else", "while", "return", "int", "class", "sizeof", "co_await"]
for name in sample:
    for _, n, zhname, flags in rows:
        if n == name:
            print('    AddKeyword("%s", tok::kw_%s, %s, LangOpts, *this);'
                  % (zhname, name, flags))
            print("      %-12s -> %-14s UTF-8: %s" % (name, zhname, zhname.encode("utf-8").hex(" ").upper()))
            break

# ---------------------------------------------------------------- 7. 接线
section("7. 包含点接线检查")
# 本表默认把 ZH_KEYWORD 展开为空，因此每个包含点都必须在 #include 之前
# 重新定义 ZH_KEYWORD。若漏掉，中文表会“静默失效”：编译通过，但中文关键字
# 全部认不出来。这里逐一静态核对。

INC = '#include "clang/Basic/ChineseKeywords.def"'


def check_site(path, desc, need_fallback=False):
    if not os.path.exists(path):
        errors.append("%s：文件不存在" % desc)
        print("  [错误] %s：文件不存在" % desc)
        return
    src = read(path)
    i_def = src.find("#define ZH_KEYWORD")
    i_inc = src.find(INC)
    if i_inc < 0:
        errors.append("%s：未包含 ChineseKeywords.def" % desc)
        print("  [错误] %s：未包含 ChineseKeywords.def" % desc)
        return
    if i_def < 0 or i_def > i_inc:
        errors.append("%s：在 include 之前缺少 #define ZH_KEYWORD（会静默失效）" % desc)
        print("  [错误] %s：include 之前缺少 #define ZH_KEYWORD —— 会静默失效" % desc)
        return
    print("  [通过] %s" % desc)


check_site(os.path.join(ROOT, r"clang\lib\Basic\IdentifierTable.cpp"),
           "IdentifierTable.cpp 注册中文拼写")

tk_cpp = os.path.join(ROOT, r"clang\lib\Basic\TokenKinds.cpp")
check_site(tk_cpp, "TokenKinds.cpp 中文作为正式拼写")

# TokenKinds.cpp 还必须有英文兜底分支，否则未进中文表的关键字会返回 nullptr
if os.path.exists(tk_cpp):
    tk_cpp_src = read(tk_cpp)
    if "#define KEYWORD(X,Y) case kw_ ## X: return #X;" in tk_cpp_src:
        print("  [通过] TokenKinds.cpp 保留英文兜底分支")
    else:
        errors.append("TokenKinds.cpp：缺少英文兜底分支，未进中文表的关键字会返回 nullptr")
        print("  [错误] TokenKinds.cpp：缺少英文兜底分支")

# Preprocessor.cpp 不得再有“按拼写反查”的用法
pp = os.path.join(ROOT, r"clang\lib\Lex\Preprocessor.cpp")
if os.path.exists(pp):
    pp_src = read(pp)
    if "isStr(tok::getKeywordSpelling" in pp_src:
        errors.append("Preprocessor.cpp：仍存在 isStr(getKeywordSpelling(...)) 拼写反查")
        print("  [错误] Preprocessor.cpp：仍存在拼写反查，写英文 import/module 时会判断失败")
    else:
        print("  [通过] Preprocessor.cpp 已改为按 token 类型判断")

# MSVC 的 /utf-8 必须由【顶层 llvm/CMakeLists.txt 全局设置】。
# 原因有两层：
#  1) LLVM 源码本身含非 ASCII（如 clang/lib/Lex/UnicodeCharSets.h 的数学符号
#     注释），在 GBK 代码页下会被错误解码并吞掉换行，破坏语法；
#  2) 预编译头（PCH）由其它目标生成，只有全局设置才能让 PCH 与源文件一致，
#     否则报 error C2855。
# 因此子目录【不得】再单独设置 /utf-8，否则又会与 PCH 冲突。
top_cml = os.path.join(ROOT, r"llvm\CMakeLists.txt")
cml = os.path.join(ROOT, r"clang\lib\Basic\CMakeLists.txt")

if os.path.exists(top_cml) and 'add_compile_options("/utf-8")' in read(top_cml):
    print("  [通过] llvm/CMakeLists.txt 已全局设置 MSVC /utf-8")
else:
    errors.append("llvm/CMakeLists.txt：缺少全局 MSVC /utf-8（GBK 下 LLVM 自身都编译不过）")
    print("  [错误] llvm/CMakeLists.txt：缺少全局 /utf-8")

if os.path.exists(cml):
    cml_src = read(cml)
    if '"/utf-8"' in cml_src:
        errors.append("clang/lib/Basic/CMakeLists.txt：仍有单独的 /utf-8，会与共享 PCH 冲突")
        print("  [错误] clang/lib/Basic/CMakeLists.txt：仍有局部 /utf-8（应移除）")
    else:
        print("  [通过] clang/lib/Basic/CMakeLists.txt 未重复设置 /utf-8")

# ------------------------------------------------- 8. 边界问题修复检查
section("8. 边界问题修复检查")
# getKeywordSpelling() 返回「正式拼写」，适合显示（诊断/AST 打印），
# 但不适合「凭空合成 token 拼写」。后者必须走 getKeywordSpellingEnglish()。
tk_h = os.path.join(ROOT, r"clang\include\clang\Basic\TokenKinds.h")
syn = os.path.join(ROOT, r"clang\lib\Tooling\Syntax\Synthesis.cpp")

for path, needle, desc in [
    (tk_h, "getKeywordSpellingEnglish", "TokenKinds.h 已声明 getKeywordSpellingEnglish"),
    (tk_cpp, "getKeywordSpellingEnglish", "TokenKinds.cpp 已实现 getKeywordSpellingEnglish"),
    (syn, "tok::getKeywordSpellingEnglish(K)", "Synthesis.cpp 已改用英文拼写合成 token"),
]:
    if os.path.exists(path) and needle in read(path):
        print("  [通过] %s" % desc)
    else:
        errors.append("%s：未生效" % desc)
        print("  [错误] %s" % desc)

if os.path.exists(syn) and "Spelling = tok::getKeywordSpelling(K)" in read(syn):
    errors.append("Synthesis.cpp：仍在用 getKeywordSpelling 合成 token 拼写")
    print("  [错误] Synthesis.cpp 仍用中文正式拼写合成 token，英文源码重构会插入中文")

# ------------------------------------------------- 9. 源文件编码安全检查
section("9. 源文件编码安全检查")
# 教训：只有受 MSVC /utf-8 保护的文件才允许含非 ASCII 字符。
# 在系统代码页为 GBK(936) 时，MSVC 会把 UTF-8 中文注释错误解码，
# 而错位的字节可能吞掉行尾的换行符，使后续代码被并入注释——
# 表现为“某个声明凭空消失”，极难定位（本项目已实际踩过一次）。
# 公共头文件尤其危险：它被全项目包含，无法给所有包含者加 /utf-8。
PROTECTED = {
    "IdentifierTable.cpp",
    "TokenKinds.cpp",
    "ChineseKeywords.def",  # 仅被上面两个受保护的文件包含
}
# 注意：CMakeLists.txt 不在此列。CMake 脚本始终按 UTF-8 读取，不受 MSVC
# 源代码页设置影响，中文注释在那里是安全的。本检查只针对会被 C++ 编译器
# 读取的文件（.h/.hpp/.cpp/.def 等）。
CHANGED_FILES = [
    os.path.join(ROOT, r"clang\include\clang\Basic\ChineseKeywords.def"),
    os.path.join(ROOT, r"clang\include\clang\Basic\TokenKinds.h"),
    os.path.join(ROOT, r"clang\lib\Basic\IdentifierTable.cpp"),
    os.path.join(ROOT, r"clang\lib\Basic\TokenKinds.cpp"),
    os.path.join(ROOT, r"clang\lib\Lex\Preprocessor.cpp"),
    os.path.join(ROOT, r"clang\lib\Tooling\Syntax\Synthesis.cpp"),
    os.path.join(ROOT, r"clang-tools-extra\clangd\SourceCode.cpp"),
]
for _path in CHANGED_FILES:
    if not os.path.exists(_path):
        continue
    _raw = io.open(_path, "rb").read()
    try:
        _raw.decode("ascii")
        _nonascii = False
    except UnicodeDecodeError:
        _nonascii = True
    _base = os.path.basename(_path)
    if _nonascii and _base not in PROTECTED:
        errors.append("%s 含非 ASCII 但不受 /utf-8 保护（GBK 下会破坏语法）" % _base)
        print("  [错误] %-26s 含非 ASCII 且无 /utf-8 保护" % _base)
    elif _nonascii:
        print("  [通过] %-26s 含非 ASCII，受 /utf-8 保护" % _base)
    else:
        print("  [通过] %-26s 纯 ASCII" % _base)

# ------------------------------------------- 10. 译名长度检查（2–6 汉字）
section("10. 译名长度检查（至少两字、最多六字）")

# 定则（用户 2026-09-23 明确：无论如何都得遵守这一条）。
# 汉字数按【汉字】算，不按总字符数 —— `字符8位` 是总长 4、汉字 3。
KW_MIN_HANZI, KW_MAX_HANZI = 2, 6
CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")


def hanzi_count(s):
    return len(CJK_RE.findall(s))


def bad_length(zhname):
    n = hanzi_count(zhname)
    return n < KW_MIN_HANZI or n > KW_MAX_HANZI


bad_len = [(lineno, name, zhname, hanzi_count(zhname))
           for lineno, name, zhname, flags in all_rows if bad_length(zhname)]
if bad_len:
    for lineno, name, zhname, n in bad_len:
        errors.append("第 %d 行（%s）：译名 `%s` 有 %d 个汉字，超出 %d–%d"
                      % (lineno, name, zhname, n, KW_MIN_HANZI, KW_MAX_HANZI))
        print("  [错误] 第 %d 行（%s）：`%s` 汉字数 %d，应在 %d–%d 之间"
              % (lineno, name, zhname, n, KW_MIN_HANZI, KW_MAX_HANZI))
else:
    _longest = max(all_rows, key=lambda r: hanzi_count(r[2]))
    _shortest = min(all_rows, key=lambda r: hanzi_count(r[2]))
    print("  [通过] %d 个译名的汉字数都在 %d–%d 之间（最短 `%s`，最长 `%s`）"
          % (len(all_rows), KW_MIN_HANZI, KW_MAX_HANZI, _shortest[2], _longest[2]))

# 自测：这个检查必须证明自己【会失败】。一条永远返回"通过"的检查等于没有检查
# —— 本项目吃过这个亏（"校核器会查角色表"而检查并不存在，被外部复核者用三份
# 违规副本实测 problems=0 才暴露）。
_probe = ["甲", "甲乙", "甲乙丙丁戊己", "甲乙丙丁戊己庚", "字符8位"]
_want = [True, False, False, True, False]   # 1字/2字/6字/7字/带数字按3汉字
_got = [bad_length(x) for x in _probe]
if _got != _want:
    errors.append("长度检查自测失败：%r -> %r，期望 %r" % (_probe, _got, _want))
    print("  [错误] 长度检查自测失败：%r -> %r，期望 %r" % (_probe, _got, _want))
else:
    print("  [通过] 长度检查自测：1 字与 7 字被抓，2 字与 6 字放行，"
          "`字符8位` 按 3 个汉字计")

# ------------------------------------------------- 11. 中文预处理指令拼写表
section("11. 中文预处理指令拼写检查（ChineseDirectives.def）")

# 这一节是 2026-09-24 新增的。它校核的是【另一张表】——预处理指令的中文拼写。
# 两张表分开是有原因的，见 ChineseDirectives.def 头部第 5 条：
#   * 关键字有标志位（TokenKey），指令【没有】；
#   * 依赖扫描器（DependencyDirectivesScanner.cpp）只认字符串，读不到标志位。
# 所以指令拼写必须自有一张表，而这张表有三处读取者，必须机器校核一致性。

P_ZH_DIR = os.path.join(ROOT, r"clang\include\clang\Basic\ChineseDirectives.def")
P_SCAN = os.path.join(ROOT, r"clang\lib\Lex\DependencyDirectivesScanner.cpp")
P_IDTAB = os.path.join(ROOT, r"clang\lib\Basic\IdentifierTable.cpp")

zh_dir_text = read(P_ZH_DIR)
scan_text = read(P_SCAN)
idtab_text = read(P_IDTAB)

# --- 11.0 解析 PPKEYWORD 英文名（TokenKinds.def 是唯一权威） ---
pp_keywords = [m.group(1) for m in
               re.finditer(r"^\s*PPKEYWORD\((\w+)\)", tk, re.M)]
pp_keyword_set = set(pp_keywords)
print("  解析到 TokenKinds.def 的 PPKEYWORD：%d 条（含哨兵 not_keyword）"
      % len(pp_keywords))

# --- 11.1 解析 ChineseDirectives.def ---
dir_rows = []
for lineno, line in enumerate(zh_dir_text.splitlines(), 1):
    m = re.match(r"^\s*ZH_DIRECTIVE\(\s*(\w+)\s*,\s*([^)]+?)\s*\)\s*$", line)
    if m:
        dir_rows.append((lineno, m.group(1), m.group(2)))

if not dir_rows:
    errors.append("ChineseDirectives.def 里一条 ZH_DIRECTIVE 都没解析到")
    print("  [错误] 一条 ZH_DIRECTIVE 都没解析到")
else:
    print("  解析到中文指令拼写：%d 条" % len(dir_rows))

# 自测：解析器必须真的能解析出东西，否则下面的检查全是"空集通过"
if len(dir_rows) != 22:
    errors.append("ChineseDirectives.def 解析到 %d 条，期望 22 条"
                  % len(dir_rows))
    print("  [错误] 解析到 %d 条，期望 22 条" % len(dir_rows))
else:
    print("  [通过] 条目数 22（8 条件 ＋ 1 包含 ＋ 2 宏替换 ＋ 1 行号 ＋ 1 错误 "
          "＋ 1 编译指示 ＋ 1 嵌入 ＋ 2 模块 ＋ 5 GNU/遗留）")

# --- 11.2 英文名必须真实存在（否则 tok::pp_##EN 编译不过） ---
def bad_dir_names(rows, kwset):
    return [(ln, en) for ln, en, zh in rows if en not in kwset]

_bad = bad_dir_names(dir_rows, pp_keyword_set)
if _bad:
    for ln, en in _bad:
        errors.append("ChineseDirectives.def 第 %d 行：英文名 `%s` 不在 "
                      "TokenKinds.def 的 PPKEYWORD 中，tok::pp_%s 不存在"
                      % (ln, en, en))
        print("  [错误] 第 %d 行：`%s` 不是 PPKEYWORD" % (ln, en))
else:
    print("  [通过] %d 个英文名全部存在于 TokenKinds.def" % len(dir_rows))

# 自测：这个检查必须证明自己会失败
_probe = [(1, "include", "包含"), (2, "nosuchdirective", "不存在")]
if not bad_dir_names(_probe, pp_keyword_set):
    errors.append("指令英文名检查自测失败：伪造的 nosuchdirective 没被抓到")
    print("  [错误] 英文名检查自测失败")
else:
    print("  [通过] 英文名检查自测：伪造的 `nosuchdirective` 被抓到")

# --- 11.3 表内译名唯一 + 英文名唯一 ---
def dup_dir_zh(rows):
    seen, dups = {}, []
    for ln, en, zh in rows:
        if zh in seen:
            dups.append((zh, seen[zh], en))
        seen[zh] = en
    return dups

def dup_dir_en(rows):
    seen, dups = {}, []
    for ln, en, zh in rows:
        if en in seen:
            dups.append(en)
        seen[en] = zh
    return dups

_dz = dup_dir_zh(dir_rows)
_de = dup_dir_en(dir_rows)
if _dz:
    for zh, a, b in _dz:
        errors.append("ChineseDirectives.def 译名 `%s` 重复（%s 与 %s）" % (zh, a, b))
        print("  [错误] 译名 `%s` 重复：%s 与 %s" % (zh, a, b))
elif _de:
    for en in _de:
        errors.append("ChineseDirectives.def 英文名 `%s` 重复" % en)
        print("  [错误] 英文名 `%s` 重复" % en)
else:
    print("  [通过] %d 个英文名与 %d 个译名均互不重复"
          % (len(dir_rows), len(dir_rows)))

if not dup_dir_zh([(1, "a", "同"), (2, "b", "同")]):
    errors.append("译名唯一性检查自测失败：重复译名没被抓到")
    print("  [错误] 译名唯一性检查自测失败")
else:
    print("  [通过] 译名唯一性检查自测：重复译名被抓到")

# --- 11.4 汉字数 2–6（与关键字同一定则） ---
_bad_len = [(ln, en, zh) for ln, en, zh in dir_rows if bad_length(zh)]
if _bad_len:
    for ln, en, zh in _bad_len:
        errors.append("ChineseDirectives.def 第 %d 行：译名 `%s`（%s）汉字数 %d，"
                      "应在 %d–%d 之间" % (ln, zh, en, hanzi_count(zh),
                                            KW_MIN_HANZI, KW_MAX_HANZI))
        print("  [错误] 第 %d 行 `%s` 汉字数 %d" % (ln, zh, hanzi_count(zh)))
else:
    _l = max(dir_rows, key=lambda r: hanzi_count(r[2]))
    print("  [通过] %d 个译名的汉字数都在 %d–%d 之间（最长 `%s`，%d 字）"
          % (len(dir_rows), KW_MIN_HANZI, KW_MAX_HANZI, _l[2],
             hanzi_count(_l[2])))

# --- 11.4b 字节长度必须 < 20（SkipExcludedConditionalBlock 的栈缓冲） ---
# PPDirectives.cpp 的 SkipExcludedConditionalBlock() 里有一句
#     char DirectiveBuf[20];
# 且用 `RI.size() < 20` 作为「不必清洗、可直接引用」的条件。超过 20 字节的
# 指令名会被那条 `IdLen >= 20 -> continue` 分支【静默忽略】，也就是
# `#结束如果` 永远弹不出条件栈。汉字每字 3 字节，2–6 字 = 6–18 字节，
# 所以这条安全边界是【由 2–6 汉字定则推出来的】—— 在这里显式钉住它，
# 将来有人加 7 字译名时会在本脚本失败，而不是在编译器里静默出错。
_bad_bytes = [(ln, en, zh) for ln, en, zh in dir_rows
              if len(zh.encode("utf-8")) >= 20]
if _bad_bytes:
    for ln, en, zh in _bad_bytes:
        errors.append("ChineseDirectives.def 第 %d 行：译名 `%s`（%s）占 %d 字节，"
                      "达到或超过 PPDirectives.cpp 里 DirectiveBuf[20] 的上限，"
                      "会被跳过逻辑静默忽略"
                      % (ln, zh, en, len(zh.encode("utf-8"))))
        print("  [错误] 第 %d 行 `%s` 占 %d 字节 >= 20" % (ln, zh, len(zh.encode("utf-8"))))
else:
    _mx = max(dir_rows, key=lambda r: len(r[2].encode("utf-8")))
    print("  [通过] 最长译名 `%s` 占 %d 字节 < 20"
          "（PPDirectives.cpp 的 DirectiveBuf[20] 上限）"
          % (_mx[2], len(_mx[2].encode("utf-8"))))

# 自测：20 字节的假译名必须被抓到
if not [(1, "x", "甲乙丙丁戊己庚")] or not [
        r for r in [(1, "x", "甲乙丙丁戊己庚")]
        if len(r[2].encode("utf-8")) >= 20]:
    errors.append("字节长度检查自测失败：7 汉字（21 字节）没被算出 >= 20")
    print("  [错误] 字节长度检查自测失败")
else:
    print("  [通过] 字节长度检查自测：7 汉字译名（21 字节）会被抓到")

# --- 11.5 跨表重名：只有指向【同一个英文】时才允许 ---
# 例如 `如果` 既是关键字 if 又是指令 if —— 这与英文 `if` 的双重身份一致
# （指令名在 ParsingPreprocessorDirective 下不做关键字映射）。
# 但若把 `#否则` 指给 endif 而 `否则` 是 else，就是真错误。
kw_spelling_to_en = {}
for _ln, _en, _zh, _fl in all_rows:
    kw_spelling_to_en.setdefault(_zh, _en)

def cross_conflicts(rows, kwmap):
    out = []
    for ln, en, zh in rows:
        if zh in kwmap and kwmap[zh] != en:
            out.append((ln, en, zh, kwmap[zh]))
    return out

_cc = cross_conflicts(dir_rows, kw_spelling_to_en)
_same_name = [(en, zh) for ln, en, zh in dir_rows if kw_spelling_to_en.get(zh) == en]
if _cc:
    for ln, en, zh, kwen in _cc:
        errors.append("ChineseDirectives.def 第 %d 行：`%s` 指给 %s，"
                      "但它是关键字 %s 的拼写 —— 两者英文必须相同"
                      % (ln, zh, en, kwen))
        print("  [错误] `%s` 是关键字 %s 的拼写，不能指给指令 %s" % (zh, kwen, en))
else:
    if _same_name:
        print("  [通过] 与关键字同名的拼写 %d 个，英文名全部一致：%s"
              % (len(_same_name),
                 "、".join("%s(%s)" % (zh, en) for en, zh in _same_name)))
    else:
        print("  [通过] 没有与关键字重名的拼写")

# 自测：必须能抓出「英文不同却共用拼写」
if not cross_conflicts([(1, "endif", "否则")], {"否则": "else"}):
    errors.append("跨表重名检查自测失败：endif/否则(else) 没被抓到")
    print("  [错误] 跨表重名检查自测失败")
else:
    print("  [通过] 跨表重名检查自测：把 `否则` 指给 endif 会被抓到")

# --- 11.6 依赖扫描器的中文 .Case() 必须与表一致 ---
# 扫描器自有一张字符串表（不能 include 本表，因为 DirectiveKind 里没有
# pp_module）。漏一条的后果不是「回退到完整预处理器」，而是【静默丢依赖】——
# 见 DependencyDirectivesScanner.cpp 里那段注释。所以必须机器校核。
_m = re.search(r'\.Case\("include",\s*pp_include\)', scan_text)
if not _m:
    errors.append("在 DependencyDirectivesScanner.cpp 里找不到指令 StringSwitch")
    print("  [错误] 找不到指令 StringSwitch")
    scan_en, scan_zh = [], {}
else:
    _tail = scan_text[_m.start():]
    _tail = _tail[:_tail.index(".Default(")]
    _cases = re.findall(r'\.Case\("([^"]+)",\s*(pp_\w+)\)', _tail)
    scan_en = [c for c, v in _cases if c.isascii()]
    scan_zh = {c: v for c, v in _cases if not c.isascii()}
    print("  扫描器指令表：英文 %d 条，中文 %d 条" % (len(scan_en), len(scan_zh)))

# 期望：表里所有「英文名出现在扫描器英文表中」的条目，其译名必须出现在扫描器里
expect_zh = {zh: "pp_" + en for en, zh in ((r[1], r[2]) for r in dir_rows)
             if en in scan_en}

def scan_mismatches(scan_zh_map, expect_map):
    missing = {k: v for k, v in expect_map.items() if scan_zh_map.get(k) != v}
    extra = {k: v for k, v in scan_zh_map.items() if k not in expect_map}
    return missing, extra

_miss, _extra = scan_mismatches(scan_zh, expect_zh)
if _miss or _extra:
    for k, v in _miss.items():
        errors.append("DependencyDirectivesScanner.cpp 缺少或写错中文指令 "
                      "`%s`（应为 %s）" % (k, v))
        print("  [错误] 扫描器缺少/写错 `%s` -> %s" % (k, v))
    for k, v in _extra.items():
        errors.append("DependencyDirectivesScanner.cpp 多出中文指令 `%s` -> %s"
                      "（ChineseDirectives.def 里没有）" % (k, v))
        print("  [错误] 扫描器多出 `%s` -> %s" % (k, v))
else:
    print("  [通过] 扫描器 %d 条中文指令与 ChineseDirectives.def 完全一致：%s"
          % (len(scan_zh), "、".join(sorted(scan_zh))))

# 自测：删掉一条必须被抓到
_m2, _e2 = scan_mismatches({k: v for k, v in scan_zh.items() if k != "包含"},
                           expect_zh)
if not _m2:
    errors.append("扫描器一致性检查自测失败：删掉 `包含` 没被抓到")
    print("  [错误] 扫描器一致性检查自测失败")
else:
    print("  [通过] 扫描器一致性检查自测：删掉 `包含` 会被抓到")

# --- 11.7 接线检查：IdentifierTable.cpp 真的读了这张表 ---
if '#include "clang/Basic/ChineseDirectives.def"' not in idtab_text:
    errors.append("IdentifierTable.cpp 没有 include ChineseDirectives.def，"
                  "表被定义了却没人读")
    print("  [错误] IdentifierTable.cpp 没有 include ChineseDirectives.def")
else:
    print("  [通过] IdentifierTable.cpp 引用了 ChineseDirectives.def")

# 新表必须真的能被安装/构建到。clang/CMakeLists.txt 用
#   install(DIRECTORY include/clang ... FILES_MATCHING PATTERN "*.def")
# 通配收录 .def，所以新表自动被覆盖 —— 但这条通配是【隐式契约】，
# 一旦上游改成白名单，新表会静默不被安装。在这里钉住它。
_clang_cml = read(os.path.join(ROOT, r"clang\CMakeLists.txt"))
if 'PATTERN "*.def"' in _clang_cml:
    print("  [通过] clang/CMakeLists.txt 用 PATTERN \"*.def\" 通配安装，"
          "新表自动被收录（无需改 CMake）")
else:
    errors.append("clang/CMakeLists.txt 不再用 PATTERN \"*.def\" 通配安装头文件，"
                  "ChineseDirectives.def 可能不会被安装 —— 请显式加入安装列表")
    print("  [错误] clang/CMakeLists.txt 不再通配安装 .def")

# --- 11.8 诊断正文里的指令拼写必须是中文 -------------------------------
# 【方针】2026-09-24 第二次裁定。原来这一节记的是"已知不一致，未处理，
#   理由是诊断里引用的是规范英文拼写"。那条理由被推翻了，因为关键字那边的
#   方针不是"回显用户写的拼写"，而是【永远显示规范中文拼写】：
#       写 static_assert  -> 诊断输出 "（关键字） 静态断言"
#       写 静态断言       -> 诊断输出 "（关键字） 静态断言"
#   （实测见 docs\预处理指令汉化\预处理指令汉化.md 第七节）
#   指令是功能集里唯一走相反方针的地方，所以现在统一：正文里出现的可译指令
#   一律写中文拼写。
#
# 【本条校核本身踩过的两个坑，都写进自测】
#   1) 只许看【字符串字面量】。第一版整文件替换把文件头注释里的 60 处文档
#      示例也改了；第二版按行跳过注释，又改了 .def 自己的 include guard
#      （`#ifndef ZH_DIAG` / `#define ZH_DIAG(...)` —— 那是真的预处理指令）。
#   2) `#pragma <子名>` 必须放过。omp / clang / MS 的子名字层是另一套命名
#      空间，ChineseDirectives.def 有意不收，所以那 164 处保持英文。
P_DIAG = os.path.join(ROOT, r"clang\include\clang\Basic\ChineseDiagnostics.def")
diag_text = read(P_DIAG)

# 有意不收中文的 6 条（见 ChineseDirectives.def 第 8 条）
NOT_TRANSLATED = {"__include_macros", "__preprocessed_module",
                  "__preprocessed_import", "__public_macro",
                  "__private_macro", "sccs"}

# 允许在正文里保持英文的指令名：pragma（子名字层）+ 上面 6 条
allowed_english = {"pragma"} | NOT_TRANSLATED
en2zh_dir = {en: zh for _ln, en, zh in dir_rows}
MUST_BE_CHINESE = {k: v for k, v in en2zh_dir.items() if k not in allowed_english}

_STR_LIT = re.compile(r'"(?:[^"\\]|\\.)*"')
_HASH_NAME = re.compile(r"#([A-Za-z_]\w*)")


def scan_diag_directive_spellings(text):
    """Return [(lineno, id, english)] for English directive spellings that
    appear INSIDE string literals. Comments and code are never inspected."""
    bad = []
    cur_id = "?"
    for lineno, line in enumerate(text.splitlines(), 1):
        m = re.search(r"ZH_DIAG\(\s*(\w+)", line)
        if m:
            cur_id = m.group(1)
        if line.lstrip().startswith("//"):
            continue
        for lit in _STR_LIT.findall(line):
            for name in _HASH_NAME.findall(lit):
                if name in MUST_BE_CHINESE:
                    bad.append((lineno, cur_id, name))
    return bad


_dm = scan_diag_directive_spellings(diag_text)
if _dm:
    for lineno, did, name in _dm[:20]:
        errors.append("ChineseDiagnostics.def 第 %d 行（%s）：正文里仍写英文指令 "
                      "`#%s`，应为 `#%s`" % (lineno, did, name, MUST_BE_CHINESE[name]))
        print("  [错误] 第 %d 行 %s：正文里仍是 #%s（应为 #%s）"
              % (lineno, did, name, MUST_BE_CHINESE[name]))
    if len(_dm) > 20:
        print("  ...（共 %d 处）" % len(_dm))
else:
    print("  [通过] 诊断正文里的可译指令拼写全部是中文（%d 条译名参与检查）"
          % len(MUST_BE_CHINESE))

# 自测一：正文里的英文指令拼写必须被抓到
_p1 = scan_diag_directive_spellings('ZH_DIAG(x, "见 #include 指令")')
# 自测二：.def 自己的 include guard 不可以被抓到（整行替换会误伤它）
_p2 = scan_diag_directive_spellings("#ifndef ZH_DIAG\n#define ZH_DIAG(NAME, TEXT)")
# 自测三：注释里的文档示例不可以被抓到
_p3 = scan_diag_directive_spellings('// 例如 "#include <x.h>" 这样写')
# 自测四：pragma 子名字层必须放过
_p4 = scan_diag_directive_spellings('ZH_DIAG(y, "\'#pragma omp atomic\' 非法")')

if not _p1:
    errors.append("指令拼写校核自测失败：正文里的 #include 没被抓到")
    print("  [错误] 自测一失败：正文里的 #include 没被抓到")
elif _p2 or _p3 or _p4:
    errors.append("指令拼写校核自测失败：误伤了 include guard / 注释 / pragma "
                  "（%r %r %r）" % (_p2, _p3, _p4))
    print("  [错误] 自测二/三/四失败：误伤 guard=%r 注释=%r pragma=%r"
          % (_p2, _p3, _p4))
else:
    print("  [通过] 指令拼写校核自测：正文英文被抓到；include guard、注释、"
          "#pragma 子名字层都不误伤")

# ---------------------------------------------------------------- 总结
section("验证结论")
print("  解析到中文关键字条目：%d"
      "（ZH_KEYWORD %d ＋ ZH_VIRT_SPECIFIER %d ＋ ZH_OPERATOR_KEYWORD %d）"
      % (len(all_rows), len(rows), len(virt_rows), len(op_rows)))
print("  错误：%d" % len(errors))
if errors:
    for e in errors:
        print("    - " + e)
    print("")
    print("  结果：未通过，请修正后重跑。")
    sys.exit(1)
else:
    print("")
    print("  结果：全部通过。")
    print("  下一步：确保 MSVC 以 /utf-8 编译 IdentifierTable.cpp 与 TokenKinds.cpp")
    print("  （已在 clang/lib/Basic/CMakeLists.txt 中按源文件设置），随后构建 clang。")
    sys.exit(0)
