#!/usr/bin/env bash
# The same chosen interpreter compiles AND runs all dynamically loaded suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-filter-graphs.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-filters-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
# Do not rely on raco make skia-lib/run-tests.rkt to discover dynamic-require targets.
# -l raco dispatches the compiler within exactly this Racket installation.
"$RACKET" -l raco -- make \
  skia-lib/main.rkt skia-lib/matrix.rkt skia-lib/output.rkt skia-lib/bitmap.rkt skia-lib/tools/doctor.rkt skia-lib/run-tests.rkt \
  tests/*.rkt skia-lib/examples/filter-graphs.rkt
"$RACKET" skia-lib/tools/doctor.rkt
"$RACKET" skia-lib/run-tests.rkt
mkdir -p output
"$RACKET" skia-lib/examples/filter-graphs.rkt output/filter-graphs-0.25
python3 tools/inspect-filter-graphs.py --probe-prefix output/filter-graphs-0.25
