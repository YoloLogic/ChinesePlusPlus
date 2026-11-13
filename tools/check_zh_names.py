# -*- coding: utf-8 -*-
"""check_zh_names.py —— 中文命名检查器

定新名字前先跑它，避免三类返工（都真实发生过）：
  1. 撞关键字：类型(=class)、选择(=switch) 不能当标识符
  2. 撞既有头：是空型、独占锁 已在别名层定义，重复定义会编译失败
  3. 只确认「可用」还不够 —— 还要在对应头里注册，避免两个头各起一个名字

用法：
  python tools/check_zh_names.py 值 类别 为整数 选择 类型
  python tools/check_zh_names.py --registry      # 列出已占用的中文名
"""
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")
根 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF = os.path.join(根, "LLVM-main", "clang", "include", "clang", "Basic", "ChineseKeywords.def")
ZH = os.path.join(根, "zhstdlib")

中文 = re.compile(r"[\u4e00-\u9fff][\u4e00-\u9fffA-Za-z0-9_]*")
声明行 = re.compile(r"^\s*(?:模板\s*<[^>]*>\s*)?(?:使用|类型|结构|枚举|内联|静态|常量表达式|模板)")

def load_keywords():
    kw = {}
    for line in open(DEF, encoding="utf-8", errors="replace"):
        m = re.match(r"ZH_[A-Z_]+\(\s*(?:([^,]+),\s*)?([^,)]+),", line.strip())
        if m:
            for g in m.groups():
                if g:
                    kw[g.strip()] = True
    return kw

def load_registry():
    """扫 zhstdlib 各头里的声明行，收集已占用的中文名 → 首次出现的头"""
    reg = {}
    for dirpath, _, files in os.walk(ZH):
        for f in files:
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, ZH)
            for line in open(p, encoding="utf-8", errors="replace"):
                s = line.split("//")[0]
                if not 声明行.match(s):
                    continue
                for name in 中文.findall(s):
                    reg.setdefault(name, rel)
    return reg

def main():
    kw = load_keywords()
    reg = load_registry()
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if args[0] == "--registry":
        print("已占用的中文名 %d 个：" % len(reg))
        for k in sorted(reg):
            print("  %-14s %s" % (k, reg[k]))
        return 0
    坏 = 0
    for name in args:
        if name in kw:
            print("✗ %-14s 是中文关键字，不能当标识符" % name)
            坏 += 1
        elif name in reg:
            print("✗ %-14s 已在 %s 定义，重复定义会编译失败" % (name, reg[name]))
            坏 += 1
        else:
            print("✓ %-14s 可用" % name)
    return 1 if 坏 else 0

if __name__ == "__main__":
    sys.exit(main())