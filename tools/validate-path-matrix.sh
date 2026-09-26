#!/usr/bin/env bash
# The same chosen interpreter compiles AND runs all dynamically loaded suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-path-matrix.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-matrix-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
# Do not rely on raco make run-tests.rkt to discover dynamic-require targets.
# -l raco dispatches the compiler within exactly this Racket installation.
"$RACKET" -l raco -- make \
  main.rkt matrix.rkt output.rkt bitmap.rkt tools/doctor.rkt run-tests.rkt \
  tests/*.rkt examples/path-matrix.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/path-matrix.rkt output/path-matrix-0.24
python3 tools/inspect-path-matrix.py --probe-prefix output/path-matrix-0.24
python3 tools/update-source-sums.py
