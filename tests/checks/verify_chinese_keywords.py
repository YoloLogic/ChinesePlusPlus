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
section("2. 译名唯一性检查")
seen = {}
dups = []
for lineno, name, zhname, flags in rows:
    if zhname in seen:
        dups.append((zhname, seen[zhname], name, lineno))
    else:
        seen[zhname] = name
if dups:
    for zhname, first, second, lineno in dups:
        errors.append("译名 `%s` 重复：%s 与 %s" % (zhname, first, second))
        print("  [错误] 译名 `%s` 重复：先注册为 %s，第 %d 行又注册为 %s" % (zhname, first, lineno, second))
else:
    print("  [通过] %d 个译名互不重复" % len(rows))

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
for lineno, name, zhname, flags in rows:
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
allchars = sorted({ch for _, _, zhname, _ in rows for ch in zhname})
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
           for lineno, name, zhname, flags in rows if bad_length(zhname)]
if bad_len:
    for lineno, name, zhname, n in bad_len:
        errors.append("第 %d 行（%s）：译名 `%s` 有 %d 个汉字，超出 %d–%d"
                      % (lineno, name, zhname, n, KW_MIN_HANZI, KW_MAX_HANZI))
        print("  [错误] 第 %d 行（%s）：`%s` 汉字数 %d，应在 %d–%d 之间"
              % (lineno, name, zhname, n, KW_MIN_HANZI, KW_MAX_HANZI))
else:
    _longest = max(rows, key=lambda r: hanzi_count(r[2]))
    _shortest = min(rows, key=lambda r: hanzi_count(r[2]))
    print("  [通过] %d 个译名的汉字数都在 %d–%d 之间（最短 `%s`，最长 `%s`）"
          % (len(rows), KW_MIN_HANZI, KW_MAX_HANZI, _shortest[2], _longest[2]))

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

# ---------------------------------------------------------------- 总结
section("验证结论")
print("  解析到中文关键字条目：%d" % len(rows))
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
