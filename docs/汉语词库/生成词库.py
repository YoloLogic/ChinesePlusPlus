# -*- coding: utf-8 -*-
"""
生成 Chinese++ 输入法词库（每行一条中文译名）。

两个来源，**都是生成的，没有一条是手打的**（本仓库既定规矩：手写的副本一定会漂移）：

  一、语言本身 —— `packaging/中文对照表.md`
      由 tools/make_cheatsheet.py 从编译器真正在用的那两张表生成。
      88 关键字 + 11 运算符替代拼写 + 22 预处理指令 + 主函数。

  二、汉语标准库 —— `zhstdlib/` 里 73 个中文头
      由 tools/make_zhstdlib2.ps1（抄+派生轨道）与 make_zhalias.ps1（别名轨道）生成，
      就是编译器真正在用的那份实现。词条 = 头里的中文标识符。

筛选规则（写在这里是为了能复核，不是为了"好看"）
------------------------------------------------
  · 去掉 `_` 开头     —— MSVC 内部命名约定，用户不会去打字
  · 去掉 `*实现` 结尾 —— `标准::细节` 那一层的实现类，同上
  · 去掉单个汉字      —— 输入法本来就有这个字，加进去只增噪
  · 与关键字重合的自动去重

自检
----
两处都拿「文档自己声明的条数」对拍，不符即报错退出：
  · 中文对照表章节标题写着「关键字（88 个）」……
  · 汉语标准库章节标题写着「32 个 / 16 个 / 25 个」，合计须等于 zhstdlib/ 的文件数

用法
----
    python 生成词库.py

输出
----
    汉语编程Chinese++输入法词库.txt
    编码 UTF-8 with BOM，换行 CRLF，一行一条，无表头无注释。
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

OUT = os.path.join(HERE, '汉语编程Chinese++输入法词库.txt')
OUT_GBK = os.path.join(HERE, '汉语编程Chinese++输入法词库.GBK.txt')
MAX_CHARS = 64          # 用户要求：每条长度小于 64 个汉字

CHEATSHEET_CANDS = [
    os.path.join(ROOT, 'packaging', '中文对照表.md'),
    r'E:\Chinese++-0.1-win64\中文对照表.md',
    r'E:\ChinesePlusPlus\中文对照表.md',
]
ZHLIB = os.path.join(ROOT, 'zhstdlib')
USAGE_DOC = os.path.join(ROOT, 'docs', '标准库汉化', '汉语标准库-用法.md')

CELL = re.compile(r'`([^`]+)`')
DECLARED = re.compile(r'（(\d+)\s*[个条]）')
SECTION_OF = [('关键字', 'kw'), ('运算符', 'ops'), ('预处理指令', 'dir'), ('入口点', 'entry')]

# 中文标识符：整词切分 —— 把一整段「字母/数字/下划线/汉字」当一个 token，
# 只保留含汉字的那些。
#
# **不能**写成「汉字开头 + 汉字/数字续」：标识符里夹拉丁字母时会被切碎。
# 实测 `_复制N个非检查4`（`_Copy_n_unchecked4` 的译名）会被切成
# `复制` 和 `个非检查4` 两段，后者是纯残渣。整词切法下它是一整个 token，
# 随后被 `_` 前缀规则整条剔掉。
IDENT_RUN = re.compile(r'[A-Za-z0-9_\u4e00-\u9fff]+')
HAS_ZH = re.compile(r'[\u4e00-\u9fff]')
COMMENT = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)


# ---------------------------------------------------------------------------
#  一、语言本身
# ---------------------------------------------------------------------------
def find_cheatsheet():
    for p in CHEATSHEET_CANDS:
        if os.path.exists(p):
            return p
    sys.exit('找不到 中文对照表.md，试过：\n  ' + '\n  '.join(CHEATSHEET_CANDS))


def extract_language(path):
    groups = {'kw': [], 'ops': [], 'dir': [], 'entry': []}
    declared = {}
    section = None

    with open(path, encoding='utf-8') as f:
        for line in f:
            if line.startswith('## '):
                section = None
                for word, key in SECTION_OF:
                    if word in line:
                        section = key
                        break
                m = DECLARED.search(line)
                if section and m:
                    declared[section] = int(m.group(1))
                continue

            # 只认真正的表格行。章节里的说明句也含反引号代码
            # （「其中 `重写`（override）…」「原本的 `and` / `or` / `not`」
            #   「同一条 `#if` 链里混着写」），不卡这个会混进 `重写` / `and` / `if`。
            if section is None or not line.lstrip().startswith('|'):
                continue

            cells = CELL.findall(line)
            if not cells:
                continue

            # 关键字表是「中文|英文|中文|英文」四列 —— 第 1 和第 3 列**都是**中文译名。
            # 只取第 1 列会漏掉一半（44/88），还会漏掉与指令重合的 `模块`。
            names = [cells[0], cells[2]] if (section == 'kw' and len(cells) >= 3) else [cells[0]]
            for name in names:
                # 预处理指令写作 `#包含`；词库里存 `包含` —— `#` 是打字时另外敲的，
                # 拼音打不出 `#`，带 `#` 的词条在输入法里永远选不到。
                if section == 'dir':
                    name = name.lstrip('#')
                if name:
                    groups[section].append(name)

    return groups, declared


# ---------------------------------------------------------------------------
#  二、汉语标准库
# ---------------------------------------------------------------------------
def declared_header_total(doc):
    """从用法文档的章节标题里数出「应有几个头」。"""
    if not os.path.exists(doc):
        return None
    parts = []
    for line in open(doc, encoding='utf-8'):
        m = re.match(r'^##\s*[二三四五]、.*?（(\d+)\s*个', line)
        if m:
            parts.append(int(m.group(1)))
    return (parts, sum(parts)) if parts else None


def extract_stdlib():
    """返回 (头名列表, 词条->出现次数)。"""
    if not os.path.isdir(ZHLIB):
        sys.exit('找不到汉语标准库目录: %s' % ZHLIB)

    headers, freq = [], {}
    for fn in sorted(os.listdir(ZHLIB)):
        p = os.path.join(ZHLIB, fn)
        if not os.path.isfile(p):
            continue
        headers.append(fn)
        txt = open(p, encoding='utf-8', errors='replace').read()
        txt = COMMENT.sub(' ', txt)                 # 注释是中文散文，不能当词条
        for t in IDENT_RUN.findall(txt):
            if HAS_ZH.search(t):
                freq[t] = freq.get(t, 0) + 1
    return headers, freq


# ---------------------------------------------------------------------------
def main():
    labels = [('kw', '关键字'), ('ops', '运算符拼写'), ('dir', '预处理指令'), ('entry', '入口点')]

    # ---- 一、语言本身 ----
    sheet = find_cheatsheet()
    groups, declared = extract_language(sheet)

    print('一、语言本身   <- %s' % sheet)
    mismatch = []
    for key, label in labels:
        n = len(groups[key])
        want = declared.get(key)
        if want is not None and want != n:
            mismatch.append((label, want, n))
        print('    %-10s %3d%s' % (label, n, '   <<< 表头声明 %d，不符！' % want if (want is not None and want != n) else ''))
    if mismatch:
        sys.exit('中文对照表抽取条数与表头声明不符，拒绝写出：%s' % mismatch)

    # ---- 二、汉语标准库 ----
    headers, freq = extract_stdlib()
    dt = declared_header_total(USAGE_DOC)
    print('')
    print('二、汉语标准库 <- %s' % ZHLIB)
    print('    中文头文件 %3d' % len(headers))
    if dt:
        parts, total = dt
        flag = '' if total == len(headers) else '   <<< 用法文档声明 %s，不符！' % parts
        print('    文档声明   %3d  %s%s' % (total, parts, flag))
        if total != len(headers):
            sys.exit('中文头数量与用法文档声明不符，拒绝写出：文档 %d，目录 %d' % (total, len(headers)))

    under = [t for t in freq if t.startswith('_')]
    impl = [t for t in freq if t.endswith('实现')]
    single = [t for t in freq if len(t) == 1]
    keep = sorted(t for t in freq
                  if not t.startswith('_') and not t.endswith('实现') and len(t) > 1)
    # 注意：单字规则**只管头里的标识符，不管头名**。
    # `zhstdlib/位`、`栈`、`比` 就是单字头（`#包含 <位>`），那是真实 API 必须留 ——
    # 下面 headers 是直接拼进结果的，没走 keep 的过滤。这不是漏网，是刻意。
    print('    抽出中文标识符（去重） %4d' % len(freq))
    print('      - `_` 开头内部名      %4d' % len(under))
    print('      - `*实现` 细节层      %4d' % len(impl))
    print('      - 单个汉字            %4d' % len(single))
    print('      => 保留               %4d' % len(keep))

    # ---- 合并去重 ----
    ordered, seen, dup = [], set(), []
    for key, _ in labels:
        for w in groups[key]:
            if w in seen:
                dup.append(w)
                continue
            seen.add(w)
            ordered.append(w)
    print('')
    print('语言级 %d 条（合并重复 %d: %s）' % (len(ordered), len(dup), '、'.join(dup)))

    lib_added = 0
    for w in headers + keep:
        if w in seen:
            continue
        seen.add(w)
        ordered.append(w)
        lib_added += 1
    print('标准库新增 %d 条（头名 + 头里的中文标识符，与语言级重合的不重复计入）' % lib_added)

    # ---- 校验 ----
    bad_len = [w for w in ordered if len(w) >= MAX_CHARS]
    bad_chr = [w for w in ordered if any(c in w for c in '|\r\n\t')]
    if bad_len:
        sys.exit('超长词条（>=%d 字）: %s' % (MAX_CHARS, bad_len))
    if bad_chr:
        sys.exit('含非法字符: %s' % bad_chr)

    longest = max(ordered, key=len)
    print('')
    print('合计 %d 条   最长 %d 字 —— %s' % (len(ordered), len(longest), longest))

    body = '\n'.join(ordered) + '\n'

    # 仓库里留 UTF-8：可读、可 diff
    with open(OUT, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(body)
    print('已写出: %s' % OUT)
    print('  UTF-8 with BOM   换行 CRLF   %d 行' % len(ordered))

    # 给搜狗的那份：GB18030（GBK 的超集），无 BOM、CRLF。
    # 依据：搜狗文本词库要求「字符编码集为 ANSI、GBK 或 GB18030；
    # 换行符为 Windows 风格，即 Windows(CR LF)」。
    with open(OUT_GBK, 'w', encoding='gb18030', newline='\r\n') as f:
        f.write(body)
    print('已写出: %s' % OUT_GBK)
    print('  GB18030   无 BOM   换行 CRLF   %d 行' % len(ordered))


if __name__ == '__main__':
    main()
