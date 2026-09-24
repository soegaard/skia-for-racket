#!/usr/bin/env bash
# Downloads the pinned HarfBuzzSharp native library; does not execute it.
# Compatible with macOS's system Bash 3.2. No sudo, dotnet, or compiler needed.
set -euo pipefail
VERSION=8.3.1.2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE=""
usage() {
  printf '%s\n' 'Usage: bash tools/install-harfbuzz.sh [--archive /path/to/package.nupkg]' \
    'Downloads HarfBuzzSharp 8.3.1.2 native assets for this platform.' \
    'An optional local archive is useful for offline installation.'
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      ARCHIVE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$(uname -s)" in
  Darwin)
    RID=osx; FILE=libHarfBuzzSharp.dylib
    PACKAGE=harfbuzzsharp.nativeassets.macos ;;
  Linux)
    FILE=libHarfBuzzSharp.so
    PACKAGE=harfbuzzsharp.nativeassets.linux
    case "$(uname -m)" in
      x86_64) RID=linux-x64 ;;
      aarch64|arm64) RID=linux-arm64 ;;
      *) echo 'Only Linux x86-64 and ARM64 are supported by this installer.' >&2; exit 2 ;;
    esac ;;
  *) echo 'This installer supports macOS and glibc Linux only.' >&2; exit 2 ;;
esac
command -v unzip >/dev/null || { echo 'unzip is required.' >&2; exit 2; }
if [ -n "$ARCHIVE" ]; then
  [ -f "$ARCHIVE" ] || { echo "Archive does not exist: $ARCHIVE" >&2; exit 2; }
else
  command -v curl >/dev/null || { echo 'curl is required.' >&2; exit 2; }
fi
mkdir -p "$ROOT/native"
WORK="$(mktemp -d "$ROOT/native/.install-hb.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
URL="https://api.nuget.org/v3-flatcontainer/$PACKAGE/$VERSION/$PACKAGE.$VERSION.nupkg"
if [ -n "$ARCHIVE" ]; then
  cp "$ARCHIVE" "$WORK/package.nupkg"
else
  printf 'Downloading %s\n' "$URL"
  curl --fail --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 30 --max-time 600 \
    --output "$WORK/package.nupkg" "$URL"
fi
unzip -tqq "$WORK/package.nupkg"
unzip -p "$WORK/package.nupkg" '*.nuspec' > "$WORK/package.nuspec"
EXPECTED_ID="$(printf '%s' "$PACKAGE" | sed 's/\./[.]/g')"
grep -Eiq "<id>[[:space:]]*$EXPECTED_ID[[:space:]]*</id>" "$WORK/package.nuspec" || {
  echo "Wrong native package; expected $PACKAGE" >&2; exit 1;
}
grep -Eq '<version>[[:space:]]*8[.]3[.]1[.]2[[:space:]]*</version>' "$WORK/package.nuspec" || {
  echo "Wrong native package version; expected $VERSION" >&2; exit 1;
}
MEMBER="runtimes/$RID/native/$FILE"
unzip -p "$WORK/package.nupkg" "$MEMBER" > "$WORK/$FILE"
[ -s "$WORK/$FILE" ] || { echo "Missing or empty archive member: $MEMBER" >&2; exit 1; }
chmod 755 "$WORK/$FILE"
if command -v shasum >/dev/null; then
  (cd "$WORK" && shasum -a 256 package.nupkg "$FILE") > "$WORK/HARFBUZZ-SHA256SUMS.txt"
elif command -v sha256sum >/dev/null; then
  (cd "$WORK" && sha256sum package.nupkg "$FILE") > "$WORK/HARFBUZZ-SHA256SUMS.txt"
else
  printf '%s\n' 'No SHA-256 utility was available.' > "$WORK/HARFBUZZ-SHA256SUMS.txt"
fi
{
  printf 'Package: %s\nVersion: %s\nPlatform: %s\nMember: %s\n' "$PACKAGE" "$VERSION" "$RID" "$MEMBER"
  printf 'Source: %s\n' "$URL"
  [ -z "$ARCHIVE" ] || printf 'Installed from local archive: %s\n' "$ARCHIVE"
} > "$WORK/HARFBUZZ-SOURCE.txt"
DEST="$ROOT/native/$RID"
mkdir -p "$DEST"
for item in package.nupkg package.nuspec HARFBUZZ-SHA256SUMS.txt HARFBUZZ-SOURCE.txt; do
  mv -f "$WORK/$item" "$DEST/harfbuzz-$item"
done
mv -f "$WORK/$FILE" "$DEST/$FILE"
printf '\nInstalled %s\n' "$DEST/$FILE"
printf '%s\n' 'Next: racket tools/doctor.rkt' '      racket run-tests.rkt'
