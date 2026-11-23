#!/usr/bin/env bash
# One selected interpreter compiles every suite, including dynamic requires.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-canvas-primitives.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-canvas-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output runtime; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
"$RACKET" -l raco -- make \
  skia-lib/main.rkt skia-lib/canvas-primitives.rkt skia-lib/output-policy.rkt skia-lib/output-audit.rkt skia-lib/matrix.rkt skia-lib/output.rkt skia-lib/bitmap.rkt \
  skia-lib/tools/doctor.rkt skia-lib/run-tests.rkt tests/*.rkt skia-lib/examples/canvas-primitives.rkt
"$RACKET" skia-lib/tools/doctor.rkt
"$RACKET" skia-lib/run-tests.rkt
mkdir -p output
"$RACKET" skia-lib/examples/canvas-primitives.rkt output/canvas-primitives-0.30
python3 tools/inspect-canvas-primitives.py --probe-prefix output/canvas-primitives-0.30
