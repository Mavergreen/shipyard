#!/bin/sh
# platform: host-agnostic
#   usage: artifact-conformance-standalone-test.sh
#          A release whose pkg installs a product also carries <short>-<version>-macos-<arch>.tar.gz that
#          passed check-standalone-archive.sh, unless conventions-grandfathered names the product
#          (a warning) or INGREDIENTS.md declares '- no-standalone[:<short glob>]: <reason>'; declaring
#          it while publishing one fails. Then artifact-facts.sh judges the archives a dist carries, each
#          against the requires in its product pkg's mavergreen.plist and the repo's deviations.
set -eu
unset GITHUB_REPOSITORY
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/conformance-standalone.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cp -R "$here/../scripts" "$w/scripts"; rm -f "$w/scripts/conventions-grandfathered"
S="$w/scripts/check-artifact-conformance.sh"
fail() { echo "FAIL: conformance-standalone: $*"; exit 1; }
run() {  # facts on stdin; sets rc and out
  rc=0; out="$( { cat; printf 'end-of-facts\n'; } | sh "$S" 2>&1)" || rc=$?
}
ok() {  # $1 = label, $2 = facts
  run <<EOF
$2
EOF
  [ "$rc" -eq 0 ] || fail "$1: expected pass: $out"
}
no() {  # $1 = label, $2 = phrase, $3 = facts
  run <<EOF
$3
EOF
  [ "$rc" -ne 0 ] || fail "$1: expected failure: $out"
  printf '%s\n' "$out" | grep -q -- "$2" || fail "$1: should say '$2': $out"
}

PK=w-1.0-mavericks.1.pkg
BASE="expected 1.0-mavericks.1
pkg $PK 1.0-mavericks.1 10.9.5 dev.mavergreen.w
component $PK dev.mavergreen.base
component $PK dev.mavergreen.w
manifest $PK w dev.mavergreen.w w
manifest-line $PK none
manifest-appcast $PK none
registered w dev.mavergreen.w w
installs $PK usr/local/mavergreen/w/bin/w
installs $PK usr/local/mavergreen/w/mavergreen.plist
asset $PK 4096"
SA=w-1.0-mavericks.1-macos-x86_64.tar.gz
WITH="$BASE
asset $SA 2048
standalone $SA ok"

no "a product pkg with no standalone archive" "no-standalone: w: $PK ships w" "$BASE"
ok "a product pkg with a standalone archive that passed" "$WITH"
ok "a universal archive" "$BASE
asset w-1.0-mavericks.1-macos-universal.tar.gz 2048
standalone w-1.0-mavericks.1-macos-universal.tar.gz ok"
no "an archive for another version" "no-standalone: w:" "$BASE
asset w-0.9-mavericks.1-macos-x86_64.tar.gz 2048
standalone w-0.9-mavericks.1-macos-x86_64.tar.gz ok"
no "an archive for another product" "no-standalone: w:" "$BASE
asset v-1.0-mavericks.1-macos-x86_64.tar.gz 2048
standalone v-1.0-mavericks.1-macos-x86_64.tar.gz ok"
no "an archive check-standalone-archive refused" "standalone: $SA: bin/w x loads /usr/local/mavergreen/w/lib/libw.dylib" "$BASE
asset $SA 2048
standalone $SA fail bin/w%20x%20loads%20/usr/local/mavergreen/w/lib/libw.dylib"
no "an archive nobody checked" "standalone: $SA: artifact-facts.sh did not judge it" "$BASE
asset $SA 2048"
no "a refused archive fails whatever ships beside it" "standalone: v-1.0-macos-arm64.tar.gz: it holds an updater" "$WITH
asset v-1.0-macos-arm64.tar.gz 10
standalone v-1.0-macos-arm64.tar.gz fail it%20holds%20an%20updater"

ok "a declared no-standalone" "$BASE
deviation no-standalone a kext loads only from /Library/Extensions; there is nothing to run from a directory"
printf '%s\n' "$out" | grep -q 'no-standalone: DECLARED DEVIATION (w)' || fail "a declared no-standalone is reported: $out"
ok "a no-standalone scoped to the product" "$BASE
deviation no-standalone:w SDK data, read by a compiler that knows its installed path"
no "a no-standalone scoped to another product" "no-standalone: w:" "$BASE
deviation no-standalone:sdk* SDK data, read by a compiler that knows its installed path"
no "a no-standalone with no reason" "no reason" "$BASE
deviation no-standalone"
no "a no-standalone beside a standalone archive" "declares no-standalone" "$WITH
deviation no-standalone a kext loads only from /Library/Extensions"
no "another check's deviation" "no-standalone: w:" "$BASE
deviation install-path a reason for something else"
ok "a pkg with no product needs no archive" "expected 1.0-mavericks.1
pkg base.pkg 1.0-mavericks.1 10.9.5 dev.mavergreen.base
component base.pkg dev.mavergreen.base
installs base.pkg usr/local/mavergreen/.base/1.0/mavergreen
asset base.pkg 10"

printf 'standalone w w\n' > "$w/scripts/conventions-grandfathered"
run <<EOF
$BASE
EOF
[ "$rc" -eq 0 ] || fail "a grandfathered product without an archive warns, never fails: $out"
printf '%s\n' "$out" | grep -q '^::warning::conformance: standalone: w: .*(grandfathered: standalone w w)$' \
  || fail "a grandfathered product is a ::warning:: naming its line: $out"
