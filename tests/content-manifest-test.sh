#!/bin/sh
# platform: host-agnostic
set -eu
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
here="$(cd "$(dirname "$0")" && pwd)"
CM="$here/../scripts/content-manifest.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/content-manifest.XXXXXX")"; trap 'chmod -R u+rwX "$w" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- every case here reads a pkg"
GITHUB_REPOSITORY=Mavergreen/w; export GITHUB_REPOSITORY

R="$w/repo"
mkdir -p "$R/.mavergreen/products/w/requires/x"
printf 'W\n' > "$R/.mavergreen/products/w/noun"
printf 'library\n' > "$R/.mavergreen/products/w/requires/x/kind"
printf '1.0\n' > "$R/.mavergreen/products/w/requires/x/min"
mkdir -p "$R/.mavergreen/deviations/reproducible/t"
printf 'opt/mavergreen/w/var/*\n' > "$R/.mavergreen/deviations/reproducible/t/scope"
printf 'w stamps its build time into var/\n' > "$R/.mavergreen/deviations/reproducible/t/reason"
printf 'w stops stamping its build time\n' > "$R/.mavergreen/deviations/reproducible/t/revisit"

( . "$here/../scripts/lib/vercmp.sh"
  [ "$(mavergreen_build_version v1.0.871)" = 1.0.871 ] || fail "mavergreen_build_version drops one leading v"
  [ "$(mavergreen_build_version 9.9p2)" = 9.9.2 ] || fail "mavergreen_build_version maps pN"
  [ "$(mavergreen_build_version 1.2.3-mavergreen.4)" = 1.2.3.4 ] || fail "mavergreen_build_version maps -mavergreen.N" ) || exit 1
echo "ok: mavergreen_build_version"

n=0
build() {
  n=$((n + 1)); _v="$1"; _v0="${_v#v}"
  _bv="$(. "$here/../scripts/lib/vercmp.sh"; mavergreen_build_version "$_v")"
  B="$w/b$n"; rm -rf "$B"; mkdir -p "$B/root/opt/mavergreen/w/share/w-$_v0" "$B/root/opt/mavergreen/w/var" \
    "$B/root/opt/mavergreen/w/W.app/Contents" "$B/scripts" "$B/base/opt/mavergreen/base" "$B/dist"
  printf '%s\n' "$_v0" > "$B/root/opt/mavergreen/w/share/w-$_v0/VERSION"
  printf 'head\000%s\000%s\000tail%s' "$_v0" "$_bv" "${BYTE:-}" > "$B/root/opt/mavergreen/w/blob"
  printf 'odd\n' > "$B/root/opt/mavergreen/w/a b%c"
  printf 'built %s\n' "$n" > "$B/root/opt/mavergreen/w/var/stamp"
  [ -z "${NEWLINE:-}" ] || printf 'x\n' > "$B/root/opt/mavergreen/w/new
line"
  ln -s "${LINKT:-share/w-$_v0}" "$B/root/opt/mavergreen/w/current"
  chmod "${FMODE:-0644}" "$B/root/opt/mavergreen/w/blob"
  chmod "${DMODE:-0755}" "$B/root/opt/mavergreen/w/share"
  cat > "$B/root/opt/mavergreen/w/W.app/Contents/Info.plist" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>dev.mavergreen.w.app</string>
	<key>CFBundleShortVersionString</key>
	<string>$_v0</string>
	<key>CFBundleVersion</key>
	<string>$_bv</string>
</dict>
</plist>
XML
  printf '#!/bin/sh\necho installing w %s%s\n' "$_v0" "${POST:-}" > "$B/scripts/postinstall"; chmod 0755 "$B/scripts/postinstall"
  printf 'base\n' > "$B/base/opt/mavergreen/base/marker"
  "$SD" component --root "$B/base" --identifier dev.mavergreen.base --version "${BASEV:-1.0.9}" --install-location / \
    --mtime "$SOURCE_DATE_EPOCH" --out "$B/base.pkg" >/dev/null
  "$SD" component --root "$B/root" --identifier dev.mavergreen.w --version "$_bv" --install-location / \
    --scripts "$B/scripts" --mtime "$SOURCE_DATE_EPOCH" --out "$B/w.pkg" >/dev/null
  cat > "$B/d.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>W</title>
    <allowed-os-versions><os-version min="${FLOOR:-10.9.5}" before="10.11"/></allowed-os-versions>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64"/>
    <choices-outline><line choice="default"><line choice="dev.mavergreen.base"/><line choice="dev.mavergreen.w"/></line></choices-outline>
    <choice id="default"/>
    <choice id="dev.mavergreen.base" visible="false"><pkg-ref id="dev.mavergreen.base"/></choice>
    <choice id="dev.mavergreen.w" visible="false"><pkg-ref id="dev.mavergreen.w"/></choice>
    <pkg-ref id="dev.mavergreen.base" version="${BASEV:-1.0.9}" onConclusion="none">base.pkg</pkg-ref>
    <pkg-ref id="dev.mavergreen.w" version="$_bv" onConclusion="none">w.pkg</pkg-ref>
</installer-gui-script>
XML
  "$SD" product --distribution "$B/d.xml" --package "$B/base.pkg" --package "$B/w.pkg" \
    --mtime "$SOURCE_DATE_EPOCH" --out "$B/dist/w-$_v0.pkg" >/dev/null
}
run() {
  rc=0; sh "$CM" "$1" "$2" "$R" > "$w/out" 2> "$w/err" || rc=$?
  out="$(cat "$w/out")"; err="$(cat "$w/err")"
}
manifest() {
  build "$1"; run "$B/dist" "$1"
  [ "$rc" -eq 0 ] || fail "content-manifest.sh on $1 exits 0: rc $rc: $err"
  printf '%s\n' "$out"
}

