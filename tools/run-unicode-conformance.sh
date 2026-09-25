#!/bin/sh
set -eu

RACKET=${RACKET:-racket}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=15.1.0
BASE="https://www.unicode.org/Public/$VERSION/ucd"

usage() {
  cat <<USAGE
Usage: tools/run-unicode-conformance.sh [--data-dir DIR]

Without --data-dir, downloads the Unicode $VERSION LineBreakTest.txt and
BidiCharacterTest.txt into a temporary directory, runs the pure-Racket
conformance harness, then removes the downloads. With --data-dir, reads
DIR/LineBreakTest.txt and DIR/BidiCharacterTest.txt without network access.
USAGE
}

DATA_DIR=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; DATA_DIR=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

TMP=
if [ -z "$DATA_DIR" ]; then
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required unless --data-dir is supplied" >&2; exit 1; }
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/racket-skia-unicode.XXXXXX")
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
  DATA_DIR=$TMP
  curl -fsSL "$BASE/auxiliary/LineBreakTest.txt" -o "$DATA_DIR/LineBreakTest.txt"
  curl -fsSL "$BASE/BidiCharacterTest.txt" -o "$DATA_DIR/BidiCharacterTest.txt"
fi

[ -s "$DATA_DIR/LineBreakTest.txt" ] || { echo "missing LineBreakTest.txt" >&2; exit 1; }
[ -s "$DATA_DIR/BidiCharacterTest.txt" ] || { echo "missing BidiCharacterTest.txt" >&2; exit 1; }

exec "$RACKET" "$ROOT/tools/unicode-conformance.rkt" \
  --line-break "$DATA_DIR/LineBreakTest.txt" \
  --bidi "$DATA_DIR/BidiCharacterTest.txt"
