#!/bin/sh
# platform: host-agnostic
#   usage: artifact-conformance-standalone-test.sh
#          A release whose pkg installs a product also carries <short>-<version>-macos-<arch>.tar.gz that
#          passed check-standalone-archive.sh, unless conventions-grandfathered names the product
#          (a warning) or INGREDIENTS.md declares '- no-standalone[:<short glob>]: <reason>'; declaring
#          it while publishing one fails. Then artifact-facts.sh judges the archives a dist carries, each
#          against the requires in its product pkg's mavergreen.plist and the repo's deviations; a
#          standalone-text or standalone-install-name entry is unused only when no archive of the
#          release uses it. An archive is archive-first when its repo declares
#          packaging/<short>.standalone-bundled, else pkg-first, which conformance names and does not
#          yet fail.
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
(cd "$w/bad" && tar -czf "$w/dist/w-1.0-macos-arm64.tar.gz" w-1.0) || exit 1
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
(cd "$w/zig" && tar -czf "$w/dist2/w-1.0-macos-arm64.tar.gz" w-1.0) || exit 1
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
mkdir -p "$w/dist4/good/w-1.0/bin"; printf '#!/bin/sh\necho w\n' > "$w/dist4/good/w-1.0/bin/w"
(cd "$w/dist4/good" && tar -czf "$w/dist4/w-1.0-macos-x86_64.tar.gz" w-1.0) || exit 1; rm -rf "$w/dist4/good"
cp "$w/dist2/w-1.0-macos-arm64.tar.gz" "$w/dist4/"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist4" 1.0-mavericks.1 "$w/repo3" 2>"$w/err")" || fail "artifact-facts.sh failed on two archives: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx 'standalone w-1.0-macos-x86_64.tar.gz ok' || fail "an entry one archive uses is no finding in another: $facts"
printf '%s\n' "$facts" | grep -qx 'standalone w-1.0-macos-arm64.tar.gz ok' || fail "the archive the entry excuses passes: $facts"
printf '%s\n' "$facts" | grep -q '^standalone-text-unused' && fail "an entry one archive of two uses is used: $facts"
rm "$w/dist4/w-1.0-macos-arm64.tar.gz"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist4" 1.0-mavericks.1 "$w/repo3" 2>"$w/err")" || fail "artifact-facts.sh failed on one archive: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx 'standalone-text-unused bin/w' || fail "an entry no archive uses is a standalone-text-unused fact: $facts"
no "a standalone-text entry no archive uses" "standalone-text: INGREDIENTS.md's standalone-text:bin/w excuses nothing" "$WITH
standalone-text-unused bin/w"
printf '## Conformance deviations\n- standalone-install-name:*/w/lib/libw.dylib: one copy per process\n' > "$w/repo3/INGREDIENTS.md"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist4" 1.0-mavericks.1 "$w/repo3" 2>"$w/err")" || fail "artifact-facts.sh failed on a declared standalone-install-name: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qxF 'standalone-install-name-unused */w/lib/libw.dylib' || fail "a standalone-install-name entry no archive uses is a fact: $facts"
no "a standalone-install-name entry no archive uses" "standalone-install-name: INGREDIENTS.md's standalone-install-name:\*/w/lib/libw.dylib excuses nothing" "$WITH
standalone-install-name-unused */w/lib/libw.dylib"
printf '## Conformance deviations\n- standalone-text:bin/w: the wrapper names zig\n' > "$w/repo3/INGREDIENTS.md"
echo "ok: artifact-facts.sh passes the repo's deviations to check-standalone-archive.sh, judging unused entries across every archive"