base="$(manifest 1.2.3-mavergreen.9)"
for row in 'file w.pkg opt/mavergreen/w/share/w-@VERSION@/VERSION 0644 ' \
           'link w.pkg opt/mavergreen/w/current share/w-@VERSION@' \
           'dir w.pkg opt/mavergreen/w/share 0755' \
           'file w.pkg opt/mavergreen/w/a%20b%25c 0644 ' \
           'meta w.pkg identifier dev.mavergreen.w' \
           'meta w.pkg install-location /' \
           'meta w.pkg script:dev.mavergreen.w:postinstall ' \
           'meta w.pkg floor 10.9.5' 'meta w.pkg before 10.11' 'meta w.pkg arch-rule none' \
           'meta w.pkg host-architectures x86_64' \
           'meta w feed-min-os 10.9.5' \
           'meta w feed-url https://github.com/Mavergreen/w/releases/latest/download/w.xml' \
           'meta w requires x library 1.0'; do
  printf '%s\n' "$base" | grep -qF -- "$row" || fail "the manifest has '$row': $base"
done
printf '%s\n' "$base" | grep -q 'dev.mavergreen.base\|opt/mavergreen/base' && fail "the bundled base component is not content (Q12): $base"
printf '%s\n' "$base" | grep -q 'var/stamp' && fail "a path a reproducible deviation scopes has no row: $base"
printf '%s\n' "$base" | grep -q 'mavergreen\.9\|1\.2\.3\.9' && fail "no row holds the version: $base"
[ "$base" = "$(printf '%s\n' "$base" | LC_ALL=C sort -u)" ] || fail "the manifest is sorted and unique"
echo "ok: rows, encoding, the deviation and the base component"

