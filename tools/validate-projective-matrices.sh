#!/usr/bin/env bash
# One selected Racket for all compilation, dynamically loaded tests, and probes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-projective-matrices.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-projective-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output runtime geometry projective; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
"$RACKET" -l raco -- make \
  skia-lib/main.rkt skia-lib/projective-matrix.rkt skia-lib/canvas-matrix.rkt skia-lib/matrix.rkt skia-lib/output.rkt skia-lib/bitmap.rkt \
  skia-lib/tools/doctor.rkt skia-lib/run-tests.rkt tests/*.rkt skia-lib/examples/projective-matrices.rkt
"$RACKET" skia-lib/tools/doctor.rkt
"$RACKET" skia-lib/run-tests.rkt
mkdir -p output
"$RACKET" skia-lib/examples/projective-matrices.rkt output/projective-matrices-0.32
python3 tools/inspect-projective-matrices.py --probe-prefix output/projective-matrices-0.32
