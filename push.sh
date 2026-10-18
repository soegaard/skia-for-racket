#!/usr/bin/env sh
# Run the source CI preflight, then push the current branch.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"

die() {
  printf '%s\n' "push.sh: $*" >&2
  exit 1
}

run_source_preflight() {
  command -v uv >/dev/null 2>&1 || die 'uv is required for the source CI preflight'
  uv run --with-requirements tools/dc-output-requirements.txt python -c '
import os
import subprocess
import sys

sys.path.insert(0, "tools")
import ci

environment = ci.clean_environment(os.environ)
commands = [
    [sys.executable, ci.ROOT / "tools/static-check.py"],
    [sys.executable, ci.ROOT / "tools/check-gpu-source.py", "--require-integration"],
]
commands.extend(
    [sys.executable, ci.ROOT / "tools" / name,
     *(["--self-test"] if name.startswith("inspect-") else [])]
    for name in ci.PYTHON_CHECKS
)
for command in commands:
    print("+", " ".join(map(str, command)))
    subprocess.run(command, cwd=ci.ROOT, env=environment, check=True)
print(f"Verified {len(commands)} source CI commands")
'
}

if test -n "$(git status --porcelain)"; then
  die 'commit or stash changes before pushing'
fi

run_source_preflight

git push
