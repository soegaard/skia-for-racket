#!/usr/bin/env bash
# One selected interpreter compiles every suite, including dynamic requires.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-geometry-primitives.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-geometry-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output runtime geometry; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
"$RACKET" -l raco -- make \
  main.rkt geometry-primitives.rkt canvas-primitives.rkt output-policy.rkt output-audit.rkt matrix.rkt output.rkt bitmap.rkt \
  tools/doctor.rkt run-tests.rkt tests/*.rkt examples/geometry-primitives.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/geometry-primitives.rkt output/geometry-primitives-0.31
python3 tools/inspect-geometry-primitives.py --probe-prefix output/geometry-primitives-0.31
python3 tools/update-source-sums.py