same() {
  _a="$(manifest "$1")"; _b="$(manifest "$2")"
  [ "$_a" = "$_b" ] || fail "$1 and $2 differ only in the version, so their manifests are identical: $(printf '%s\n' "$_a" > "$w/a"; printf '%s\n' "$_b" > "$w/b"; diff "$w/a" "$w/b" || :)"
}
same 1.2.3-mavergreen.9 1.2.3-mavergreen.10
same 20261123.1 20261124.1
same v1.0.871 v1.0.872
echo "ok: releases differing only in the version, in every scheme, give one manifest"

differs() {
  _c="$(manifest 1.2.3-mavergreen.9)"
  [ "$_c" != "$base" ] || fail "$1 changes the manifest"
}
( BYTE=x; differs "a payload byte" ) || exit 1
( LINKT=elsewhere; differs "a symlink target" ) || exit 1
( FMODE=0755; differs "a file mode" ) || exit 1
( DMODE=0700; differs "a directory mode" ) || exit 1
( POST=' now'; differs "a postinstall byte" ) || exit 1
( FLOOR=10.10; differs "the floor" ) || exit 1
printf '2.0\n' > "$R/.mavergreen/products/w/requires/x/min"
differs "products/w/requires/x/min"
printf '1.0\n' > "$R/.mavergreen/products/w/requires/x/min"
c="$(BASEV=1.0.10; manifest 1.2.3-mavergreen.9)"
[ "$c" = "$base" ] || fail "a different dev.mavergreen.base version leaves the manifest unchanged (Q12)"
echo "ok: each content change changes the manifest, and the base component's version does not"

NEWLINE=1; build 1.2.3-mavergreen.9; NEWLINE=; run "$B/dist" 1.2.3-mavergreen.9
[ "$rc" -eq 1 ] || fail "a payload path with a newline exits 1: rc $rc"
[ -z "$out" ] || fail "a payload path with a newline prints no partial manifest: $out"
build 1.2.3-mavergreen.9; head -c 600 "$B/dist/w-1.2.3-mavergreen.9.pkg" > "$B/t.pkg"
mv "$B/t.pkg" "$B/dist/w-1.2.3-mavergreen.9.pkg"; run "$B/dist" 1.2.3-mavergreen.9
[ "$rc" -eq 1 ] || fail "a truncated pkg exits 1: rc $rc"
[ -z "$out" ] || fail "a truncated pkg prints no partial manifest: $out"
echo "ok: an unreadable artifact or a bad path exits 1 with empty stdout"

build 1.2.3-mavergreen.9
mkdir -p "$w/dsym/x-1.0-mavergreen.1-dSYM"; printf 'dwarf\n' > "$w/dsym/x-1.0-mavergreen.1-dSYM/f"
( cd "$w/dsym" && tar -cf - x-1.0-mavergreen.1-dSYM | gzip > "$B/dist/x-1.0-mavergreen.1-dSYM.tar.gz" )
run "$B/dist" 1.2.3-mavergreen.9
[ "$rc" -eq 0 ] || fail "a dist with a dSYM tarball exits 0: rc $rc: $err"
[ "$out" = "$base" ] || fail "a dSYM tarball adds no row"
mkdir -p "$w/tar/w-1.2.3-mavergreen.9/bin"; printf '1.2.3-mavergreen.9\n' > "$w/tar/w-1.2.3-mavergreen.9/bin/w"
chmod 0755 "$w/tar/w-1.2.3-mavergreen.9/bin/w"
( cd "$w/tar" && tar -cf - w-1.2.3-mavergreen.9 | gzip > "$B/dist/w-1.2.3-mavergreen.9-macos-x86_64.tar.gz" )
run "$B/dist" 1.2.3-mavergreen.9
printf '%s\n' "$out" | grep -qF 'file w-macos-x86_64.tar.gz w-@VERSION@/bin/w 0755 ' \
  || fail "a tarball's rows are relative to its root, the artifact named without the version: $out"
echo "ok: tarballs, and dSYM tarballs skipped"

rc=0; sh "$CM" "$w" 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a usage error exits 2: rc $rc"
echo "PASS: content-manifest"
