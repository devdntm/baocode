#!/usr/bin/env python3
"""Resolve every conflict block of a file to one side.

    take-side.py <file> ours|theirs

"ours" keeps the fork's lines (HEAD), "theirs" upstream's. Blocks with a
merge base section (diff3 style) keep the chosen side only. Then re-apply
by hand what of the other side must stay, and `git add` the file.
"""
import re
import sys

if len(sys.argv) != 3 or sys.argv[2] not in ("ours", "theirs"):
    sys.exit(__doc__)
path, side = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
block = re.compile(
    r"<<<<<<< [^\n]*\n(.*?)(?:\|\|\|\|\|\|\| [^\n]*\n.*?)?=======\n(.*?)>>>>>>> [^\n]*\n",
    re.S,
)
text, count = block.subn(lambda m: m.group(1) if side == "ours" else m.group(2), text)
open(path, "w", encoding="utf-8").write(text)
print(f"{path}: {count} block(s) -> {side}")
