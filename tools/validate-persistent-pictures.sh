#!/usr/bin/env bash
# One selected Racket for all compilation, dynamically loaded tests, and probes.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-persistent-pictures.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-pictures-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output runtime geometry projective; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
"$RACKET" -l raco -- make \
  main.rkt pictures.rkt output.rkt bitmap.rkt \
  tools/doctor.rkt run-tests.rkt tests/*.rkt examples/persistent-pictures.rkt tools/replay-picture-probe.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/persistent-pictures.rkt output/persistent-pictures-0.33
"$RACKET" tools/replay-picture-probe.rkt output/persistent-pictures-0.33.cache.skp \
  output/persistent-pictures-0.33.fresh 240 140
python3 tools/inspect-persistent-pictures.py --probe-prefix output/persistent-pictures-0.33
python3 tools/update-source-sums.py
