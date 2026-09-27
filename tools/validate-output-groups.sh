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
# run-tests.rkt dynamically requires the native suites. Compile every test
# with the selected Racket so stale .zo files from another Racket version
# cannot be loaded later by dynamic-require.
"$RACO" make main.rkt output-groups.rkt run-tests.rkt tests/*.rkt tools/doctor.rkt examples/output-groups.rkt
"$RACKET" tools/doctor.rkt
"$RACKET" run-tests.rkt
mkdir -p output
"$RACKET" examples/output-groups.rkt output/output-groups-0.34
python3 tools/inspect-output-groups.py --probe-prefix output/output-groups-0.34 \
  | tee output/output-groups-0.34.inspection.json
python3 tools/update-source-sums.py
