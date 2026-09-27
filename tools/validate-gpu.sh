#!/usr/bin/env bash
# The Python runner propagates one selected Racket to every compile/test/probe.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PYTHONDONTWRITEBYTECODE=1
exec "${PYTHON:-python3}" tools/validate-gpu.py
