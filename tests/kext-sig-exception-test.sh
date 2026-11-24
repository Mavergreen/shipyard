#!/bin/sh
# platform: host-agnostic
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Kexts that load at boot" --
#       scripts/kext_sig_exception.sh, against a copy of 10.9.5 (13F1911)'s AppleKextExcludeList Info.plist
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
X="$here/../scripts/kext_sig_exception.sh"
REAL="$here/fixtures/kext-sig-exception/AppleKextExcludeList-13F1911.plist"
t="$(mktemp -d "${TMPDIR:-/tmp}/kext-sig-exception.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }
ID=dev.mavergreen.example.bootkext
P="$t/Info.plist"
tab="$(printf '\t')"
entries() { awk -v id="$1" 'index($0, "<key>" id "</key>") { n++; getline; v = v $0 } END { print n + 0, v }' "$P"; }
siglist() { awk '/<key>OSKextSigExceptionList<\/key>/ { f = 1; next } f && /<\/dict>/ { exit } f' "$P"; }
excl() { awk '/<key>OSKextExcludeList<\/key>/ { f = 1 } f { print } f && /<\/dict>/ { exit }' "$1"; }

excl "$REAL" > "$t/excl"
grep -q "<key>$ID</key>" "$REAL" && bad "the fixture already lists $ID"

echo "== add"
cp "$REAL" "$P"
sh "$X" add "$P" "$ID" 2611.23.4 || bad "add failed"
[ "$(entries "$ID")" = "1 ${tab}${tab}<string>2611.23.4</string>" ] || bad "add: want one entry at 2611.23.4, got: $(entries "$ID")"
siglist | grep -q "<key>$ID</key>" || bad "add: the entry is not in OSKextSigExceptionList"
excl "$P" | grep -q "$ID" && bad "add: the entry went into OSKextExcludeList"
excl "$P" | cmp -s - "$t/excl" || bad "add: OSKextExcludeList changed"
n="$(grep -n "^${tab}<key>OSKextSigExceptionList</key>\$" "$REAL" | cut -d: -f1)"
sed -n "$((n + 2)),$((n + 3))p" "$P" > "$t/added"
printf '\t\t<key>%s</key>\n\t\t<string>2611.23.4</string>\n' "$ID" | cmp -s - "$t/added" || bad "add: the entry is not the list's first two lines: $(cat "$t/added")"
sed "$((n + 2)),$((n + 3))d" "$P" | cmp -s - "$REAL" || bad "add changed other bytes"
[ "$(ls -l "$P" | cut -c1-10)" = "-rw-r--r--" ] || bad "add: the file is not mode 644"
ls "$t" | grep -q shipyard && bad "add left a temporary file"

echo "== idempotent add"
cp "$P" "$t/once"
sh "$X" add "$P" "$ID" 2611.23.4 || bad "a second add failed"
cmp -s "$P" "$t/once" || bad "a second add of the same version changed the file"

echo "== replace"
sh "$X" add "$P" "$ID" 2612.1.1 || bad "replace failed"
[ "$(entries "$ID")" = "1 ${tab}${tab}<string>2612.1.1</string>" ] || bad "replace: want one entry at 2612.1.1, got: $(entries "$ID")"

echo "== remove"
sh "$X" remove "$P" "$ID" || bad "remove failed"
cmp -s "$P" "$REAL" || bad "remove did not restore Apple's file byte for byte"

echo "== remove an absent entry"
sh "$X" remove "$P" "$ID" || bad "removing an absent entry must succeed"
cmp -s "$P" "$REAL" || bad "removing an absent entry changed the file"

echo "== round trips"
for v in 1.0 2611.24.1 1.0.0d1; do
  sh "$X" add "$P" "$ID" "$v" && sh "$X" remove "$P" "$ID" || bad "round trip at $v failed"
  cmp -s "$P" "$REAL" || bad "round trip at $v is not byte-identical"
done
sh "$X" add "$P" "$ID" 1.0 && sh "$X" add "$P" dev.mavergreen.example.second 2.0 \
  && sh "$X" remove "$P" "$ID" && sh "$X" remove "$P" dev.mavergreen.example.second || bad "two-id round trip failed"
cmp -s "$P" "$REAL" || bad "two-id round trip is not byte-identical"

echo "== an id Apple also lists elsewhere stays out of OSKextExcludeList"
sh "$X" add "$P" com.vmware.kext.vmci 9.9 || bad "add of an id in both lists failed"
excl "$P" | cmp -s - "$t/excl" || bad "OSKextExcludeList changed when its id was added to the exception list"

echo "== refusals"
cp "$REAL" "$P"
for a in "add $P" "add $P $ID" "remove $P" "frob $P $ID 1.0" "add $P bad<id 1.0" "add $P $ID 1.0<x" "add $P -x 1.0"; do
  if sh "$X" $a 2>/dev/null; then bad "accepted: $a"; fi
done
cmp -s "$P" "$REAL" || bad "a refused call changed the file"
printf 'bplist00binary' > "$P"
if sh "$X" add "$P" "$ID" 1.0 2>/dev/null; then bad "a binary plist was edited"; fi
[ "$(cat "$P")" = bplist00binary ] || bad "a refused binary plist changed"
grep -v OSKextSigExceptionList "$REAL" > "$P"; cp "$P" "$t/nolist"
if sh "$X" add "$P" "$ID" 1.0 2>/dev/null; then bad "a plist without OSKextSigExceptionList was edited"; fi
cmp -s "$P" "$t/nolist" || bad "a refused plist without the list changed"
if sh "$X" add "$t/absent" "$ID" 1.0 2>/dev/null; then bad "a missing plist reported success"; fi
[ ! -e "$t/absent" ] || bad "a missing plist was created"

[ "$fail" = 0 ] && echo "kext-sig-exception OK"
exit "$fail"
