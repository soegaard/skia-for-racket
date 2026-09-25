#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "SOURCE-SHA256SUMS.txt"

paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT
).split(b"\0")

rows = []
for raw in paths:
    if not raw:
        continue
    rel = raw.decode("utf-8")
    if rel == OUT.name:
        continue
    path = ROOT / rel
    if not path.is_file():
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    rows.append(f"{digest}  {rel}\n")

OUT.write_text("".join(rows), encoding="utf-8")
print(f"Wrote {OUT.relative_to(ROOT)} ({len(rows)} files)")
