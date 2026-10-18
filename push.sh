#!/usr/bin/env sh
# Refresh the source-checksum manifest, commit that ledger update, and push.
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

# This helper is intended to run after the source changes themselves have
# been committed.  Its own first-run files are the only allowed exceptions.
if ! git diff --quiet -- . ':(exclude)SOURCE-SHA256SUMS.txt' ':(exclude)push.sh' ||
   ! git diff --cached --quiet -- . ':(exclude)SOURCE-SHA256SUMS.txt' ':(exclude)push.sh'; then
  die 'commit or stash unrelated changes before updating the source manifest'
fi

if test -n "$(git ls-files --others --exclude-standard -- ':!push.sh')"; then
  die 'remove, commit, or ignore unrelated untracked files before updating the source manifest'
fi

python3 -B tools/update-source-sums.py
python3 -B tools/update-source-sums.py --check
run_source_preflight

git add -- SOURCE-SHA256SUMS.txt push.sh
if ! git diff --cached --quiet; then
  git commit -m 'Refresh source checksum manifest'
fi

git push
