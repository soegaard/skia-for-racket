#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_RKT="$ROOT/private/harfbuzz-native.rkt"
case "${1:-}" in -h|--help)
  echo 'Usage: tools/audit-harfbuzz-symbols.sh [LIBRARY]'; exit 0;; esac
[ "$#" -le 1 ] || exit 2
if [ "$#" -eq 1 ]; then
  LIB="$1"
elif [ -n "${RACKET_HARFBUZZ_LIBRARY:-}" ]; then
  LIB="$RACKET_HARFBUZZ_LIBRARY"
else
  case "$(uname -s)/$(uname -m)" in
    Darwin/*) LIB="$ROOT/native/osx/libHarfBuzzSharp.dylib" ;;
    Linux/x86_64) LIB="$ROOT/native/linux-x64/libHarfBuzzSharp.so" ;;
    Linux/aarch64|Linux/arm64) LIB="$ROOT/native/linux-arm64/libHarfBuzzSharp.so" ;;
    *) echo 'Unsupported platform; pass the library explicitly.' >&2; exit 2 ;;
  esac
fi
[ -f "$LIB" ] || { echo "Native HarfBuzz library not found: $LIB" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/racket-harfbuzz-symbols.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
REQ="$TMP/required.txt"; EXP="$TMP/exported.txt"; MISS="$TMP/missing.txt"
sed -nE 's/^[[:space:]]*\(define-hb-native[[:space:]]+([^[:space:])]+).*/\1/p' \
  "$NATIVE_RKT" | LC_ALL=C sort -u > "$REQ"
case "$(uname -s)" in
  Darwin)
    if command -v xcrun >/dev/null 2>&1; then xcrun nm -gjU "$LIB"; else nm -gjU "$LIB"; fi |
      sed 's/^_//' | LC_ALL=C sort -u > "$EXP" ;;
  Linux)
    nm -D --defined-only "$LIB" | awk '{print $NF}' | LC_ALL=C sort -u > "$EXP" ;;
  *) exit 2 ;;
esac
comm -23 "$REQ" "$EXP" > "$MISS"
echo "Library: $LIB"
echo "Required define-hb-native symbols: $(wc -l < "$REQ" | tr -d ' ')"
echo "Exported symbols: $(wc -l < "$EXP" | tr -d ' ')"
if [ ! -s "$MISS" ]; then
  echo 'Missing required symbols: 0'
  echo 'HarfBuzz symbol audit passed.'
else
  echo "Missing required symbols: $(wc -l < "$MISS" | tr -d ' ')"
  cat "$MISS"
  exit 1
fi
