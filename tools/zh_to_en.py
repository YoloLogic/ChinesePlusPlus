# -*- coding: utf-8 -*-
"""
中文关键字源码 → 等价英文关键字源码（机械替换，证明"没有锁定"）

用法:
    python E:\\Chinese++\\tools\\zh_to_en.py <输入.cpp> [输出.cpp]

数据源: clang/include/clang/Basic/ChineseKeywords.def

为什么这个替换是【精确】的
--------------------------
本编译器的中文关键字识别完全按词法规则：一个标识符「整段」等于某个中文关键字
拼写时才是关键字，否则就是普通标识符。所以

    整数 甲     -> 两个 token：关键字 整数 + 标识符 甲
    整数甲      -> 一个 token：标识符「整数甲」，不是关键字
    如果(甲)    -> 关键字 如果 + ( + …

因此本工具只做一件事：把每一段「连续标识符字符」取出来，若它整段等于某个中文
关键字的拼写，就换成对应的英文关键字；否则原样保留。

注释与字符串/字符字面量会被跳过（注释里出现的词不该被改，字符串里的
「无法识别的字符」更不能变成「无法识别的 char」）。
"""

import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = r"E:\Chinese++"
SRC  = os.path.join(ROOT, "LLVM-main", "clang", "include", "clang", "Basic", "ChineseKeywords.def")
TOKKINDS = os.path.join(ROOT, "LLVM-main", "clang", "include", "clang", "Basic", "TokenKinds.def")

# 第一节～第五节：普通中文关键字。参数顺序 (英文, 中文, 标志)
ENTRY = re.compile(r"^\s*ZH_KEYWORD\(\s*([A-Za-z_]\w*)\s*,\s*([^\s,]+)\s*,")

# 第六节：中文上下文关键字（重写 / 最终）。override 与 final 在 C++ 里不是关键字，
# 而是“有特殊含义的标识符”，所以它们在 .def 里用另一张表；参数顺序与第一节相同。
VIRT = re.compile(r"^\s*ZH_VIRT_SPECIFIER\(\s*([A-Za-z_]\w*)\s*,\s*([^\s,)]+)")

# 第七节：运算符替代拼写（并且 / 或者 / 并非 …）。注意参数顺序【反了】——中文在前，
# 后面是 tok:: 别名（ampamp / pipepipe …）而不是英文单词，所以要再查一次
# TokenKinds.def，换成 and / or / not 这些能写给 stock clang 的拼写。
OPER = re.compile(r"^\s*ZH_OPERATOR_KEYWORD\(\s*([^\s,]+)\s*,\s*([A-Za-z_]\w*)\s*\)")
OPALIAS = re.compile(r"^\s*CXX_KEYWORD_OPERATOR\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\)")

# 第八节：上下文关键字（module / import）。参数顺序 (英文, 中文, setter)，
# 前两个与第一节相同；第三个是 IdentifierInfo 上的 setter 名，本脚本用不到。
CTX = re.compile(r"^\s*ZH_CONTEXTUAL_KEYWORD\(\s*([A-Za-z_]\w*)\s*,\s*([^\s,]+)\s*,")


def load_op_words():
    """tok:: 别名 -> 英文运算符拼写，例如 ampamp -> and、exclaimequal -> not_eq"""
    table = {}
    with io.open(TOKKINDS, encoding="utf-8") as fh:
        for line in fh:
            m = OPALIAS.match(line)
            if m:
                table[m.group(2)] = m.group(1)
    return table


def load_mapping():
    """中文拼写 -> 英文关键字（第一、六、七、八节全部纳入）"""
    table = {}
    op_words = load_op_words()
    with io.open(SRC, encoding="utf-8") as fh:
        for line in fh:
            m = ENTRY.match(line)
            if m:
                table[m.group(2)] = m.group(1)
                continue
            m = VIRT.match(line)
            if m:
                table[m.group(2)] = m.group(1)
                continue
            m = CTX.match(line)
            if m:
                table[m.group(2)] = m.group(1)
                continue
            m = OPER.match(line)
            if m:
                word = op_words.get(m.group(2))
                if word:
                    table[m.group(1)] = word
    return table


def is_ident_char(ch):
    # 与词法器一致：字母/数字/下划线/$ 连续成一段标识符；中文属于字母
    return ch.isalnum() or ch == "_" or ch == "$"


def translate(text, table):
    out = []
    i, n, hits = 0, len(text), 0
    while i < n:
        # 行注释
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(text[i:j]); i = j; continue
        # 块注释
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(text[i:j]); i = j; continue
        # 字符串 / 字符字面量
        c = text[i]
        if c == '"' or c == "'":
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2; continue
                if text[j] == c:
                    j += 1; break
                j += 1
            out.append(text[i:j]); i = j; continue
        # 一段标识符字符
        if is_ident_char(c):
            j = i
            while j < n and is_ident_char(text[j]):
                j += 1
            word = text[i:j]
            if word in table:            # 整段等于中文关键字 -> 才是关键字
                out.append(table[word]); hits += 1
            else:
                out.append(word)         # 用户自己的中文标识符，原样保留
            i = j; continue
        out.append(c); i += 1
    return "".join(out), hits


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ".english.cpp"
    if not os.path.isfile(src):
        print("找不到输入文件: %s" % src)
        return 1

    table = load_mapping()
    if not table:
        print("没有从 %s 解析到关键字表" % SRC)
        return 1

    with io.open(src, encoding="utf-8") as fh:
        text = fh.read()
    result, hits = translate(text, table)

    with io.open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(result)

    print("关键字表: %d 条" % len(table))
    print("已替换:   %d 处中文关键字" % hits)
    print("输出:     %s" % dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
