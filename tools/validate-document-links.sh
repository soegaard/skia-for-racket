#!/usr/bin/env bash
# Compile and run through ONE chosen interpreter, including dynamic suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-document-links.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-links-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output; do
  cc -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
"$RACKET" -l raco -- make \
  main.rkt annotations.rkt color-space.rkt matrix.rkt output.rkt bitmap.rkt \
  tools/doctor.rkt run-tests.rkt tests/*.rkt examples/document-links.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/document-links.rkt output/document-links-0.27
python3 tools/inspect-document-links.py --probe-prefix output/document-links-0.27
python3 tools/update-source-sums.py
