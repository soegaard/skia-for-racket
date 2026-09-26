#!/usr/bin/env bash
# One interpreter for compilation and all native/dynamically loaded suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-color-output.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-color-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
# A runner's dynamic-require targets are not raco make dependencies.
# Compile every test file explicitly, with the same selected Racket.
"$RACKET" -l raco -- make \
  main.rkt color-space.rkt matrix.rkt output.rkt bitmap.rkt \
  tools/doctor.rkt run-tests.rkt tests/*.rkt examples/color-output.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/color-output.rkt output/color-output-0.26
python3 tools/inspect-color-output.py --probe-prefix output/color-output-0.26
python3 tools/update-source-sums.py
