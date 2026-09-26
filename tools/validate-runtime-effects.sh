#!/usr/bin/env bash
# One interpreter compiles and runs all test modules, including dynamic suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-runtime-effects.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-runtime-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output runtime; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
"$RACKET" -l raco -- make \
  main.rkt matrix.rkt color-space.rkt output.rkt annotations.rkt runtime-effects.rkt \
  bitmap.rkt tools/doctor.rkt run-tests.rkt tests/*.rkt examples/runtime-effects.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/runtime-effects.rkt output/runtime-effects-0.28
python3 tools/inspect-runtime-effects.py --probe-prefix output/runtime-effects-0.28
python3 tools/update-source-sums.py
