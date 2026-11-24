#!/bin/sh
# platform: host-agnostic
set -eu
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
here="$(cd "$(dirname "$0")" && pwd)"
RP="$here/../scripts/reproduce.sh"
CM="$here/../scripts/content-manifest.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/reproduce.XXXXXX")"; trap 'chmod -R u+rwX "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- every case here reads a pkg"
MAVERGREEN_RELEASES="file://$w/srv"; SHIPYARD_FETCH_BACKOFF=0; SHIPYARD_FETCH_TRIES=1
export MAVERGREEN_RELEASES SHIPYARD_FETCH_BACKOFF SHIPYARD_FETCH_TRIES
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

R="$w/repo"; mkdir -p "$R/.mavergreen/products/w"; printf 'W\n' > "$R/.mavergreen/products/w/noun"
T=1.0-mavergreen.1
pkg() {  # $1 = dist dir, $2 = the blob's bytes
  rm -rf "$w/root"; mkdir -p "$w/root/opt/mavergreen/w" "$1"
  printf '%s' "$2" > "$w/root/opt/mavergreen/w/blob"; chmod 0644 "$w/root/opt/mavergreen/w/blob"
  "$SD" component --root "$w/root" --identifier dev.mavergreen.w --version 1.0.1 --install-location / \
    --mtime "$SOURCE_DATE_EPOCH" --out "$1/w-$T.pkg" >/dev/null
}
P="$w/srv/Mavergreen/w/releases/download/$T"
pkg "$P" released
GITHUB_REPOSITORY=Mavergreen/w sh "$CM" "$P" "$T" "$R" > "$P/CONTENT-MANIFEST.txt"
printf 'shipyard 1.0.900\n' > "$P/RELEASE-MANIFEST.txt"
( cd "$P" && for f in *; do printf '%s  %s\n' "$(sha "$f")" "$f"; done ) > "$w/sums"; mv "$w/sums" "$P/SHA256SUMS"

run() { rc=0; sh "$RP" --dist "$w/dist" --repo Mavergreen/w --tag "$T" --repo-root "$R" > "$w/out" 2> "$w/err" || rc=$?; out="$(cat "$w/out")"; }
SHIPYARD_VERSION=1.0.900; export SHIPYARD_VERSION

rm -rf "$w/dist"; pkg "$w/dist" released
run
[ "$rc" -eq 0 ] || fail "an identical rebuild exits 0: rc $rc: $out $(cat "$w/err")"
echo "ok: an identical rebuild reproduces"

rm -rf "$w/dist"; pkg "$w/dist" releaseD
run
[ "$rc" -eq 1 ] || fail "a rebuild with one byte different exits 1: rc $rc: $out $(cat "$w/err")"
printf '%s\n' "$out" | grep -q '^-file w.pkg opt/mavergreen/w/blob ' || fail "the differing row is printed: $out"
printf '%s\n' "$out" | grep -q '^bytes	opt/mavergreen/w/blob	' || fail "build-equivalence.sh's bytes line follows: $out"
echo "ok: one byte different names the row and the bytes"

SHIPYARD_VERSION=1.0.901 run
[ "$(printf '%s\n' "$out" | head -n 1)" = "built with shipyard 1.0.900, reproduced with 1.0.901" ] \
  || fail "a different shipyard is named first: $out"
echo "ok: a different shipyard is named first"

rm -f "$P/CONTENT-MANIFEST.txt"
( cd "$P" && for f in *; do [ "$f" = SHA256SUMS ] || printf '%s  %s\n' "$(sha "$f")" "$f"; done ) > "$w/sums"; mv "$w/sums" "$P/SHA256SUMS"
run
[ "$rc" -eq 2 ] || fail "a tag with no CONTENT-MANIFEST.txt exits 2: rc $rc: $out"
rc=0; sh "$RP" --dist "$w/dist" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "a usage error exits 2: rc $rc"
echo "PASS: reproduce"
