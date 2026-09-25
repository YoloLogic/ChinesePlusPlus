"""Mutation-test the markdown table guard in tools/make_cheatsheet.py.

WHY THIS EXISTS
    tools/make_cheatsheet.py generates packaging/中文对照表.md. It must refuse to
    write a file whose tables GFM would not parse, because the failure is
    completely silent: markdown renderers fall back to showing a wall of pipes,
    and neither Python, nor the compiler, nor the editor reports anything.
    That is exactly what shipped -- section one of 中文对照表.md showed as raw
    text because its delimiter row had 5 cells for a 4-column header.

    A guard that has never been shown to fail is not a guard. So this script
    deliberately reintroduces each known breakage and requires the generator to
    exit non-zero AND leave the previous output untouched.

MUTATIONS
    1. delimiter row goes back to "|---|---|" * (cols // 2)
       -> 5 cells for a 4-column header (the reported bug)
    2. esc() stops escaping pipes
       -> the operator rows whose symbol IS '|', '||' or '|=' split their own cells

    The first draft of the guard MISSED mutation 1: it treated a delimiter row
    containing an empty cell as "not a delimiter row" and skipped that table
    entirely. This test is what caught that, so keep it.

RUN
    python tools/verify_cheatsheet_tables.py
"""
import io
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "make_cheatsheet.py")
OUT = os.path.join(ROOT, "packaging", "中文对照表.md")
BAK = SRC + ".mutbak"

MUTATIONS = [
    ("1 bad delimiter width",
     'w("|" + "---|" * cols)',
     'w("|---|---|" * (cols // 2))'),
    ("2 pipes not escaped",
     'return str(s).replace("|", "\\\\|")',
     'return str(s)'),
]


def read(path):
    try:
        return io.open(path, encoding="utf-8").read()
    except OSError:
        return None


def main():
    orig = read(SRC)
    if orig is None:
        print("cannot read %s" % SRC)
        return 1
    good = read(OUT)

    env = dict(os.environ)
    # The generator prints Chinese. Without this the child writes GBK bytes and
    # the detail lines come back as mojibake, which makes a failure unreadable.
    env["PYTHONIOENCODING"] = "utf-8"

    shutil.copy(SRC, BAK)
    results = []
    try:
        for name, old, new in MUTATIONS:
            if old not in orig:
                results.append((name, None, "PATTERN NOT FOUND -- this test is stale"))
                continue
            # Start each round from the known-good output: a MISS in an earlier
            # round would otherwise change the baseline for the next one.
            if good is not None:
                io.open(OUT, "w", encoding="utf-8").write(good)
            io.open(SRC, "w", encoding="utf-8").write(orig.replace(old, new, 1))
            r = subprocess.run([sys.executable, SRC], capture_output=True,
                               text=True, encoding="utf-8", errors="replace",
                               env=env)
            untouched = (read(OUT) == good)
            detail = ""
            for line in ((r.stdout or "") + (r.stderr or "")).strip().splitlines():
                if "不一致" in line or "refusing" in line:
                    detail = line.strip()
                    break
            results.append((name, r.returncode,
                            "exit=%s output_untouched=%s  %s"
                            % (r.returncode, untouched, detail)))
    finally:
        shutil.copy(BAK, SRC)
        os.remove(BAK)
        if good is not None:
            io.open(OUT, "w", encoding="utf-8").write(good)

    print("=== mutation test: cheatsheet table guard ===")
    ok = True
    for name, code, detail in results:
        caught = (code is not None and code != 0)
        ok = ok and caught
        print("  [%s] %s -> %s" % ("CAUGHT" if caught else "MISSED", name, detail))
    print("  generator source restored: %s" % (read(SRC) == orig))
    print("  RESULT: %s" % ("guard works" if ok else "GUARD DOES NOT WORK"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