printf '%s\n' "$facts" | grep -qx 'standalone-flow w-1.0-macos-x86_64.tar.gz pkg-first' || fail "an archive whose repo declares no bundled list is pkg-first: $facts"
mkdir -p "$w/repo3/packaging"; : > "$w/repo3/packaging/w.standalone-bundled"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist4" 1.0-mavericks.1 "$w/repo3" 2>"$w/err")" || fail "artifact-facts.sh failed on an archive-first repo: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx 'standalone-flow w-1.0-macos-x86_64.tar.gz archive-first' || fail "an archive whose repo declares packaging/w.standalone-bundled is archive-first: $facts"
mv "$w/repo3/packaging/w.standalone-bundled" "$w/repo3/packaging/v.standalone-bundled"
facts="$(sh "$w/scripts/artifact-facts.sh" "$w/dist4" 1.0-mavericks.1 "$w/repo3" 2>"$w/err")" || fail "artifact-facts.sh failed: $(cat "$w/err")"
printf '%s\n' "$facts" | grep -qx 'standalone-flow w-1.0-macos-x86_64.tar.gz pkg-first' || fail "another product's bundled list does not make w archive-first: $facts"
ok "a pkg-first archive passes" "$WITH
standalone-flow $SA pkg-first"
printf '%s\n' "$out" | grep -q "^conformance: standalone: $SA: pkg-first" || fail "a pkg-first archive is named: $out"
ok "an archive-first archive passes" "$WITH
standalone-flow $SA archive-first"
printf '%s\n' "$out" | grep -q 'pkg-first' && fail "an archive-first archive draws no note: $out"
echo "ok: artifact-facts.sh tells an archive-first product from a pkg-first one, and conformance names the pkg-first"

if CL="$(sh "$w/scripts/fetch_clang22.sh" "$here/../components/clang22" 2>/dev/null)"; then
  U=w-1.0-macos-universal.tar.gz
  mkdir -p "$w/fat/w-1.0/bin" "$w/dist5" "$w/noclang" "$w/components"
  cp -R "$here/../components/clang22" "$w/components/clang22"
  printf 'int main(void) { return 0; }\n' > "$w/m.c"
  exe() { "$CL/bin/clang" --no-default-config -target "$1" -nostdlib -fuse-ld=lld -Wl,-e,_main -Wl,-platform_version,macos,"$2","$3" "$w/m.c" -o "$w/$4" 2>/dev/null; }
  if exe x86_64-apple-macos10.9 10.9 10.9 m64 && exe arm64-apple-macos11.0 11.0 11.3 marm; then
    "$CL/bin/llvm-lipo" -create "$w/m64" "$w/marm" -output "$w/fat/w-1.0/bin/w" || fail "llvm-lipo could not make a universal tool"
  else
    "$CL/bin/clang" --no-default-config -target x86_64-apple-macos10.9 -c "$w/m.c" -o "$w/m64.o" \
      && "$CL/bin/clang" --no-default-config -target i386-apple-macos10.9 -c "$w/m.c" -o "$w/m32.o" \
      && "$CL/bin/llvm-lipo" -create "$w/m32.o" "$w/m64.o" -output "$w/fat/w-1.0/bin/w" || fail "clang22 could not make a fat object"
    printf '## Conformance deviations\n- sdk-pin:*/bin/w: i386 has no pinned SDK; this clang22 builds no arm64\n' > "$w/dist5/INGREDIENTS.md"
  fi
  (cd "$w/fat" && tar -czf "$w/dist5/$U" w-1.0) || exit 1
  rc=0; facts="$(unset NM OTOOL LIPO
    # platform: off macOS artifact-facts.sh reads Mach-O only through the LIPO and OTOOL its caller sets
    [ "$(uname -s)" = Darwin ] || { LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; export LIPO OTOOL; }
    SHIPYARD_MG_PREFIX="$w/noclang" sh "$w/scripts/artifact-facts.sh" "$w/dist5" 1.0 "$w/dist5" 2>"$w/err")" || rc=$?
  [ "$rc" -eq 0 ] || fail "artifact-facts.sh, as stand-in-feeds.sh calls it with no installed clang22, reads a universal archive's Mach-O: $(cat "$w/err")"
  printf '%s\n' "$facts" | grep -qx "standalone $U ok" || fail "a universal archive's Mach-O is judged with the reader check-standalone-archive.sh fetches: $facts"
  echo "ok: artifact-facts.sh judges a universal archive with no installed clang22, as check-standalone-archive.sh alone does"
else
  echo "skip: no clang22 to build a universal Mach-O"
fi

echo "PASS: artifact-conformance-standalone"
