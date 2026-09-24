#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE_RKT="$ROOT/private/native.rkt"

usage() {
  cat <<'EOF'
Usage: tools/audit-symbols.sh [LIBRARY]

Compare every (define-native ...) declaration in private/native.rkt with
symbols exported by libSkiaSharp. If LIBRARY is omitted, use
RACKET_SKIA_LIBRARY when set, otherwise the project's native/<platform>/ copy.

Exit status is 0 when all required symbols are present, 1 when one or more are
missing, and 2 for usage/platform/tool errors.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi

if [ "$#" -eq 1 ]; then
  LIB="$1"
elif [ -n "${RACKET_SKIA_LIBRARY:-}" ]; then
  LIB="$RACKET_SKIA_LIBRARY"
else
  OS="$(uname -s)"
  ARCH="$(uname -m)"
  case "$OS/$ARCH" in
    Darwin/*) LIB="$ROOT/native/osx/libSkiaSharp.dylib" ;;
    Linux/x86_64) LIB="$ROOT/native/linux-x64/libSkiaSharp.so" ;;
    Linux/aarch64|Linux/arm64) LIB="$ROOT/native/linux-arm64/libSkiaSharp.so" ;;
    *) echo "Unsupported platform $OS/$ARCH; pass the library filename explicitly." >&2; exit 2 ;;
  esac
fi

if [ ! -f "$LIB" ]; then
  echo "Native library not found: $LIB" >&2
  exit 2
fi
if [ ! -f "$NATIVE_RKT" ]; then
  echo "Binding file not found: $NATIVE_RKT" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/racket-skia-symbols.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
REQ="$TMP/required.txt"
EXP="$TMP/exported.txt"
MISS="$TMP/missing.txt"

# Binding names are intentionally simple identifiers, one per define-native.
sed -nE 's/^[[:space:]]*\(define-native[[:space:]]+([^[:space:])]+).*/\1/p' \
  "$NATIVE_RKT" | LC_ALL=C sort -u > "$REQ"

case "$(uname -s)" in
  Darwin)
    if command -v xcrun >/dev/null 2>&1; then
      xcrun nm -gjU "$LIB"
    elif command -v nm >/dev/null 2>&1; then
      nm -gjU "$LIB"
    else
      echo "Neither xcrun nm nor nm is available." >&2
      exit 2
    fi | sed 's/^_//' | LC_ALL=C sort -u > "$EXP"
    ;;
  Linux)
    if ! command -v nm >/dev/null 2>&1; then
      echo "nm is required (usually from binutils)." >&2
      exit 2
    fi
    nm -D --defined-only "$LIB" | awk '{print $NF}' | LC_ALL=C sort -u > "$EXP"
    ;;
  *)
    echo "Automatic symbol extraction is supported on macOS and Linux; pass the output through nm manually on this platform." >&2
    exit 2
    ;;
esac

comm -23 "$REQ" "$EXP" > "$MISS"

REQ_N="$(wc -l < "$REQ" | tr -d ' ')"
EXP_N="$(wc -l < "$EXP" | tr -d ' ')"
MISS_N="$(wc -l < "$MISS" | tr -d ' ')"

echo "Library: $LIB"
echo "Required define-native symbols: $REQ_N"
echo "Exported symbols: $EXP_N"

if [ "$MISS_N" -eq 0 ]; then
  echo "Missing required symbols: 0"
  echo "Native symbol audit passed."
  exit 0
fi

echo "Missing required symbols: $MISS_N"
echo
echo "=== Required by Racket but absent from the library ==="
cat "$MISS"
exit 1
