#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
RACKET="${RACKET:-racket}"
if [[ "$RACKET" == */racket ]]; then RACO="${RACKET%/racket}/raco"; else RACO="raco"; fi
printf 'Validation interpreter: %s; ' "$RACKET"
"$RACKET" -e '(printf "version ~a; VM ~a; platform ~a/~a\n" (version) (system-type (quote vm)) (system-type (quote os)) (system-type (quote arch)))'
python3 tools/static-check.py
python3 tools/inspect-output-groups.py --self-test
bash tools/audit-symbols.sh
bash tools/audit-harfbuzz-symbols.sh
# skia-lib/run-tests.rkt dynamically requires the native suites. Compile every test
# with the selected Racket so stale .zo files from another Racket version
# cannot be loaded later by dynamic-require.
"$RACO" make skia-lib/main.rkt skia-lib/output-groups.rkt skia-lib/run-tests.rkt tests/*.rkt skia-lib/tools/doctor.rkt skia-lib/examples/output-groups.rkt
"$RACKET" skia-lib/tools/doctor.rkt
"$RACKET" skia-lib/run-tests.rkt
mkdir -p output
"$RACKET" skia-lib/examples/output-groups.rkt output/output-groups-0.34
python3 tools/inspect-output-groups.py --probe-prefix output/output-groups-0.34 \
  | tee output/output-groups-0.34.inspection.json
