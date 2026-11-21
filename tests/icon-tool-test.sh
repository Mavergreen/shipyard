#!/bin/sh
# platform: host-agnostic -- needs python3; exits 77 without it
# spec: scripts/icon-tool.py -- fixtures are generated pictures (tests/icon-fixtures.py), never vendor art
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
T="$here/../scripts/icon-tool.py"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: needs python3"; exit 77; }
W=$(mktemp -d "${TMPDIR:-/tmp}/icon-tool-test.XXXXXX"); trap 'rm -rf "$W"' EXIT
python3 "$here/icon-fixtures.py" "$W/f"
fail() { echo "FAIL $*"; exit 1; }
fp() { python3 "$T" fingerprint "$W/f/$1"; }
dist() { python3 "$T" distance "$(fp "$1")" "$(fp "$2")"; }
dh() { dist "$1" "$2" | sed 's/^dhash:\([0-9]*\) .*/\1/'; }
co() { dist "$1" "$2" | sed 's/.* colour:\([0-9]*\)$/\1/'; }

fp dark-64.png | grep -Eq '^sha256:[0-9a-f]{64} dhash:[0-9a-f]{16} 64x64 colour:[0-9a-f]{12}$' \
  || fail "fingerprint format: $(fp dark-64.png)"
[ "$(dist dark-64.png dark-64.png)" = "dhash:0 colour:0" ] || fail "identical icons are distance 0"
[ "$(dh dark-64.png dark-180.png)" -le 6 ] || fail "the same picture at another size is close: $(dist dark-64.png dark-180.png)"
[ "$(dh dark-64.png bars-64.png)" -ge 20 ] || fail "a different picture is far: $(dist dark-64.png bars-64.png)"
[ "$(co dark-180.png blue-180.png)" -ge 20 ] || fail "same shape, different colour: colour is far: $(dist dark-180.png blue-180.png)"
for v in pal rgba16; do
  [ "$(dist dark-64.png dark-64-$v.png)" = "dhash:0 colour:0" ] || fail "$v decodes to the same picture: $(dist dark-64.png dark-64-$v.png)"
done
[ "$(dh dark-64.png dark-64-greya.png)" -le 2 ] || fail "grey+alpha decodes: $(dist dark-64.png dark-64-greya.png)"
out=$(python3 "$T" fingerprint "$W/f/dark-64-interlaced.png" 2>&1) && fail "an interlaced PNG is refused, not mis-decoded"
printf '%s' "$out" | grep -q interlaced || fail "the refusal says interlaced: $out"
out=$(python3 "$T" fingerprint "$W/f/not-a.png" 2>&1) && fail "a non-PNG is refused"

mkdir -p "$W/root/usr/share/icons/a b" "$W/root/opt/app/resources"
cp "$W/f/bars-64.png" "$W/root/usr/share/icons/a b/bars.png"
cp "$W/f/dark-64-interlaced.png" "$W/root/usr/share/icons/il.png"
cp "$W/f/app.asar" "$W/root/opt/app/resources/app.asar"
got=$(python3 "$T" find "$(fp dark-180.png)" "$W/root")
[ "$got" = "$(printf '/opt/app/resources/app.asar:images/logo.png\t%s' "$(dh dark-180.png dark-64.png)")" ] \
  || fail "find names the asar entry and its distance, got: $got"
cp "$W/f/dark-180.png" "$W/root/usr/share/icons/a b/dark.png"
got=$(python3 "$T" find "$(fp dark-180.png)" "$W/root")
[ "$got" = "$(printf '/usr/share/icons/a b/dark.png\t0')" ] || fail "find prefers the exact picture, path with a space intact, got: $got"
sim() { python3 "$T" similar "$(fp "$1")" "$(fp "$2")"; }
sim dark-64.png dark-180.png || fail "the same picture at another size is similar"
! sim dark-180.png blue-180.png || fail "a recolour is not similar"
! sim dark-64.png bars-64.png || fail "a different picture is not similar"
[ "$(dist dark-64.png dark-64-trailing.png | cut -d' ' -f1)" = "dhash:0" ] || fail "bytes after IEND are ignored"
out=$(python3 "$T" fingerprint "$W/f/dark-64-truncated.png" 2>&1) && fail "a truncated PNG is refused"
case $out in "icon-tool: "*) ;; *) fail "a truncated PNG is refused cleanly, not with a traceback: $out" ;; esac
[ "$(dh dark-64.png dark-64-rgbkey.png)" -le 2 ] || fail "an RGB colour key (tRNS) is transparency: $(dist dark-64.png dark-64-rgbkey.png)"
out=$(python3 "$T" fingerprint "$W/f/huge.png" 2>&1) && fail "an icon over 2048 px is refused"
printf '%s' "$out" | grep -q 2048 || fail "the refusal names the limit: $out"
out=$(python3 "$T" distance "sha256:abc" "$(fp dark-64.png)" 2>&1) && fail "a malformed fingerprint is refused"
case $out in "icon-tool: "*) ;; *) fail "a malformed fingerprint is refused cleanly: $out" ;; esac
ln -s /nonexistent/icon.png "$W/root/usr/share/icons/dangling.png"
cp "$W/f/bad.asar" "$W/root/opt/app/resources/bad.asar"
got=$(python3 "$T" find "$(fp dark-180.png)" "$W/root") || fail "a dangling symlink or a malformed asar does not stop find"
[ "$(python3 "$T" same-dhash)" = 10 ] || fail "same-dhash prints the threshold"
echo "ok icon-tool"
