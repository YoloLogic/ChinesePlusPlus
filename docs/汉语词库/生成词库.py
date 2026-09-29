# -*- coding: utf-8 -*-
"""
生成 Chinese++ 输入法词库（每行一条中文译名）。

单一事实来源
------------
`packaging/中文对照表.md` —— 它本身由 `tools/make_cheatsheet.py` 从
**编译器真正在用的那两张表**自动生成，不是手写的。

本脚本只做「抽取 → 去重 → 校验 → 落盘」，**不手工维护任何词条**。
手写的副本一定会和编译器漂移（这是本仓库既定规矩）。

自检
----
章节标题里就写着应有条数（如「## 一、关键字（88 个）」）。抽取结果与它
不符就直接报错退出 —— 表长大了、或抽取写坏了，都会当场炸出来，不用人去数。

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
OUT = os.path.join(HERE, '汉语编程Chinese++输入法词库.txt')
MAX_CHARS = 64          # 用户要求：每条长度小于 64 个汉字

# 中文对照表.md 的几个副本，按可信度排列
CANDS = [
    os.path.abspath(os.path.join(HERE, '..', '..', 'packaging', '中文对照表.md')),
    r'E:\Chinese++-0.1-win64\中文对照表.md',
    r'E:\ChinesePlusPlus\中文对照表.md',
]

CELL = re.compile(r'`([^`]+)`')
DECLARED = re.compile(r'（(\d+)\s*[个条]）')

SECTION_OF = [
    ('关键字', 'kw'),
    ('运算符', 'ops'),
    ('预处理指令', 'dir'),
    ('入口点', 'entry'),
]


def find_source():
    for p in CANDS:
        if os.path.exists(p):
            return p
    sys.exit('找不到 中文对照表.md，试过：\n  ' + '\n  '.join(CANDS))


def extract(path):
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
            if section == 'kw' and len(cells) >= 3:
                names = [cells[0], cells[2]]
            else:
                names = [cells[0]]

            for name in names:
                # 预处理指令写作 `#包含`；词库里存 `包含` —— `#` 是打字时另外敲的，
                # 拼音打不出 `#`，带 `#` 的词条在输入法里永远选不到。
                if section == 'dir':
                    name = name.lstrip('#')
                if name:
                    groups[section].append(name)

    return groups, declared


def main():
    src = find_source()
    groups, declared = extract(src)

    labels = [('kw', '关键字'), ('ops', '运算符拼写'), ('dir', '预处理指令'), ('entry', '入口点')]
    print('来源: %s' % src)

    mismatch = []
    for key, label in labels:
        n = len(groups[key])
        want = declared.get(key)
        flag = ''
        if want is not None and want != n:
            flag = '   <<< 表头声明 %d，不符！' % want
            mismatch.append((label, want, n))
        print('  %-10s %3d%s' % (label, n, flag))

    if mismatch:
        sys.exit('抽取条数与表头声明不符，拒绝写出：%s' % mismatch)

    # 按类别顺序拼接，全表去重（关键字与指令有重合：否则 / 如果 / 导入 / 模块）
    ordered, seen, dup = [], set(), []
    for key, _ in labels:
        for w in groups[key]:
            if w in seen:
                dup.append(w)
                continue
            seen.add(w)
            ordered.append(w)

    print('  去重后     %3d   (合并重复 %d: %s)' % (len(ordered), len(dup), '、'.join(dup)))

    # 校验
    bad_len = [w for w in ordered if len(w) >= MAX_CHARS]
    bad_chr = [w for w in ordered if any(c in w for c in '|\r\n\t')]
    if bad_len:
        sys.exit('超长词条（>=%d 字）: %s' % (MAX_CHARS, bad_len))
    if bad_chr:
        sys.exit('含非法字符: %s' % bad_chr)

    longest = max(ordered, key=len)
    print('  最长词条   %d 字 —— %s' % (len(longest), longest))

    with open(OUT, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write('\n'.join(ordered) + '\n')

    print('')
    print('已写出: %s' % OUT)
    print('  编码 UTF-8 with BOM   换行 CRLF   %d 行' % len(ordered))


if __name__ == '__main__':
    main()
