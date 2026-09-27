#!/usr/bin/env bash
# Compile, test, generate every review page, then inspect before updating sums.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RACKET="${RACKET:-racket}"
PYTHON="${PYTHON:-python3}"
"$RACKET" -e '(printf "Validation interpreter: ~a; version ~a; VM ~a; platform ~a/~a\n" (find-system-path (quote exec-file)) (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
"$PYTHON" tools/static-check.py
"$PYTHON" tools/inspect-raster-buffers.py --self-test
WORK="$(mktemp -d "${TMPDIR:-/tmp}/skia-raster-buffers-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for NAME in codec pdf path-matrix filter color-output runtime geometry projective color-filter; do
  "${CC:-cc}" -std=c11 -Wall -Wextra -pedantic "tools/check-$NAME-abi.c" -o "$WORK/$NAME"
  "$WORK/$NAME"
done
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
# Never select a different raco from PATH. Include all dynamically loaded tests.
"$RACKET" -l raco -- make main.rkt raster-buffers.rkt color-filters.rkt output.rkt bitmap.rkt \
  tools/doctor.rkt tools/portable-drawing-doctor.rkt tools/color-filter-doctor.rkt tools/raster-buffer-doctor.rkt run-tests.rkt tests/*.rkt \
  examples/raster-buffers.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" tools/portable-drawing-doctor.rkt
"$RACKET" tools/color-filter-doctor.rkt
"$RACKET" tools/raster-buffer-doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
PREFIX="output/raster-buffers-0.37"
"$RACKET" examples/raster-buffers.rkt "$PREFIX"
PDF_ARGS=()
case "${CHECK_PDF:-auto}" in
  1) PDF_ARGS=(--pdf) ;;
  0) ;;
  auto)
    if "$PYTHON" -c 'import pypdf' >/dev/null 2>&1; then
      PDF_ARGS=(--pdf)
    else
      printf '%s\n' 'PDF structure NOT CHECKED: pypdf is unavailable; SVG, native samples and audits will still be checked.' >&2
    fi ;;
  *) printf '%s\n' 'CHECK_PDF must be auto, 0, or 1.' >&2; exit 2 ;;
esac
# Publish a complete inspection report only after the inspector succeeds.
"$PYTHON" tools/inspect-raster-buffers.py --probe-prefix "$PREFIX" "${PDF_ARGS[@]}" > "$WORK/inspection.json"
cp "$WORK/inspection.json" "$PREFIX.inspection.json"
cat "$PREFIX.inspection.json"
"$PYTHON" tools/update-source-sums.py
