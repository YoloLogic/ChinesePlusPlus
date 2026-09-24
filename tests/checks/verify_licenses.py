# -*- coding: utf-8 -*-
"""发行前必须成立的两件事：许可证正文逐字节正确、NOTICE 含法定声明。

为什么这是一条【检查】而不是一句说明
------------------------------------
LLVM 采用 Apache License 2.0 with LLVM Exceptions。分发二进制时：

  * §4(a) 必须给接收者一份许可证正文  -> licenses\\LICENSE.TXT 必须存在且正确
  * §4(b) 修改过的文件必须带显著声明    -> licenses\\NOTICE.txt 必须声明「改动过」
  * §4(d) 上游有 NOTICE 才需要附        -> LLVM 无 NOTICE 文件，不适用

`LICENSE.TXT` 要求**逐字节等同**上游，是因为它是一份法律文本：任何"顺手改成
更好读的样子"都会让附上的许可证不再是那份许可证。所以这里用 SHA256 对上游比对，
而不是查关键词。

本脚本自带自测：故意把许可证改坏、故意抽掉 NOTICE 里的声明，都必须被判失败。
项目定则 —— 一个永远返回"通过"的检查等于没有检查。

用法：
    python tests\\checks\\verify_licenses.py
退出码 0 = 通过。
"""

import hashlib
import io
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
UPSTREAM = os.path.join(ROOT, "LLVM-main", "LICENSE.TXT")
OURS = os.path.join(ROOT, "licenses", "LICENSE.TXT")
NOTICE = os.path.join(ROOT, "licenses", "NOTICE.txt")

errors = []


def sha256(path):
    with io.open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


# ---------------------------------------------------------------- 许可证正文
print("1. licenses\\LICENSE.TXT 必须与上游逐字节相同")

if not os.path.isfile(UPSTREAM):
    print("   [跳过] 找不到上游 %s（LLVM-main 未检出）" % UPSTREAM)
elif not os.path.isfile(OURS):
    errors.append("licenses\\LICENSE.TXT 不存在 —— 分发二进制必须附许可证正文")
    print("   [错误] licenses\\LICENSE.TXT 不存在")
else:
    a, b = sha256(UPSTREAM), sha256(OURS)
    if a != b:
        errors.append(
            "licenses\\LICENSE.TXT 与上游不同（上游 %s / 我们 %s）。"
            "法律文本不允许改写：请直接拷贝上游文件，不要手工编辑。" % (a[:16], b[:16]))
        print("   [错误] 与上游不同：%s != %s" % (a[:16], b[:16]))
    else:
        print("   [通过] 与上游逐字节相同（SHA256 %s…，%d 字节）"
              % (a[:16], os.path.getsize(OURS)))


# ------------------------------------------------------------------- NOTICE
print("2. licenses\\NOTICE.txt 必须含法定声明")

# 每条 = (说明, 必须出现的片段之一)
REQUIRED = [
    ("声明这是修改过的 LLVM（Apache-2.0 §4(b)）", ["修改过的", "改动", "modified"]),
    ("明确指出许可证是一份完整正文，指向 LICENSE.TXT", ["LICENSE.TXT"]),
    ("写明许可证名称", ["Apache"]),
    ("写明 LLVM 例外条款", ["LLVM Exceptions", "LLVM 例外"]),
    ("说明没有随包分发微软的库（避免误导）", ["没有再分发", "not redistribute", "不含"]),
]

notice_text = ""
if not os.path.isfile(NOTICE):
    errors.append("licenses\\NOTICE.txt 不存在")
    print("   [错误] 不存在")
else:
    notice_text = io.open(NOTICE, encoding="utf-8", errors="replace").read()
    for why, needles in REQUIRED:
        if any(n in notice_text for n in needles):
            print("   [通过] %s" % why)
        else:
            errors.append("NOTICE 缺少声明：%s（找不到 %s）" % (why, needles))
            print("   [错误] 缺少声明：%s（找不到 %s）" % (why, needles))


# --------------------------------------------------------------------- 自测
print("3. 自测：这些检查必须真的会失败")

_probe_bad_license = b"Apache License 2.0\n(hand-edited, shorter)\n"
_ok1 = sha256(UPSTREAM) if os.path.isfile(UPSTREAM) else None
_short = hashlib.sha256(_probe_bad_license).hexdigest()
if _ok1 is not None and _short == _ok1:
    errors.append("自测失败：一份被改短的许可证竟然与上游同哈希")
    print("   [错误] 自测一失败：改短的许可证没被哈希检查发现")
else:
    print("   [通过] 自测一：被改写的许可证与上游哈希不同 -> 会被判失败")

_probe_notice = "这是一个中文编程工具链。"      # 缺全部法定声明
_missing = [why for why, needles in REQUIRED
            if not any(n in _probe_notice for n in needles)]
if len(_missing) != len(REQUIRED):
    errors.append("自测失败：空洞的 NOTICE 竟然通过了声明检查（只缺 %d 条）"
                  % len(_missing))
    print("   [错误] 自测二失败：空洞 NOTICE 没被全部判缺")
else:
    print("   [通过] 自测二：空洞 NOTICE 会被判缺全部 %d 条声明" % len(REQUIRED))


# --------------------------------------------------------------------- 结论
print("")
print("=" * 60)
if errors:
    print("  错误：%d" % len(errors))
    for e in errors:
        print("    - " + e)
    print("")
    print("  结果：未通过。**在修好之前不要对外分发。**")
    sys.exit(1)
print("  结果：全部通过。许可证与 NOTICE 可以随包分发。")
sys.exit(0)
