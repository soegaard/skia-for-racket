#!/usr/bin/env sh
# Refresh the source-checksum manifest, commit that ledger update, and push.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"

die() {
  printf '%s\n' "push.sh: $*" >&2
  exit 1
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

git add -- SOURCE-SHA256SUMS.txt push.sh
if ! git diff --cached --quiet; then
  git commit -m 'Refresh source checksum manifest'
fi

git push