printf 'standalone other w\n' > "$w/scripts/conventions-grandfathered"
no "another repo's grandfathered line" "no-standalone: w:" "$BASE"
printf 'macos-runner w w\n' > "$w/scripts/conventions-grandfathered"
no "another check's grandfathered line" "no-standalone: w:" "$BASE"
rm -f "$w/scripts/conventions-grandfathered"
echo "ok: check-artifact-conformance.sh requires the standalone archive"

mkdir -p "$w/repo"; printf '# Build ingredients\n\n## Conformance deviations\n\n- no-standalone: a kext loads only from /Library/Extensions\n- no-standalone:sdk1*: SDK data\n' > "$w/repo/INGREDIENTS.md"
d="$(sh "$w/scripts/deviations.sh" "$w/repo")" || fail "deviations.sh refuses no-standalone"
printf '%s\n' "$d" | grep -qx 'no-standalone \* a kext loads only from /Library/Extensions' || fail "an unscoped no-standalone parses: $d"
printf '%s\n' "$d" | grep -qx 'no-standalone sdk1\* SDK data' || fail "a scoped no-standalone parses: $d"

R="$w/root/usr/local/mavergreen/w"; mkdir -p "$R/bin" "$w/dist"
printf '#!/bin/sh\necho w\n' > "$R/bin/w"; chmod 755 "$R/bin/w"
SOURCE_DATE_EPOCH=1700000000 sh "$w/scripts/stage_standalone.sh" "$w/root" w 1.0-mavericks.1 x86_64 "$w/dist/$SA" 2>/dev/null \
  || fail "stage_standalone.sh could not build the dist's archive"
mkdir -p "$w/bad/w-1.0/bin"; printf '#!/usr/local/mavergreen/w/bin/sh\n' > "$w/bad/w-1.0/bin/w"
(cd "$w/bad" && tar -czf "$w/dist/w-1.0-macos-arm64.tar.gz" w-1.0)
printf 'x\n' > "$w/dist/w-1.0-linux-x86_64.tar.gz.txt"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist" 1.0-mavericks.1 "$w/repo" 2>"$w/err")" || fail "artifact-facts.sh failed: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx "standalone $SA ok" || fail "artifact-facts.sh judges a good archive ok: $facts"
printf '%s\n' "$facts" | grep -q '^standalone w-1.0-macos-arm64.tar.gz fail bin/w%20is%20a%20script' || fail "artifact-facts.sh carries a refused archive's first finding: $facts"
printf '%s\n' "$facts" | grep -q 'standalone w-1.0-linux' && fail "only a -macos-<arch>.tar.gz is a standalone archive: $facts"
echo "ok: artifact-facts.sh judges every standalone archive in the dist"

ST="$(sh "$w/scripts/fetch_stevedore.sh")" || fail "no stevedore"
R="$w/root2/usr/local/mavergreen/w"; mkdir -p "$R/bin" "$w/dist2"
printf '#!/bin/sh\nexec /usr/local/mavergreen/clang22/bin/clang "$@"\n' > "$R/bin/w"; chmod 755 "$R/bin/w"
SOURCE_DATE_EPOCH=1700000000 sh "$w/scripts/stage_standalone.sh" "$w/root2" w 1.0-mavericks.1 x86_64 "$w/dist2/$SA" > /dev/null 2>&1 \
  || fail "stage_standalone.sh could not build the archive naming a require"
mkdir -p "$w/zig/w-1.0/bin"; printf '#!/bin/sh\nexec /usr/local/mavergreen/zig/bin/zig "$@"\n' > "$w/zig/w-1.0/bin/w"
(cd "$w/zig" && tar -czf "$w/dist2/w-1.0-macos-arm64.tar.gz" w-1.0)
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>product</key>\n  <string>w</string>\n  <key>identifier</key>\n  <string>dev.mavergreen.w</string>\n  <key>version</key>\n  <string>1.0-mavericks.1</string>\n  <key>requires</key>\n  <array>\n    <string>clang22</string>\n  </array>\n</dict>\n</plist>\n' > "$R/mavergreen.plist"
"$ST" component --root "$w/root2" --identifier dev.mavergreen.w --version 1.0-mavericks.1 --install-location / --mtime 1700000000 --out "$w/dist2/$PK" > /dev/null \
  || fail "stevedore could not build the pkg"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist2" 1.0-mavericks.1 "$w/repo" 2>"$w/err")" || fail "artifact-facts.sh failed on a pkg and its archives: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx "standalone $SA ok" || fail "artifact-facts.sh passes the pkg's mavergreen.plist, whose requires the archive's script names: $facts"
printf '%s\n' "$facts" | grep -q '^standalone w-1.0-macos-arm64.tar.gz fail bin/w%20names%20/usr/local/mavergreen/zig:%20an%20undeclared%20dependency' \
  || fail "artifact-facts.sh carries an undeclared dependency: $facts"
echo "ok: artifact-facts.sh judges each archive against its pkg's declared requires"
mkdir -p "$w/dist3" "$w/repo3"; cp "$w/dist2/w-1.0-macos-arm64.tar.gz" "$w/dist3/"
printf '## Conformance deviations\n- standalone-text:bin/w: the wrapper names zig\n' > "$w/repo3/INGREDIENTS.md"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist3" 1.0-mavericks.1 "$w/repo3" 2>"$w/err")" || fail "artifact-facts.sh failed on a declared standalone-text: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx 'standalone w-1.0-macos-arm64.tar.gz ok' || fail "artifact-facts.sh passes the repo's standalone-text deviations to the checker: $facts"
echo "ok: artifact-facts.sh passes the repo's deviations to check-standalone-archive.sh"

echo "PASS: artifact-conformance-standalone"
