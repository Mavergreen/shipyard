#!/bin/sh
# platform: host-agnostic -- the outputs are compared to fixed text, so every host must print the same; on a Mac, lsbom and pkgutil --expand also check them
#   usage: pkg-read-test.sh
#          scripts/pkg_read.sh over a product archive and a flat component that build_component_pkg.sh
#          and stevedore build here, and over fd 10.5.0-mavericks.18, a published family pkg fetched
#          by its release URL and verified against its SHA256SUMS (over the network).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/scripts/pkg_read.sh"
_tmp="${TMPDIR:-/tmp}"
W="$(cd -P "$(mktemp -d "${_tmp%/}/pkg-read.XXXXXX")" && pwd)"; trap 'rm -rf "$W"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
same() {
  printf '%s\n' "$2" > "$W/want"
  printf '%s\n' "$3" > "$W/got"
  diff "$W/want" "$W/got" > "$W/diff" || { cat "$W/diff"; fail "$1"; }
}
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
STEVEDORE="$(sh "$ROOT/scripts/fetch_stevedore.sh")"; export STEVEDORE
LC_ALL=C; export LC_ALL

mkdir -p "$W/base/usr/local/mavergreen/.base" "$W/bs" "$W/prod/usr/local/mavergreen/widget/bin" \
  "$W/prod/usr/local/mavergreen/widget/share/a dir" "$W/ps"
echo base > "$W/base/usr/local/mavergreen/.base/x"
printf '#!/bin/sh\nexit 0\n' > "$W/bs/postinstall"
printf '#!/bin/sh\necho tool\n' > "$W/prod/usr/local/mavergreen/widget/bin/tool"
chmod 755 "$W/prod/usr/local/mavergreen/widget/bin/tool"
echo doc > "$W/prod/usr/local/mavergreen/widget/share/a dir/read me"
chmod 644 "$W/prod/usr/local/mavergreen/widget/share/a dir/read me"
ln -s bin/tool "$W/prod/usr/local/mavergreen/widget/tool"
cat > "$W/prod/usr/local/mavergreen/widget/mavergreen.plist" <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>identifier</key>
	<string>dev.mavergreen.widget</string>
	<key>name</key>
	<string>Widget &amp; Co for Mavericks</string>
	<key>product</key>
	<string>widget</string>
	<key>version</key>
	<string>2.0-mavericks.3</string>
</dict>
</plist>
PL
chmod 644 "$W/prod/usr/local/mavergreen/widget/mavergreen.plist"
printf '#!/bin/sh\nexit 0\n' > "$W/ps/preinstall"; cp "$W/ps/preinstall" "$W/ps/postinstall"
chmod 755 "$W/bs/postinstall" "$W/ps/preinstall" "$W/ps/postinstall"
sh "$ROOT/scripts/build_component_pkg.sh" --root "$W/base" --identifier dev.mavergreen.base --version 1.0.9 \
  --install-location / --scripts "$W/bs" --out "$W/base.pkg" > /dev/null 2>&1 || fail 'build_component_pkg.sh: base'
sh "$ROOT/scripts/build_component_pkg.sh" --root "$W/prod" --identifier dev.mavergreen.widget --version 2.0-mavericks.3 \
  --install-location / --scripts "$W/ps" --out "$W/prod.pkg" > /dev/null 2>&1 || fail 'build_component_pkg.sh: widget'
cat > "$W/dist.xml" <<'DIST'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>Widget for Mavericks</title>
  <allowed-os-versions><os-version min="10.9.5"/></allowed-os-versions>
  <options customize="never" require-scripts="true" hostArchitectures="x86_64,arm64"/>
  <choices-outline><line choice="dev.mavergreen.base"/><line choice="dev.mavergreen.widget"/></choices-outline>
  <choice id="dev.mavergreen.base" visible="false"><pkg-ref id="dev.mavergreen.base"/></choice>
  <choice id="dev.mavergreen.widget" visible="false"><pkg-ref id="dev.mavergreen.widget"/></choice>
  <pkg-ref id="dev.mavergreen.base" version="1.0.9" onConclusion="none">#base.pkg</pkg-ref>
  <pkg-ref id="dev.mavergreen.widget" version="2.0-mavericks.3" onConclusion="none">#prod.pkg</pkg-ref>
</installer-gui-script>
DIST
P="$W/widget-2.0-mavericks.3.pkg"
"$STEVEDORE" product --distribution "$W/dist.xml" --package "$W/base.pkg" --package "$W/prod.pkg" \
  --mtime 1700000000 --out "$P" > /dev/null || fail 'stevedore product'

rc=0; sh "$R" list "$P" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "list without a component: exit $rc, want 2"
rc=0; sh "$R" frob "$P" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "an unknown subcommand: exit $rc, want 2"

sh "$R" expand "$P" "$W/x" || fail 'expand failed'
[ -f "$W/x/Distribution" ] && [ -f "$W/x/prod.pkg/Payload" ] || fail "expand left no Distribution or prod.pkg/Payload: $(ls "$W/x")"
rc=0; sh "$R" expand "$P" "$W/x" 2> "$W/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'already exists' "$W/err" || fail "expand into an existing DIR: exit $rc, $(cat "$W/err")"

widget_list='.	40755	0	0
./usr	40755	0	0
./usr/local	40755	0	0
./usr/local/mavergreen	40755	0	0
./usr/local/mavergreen/widget	40755	0	0
./usr/local/mavergreen/widget/bin	40755	0	0
./usr/local/mavergreen/widget/bin/tool	100755	0	0
./usr/local/mavergreen/widget/mavergreen.plist	100644	0	0
./usr/local/mavergreen/widget/share	40755	0	0
./usr/local/mavergreen/widget/share/a dir	40755	0	0
./usr/local/mavergreen/widget/share/a dir/read me	100644	0	0
./usr/local/mavergreen/widget/tool	120755	0	0'
same 'list dev.mavergreen.widget' "$widget_list" "$(sh "$R" list "$P" dev.mavergreen.widget)"
same 'list reads an expanded directory as it reads the pkg' "$widget_list" "$(sh "$R" list "$W/x" dev.mavergreen.widget)"
same 'list dev.mavergreen.base' '.	40755	0	0
./usr	40755	0	0
./usr/local	40755	0	0
./usr/local/mavergreen	40755	0	0
./usr/local/mavergreen/.base	40755	0	0
./usr/local/mavergreen/.base/x	100644	0	0' "$(sh "$R" list "$P" dev.mavergreen.base)"
rc=0; sh "$R" list "$P" dev.mavergreen.nope > /dev/null 2> "$W/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'expected one component dev.mavergreen.nope' "$W/err" || fail "an absent component: exit $rc, $(cat "$W/err")"

product_facts='component dev.mavergreen.base install-location /
component dev.mavergreen.base script postinstall
component dev.mavergreen.base version 1.0.9
component dev.mavergreen.widget install-location /
component dev.mavergreen.widget script postinstall
component dev.mavergreen.widget script preinstall
component dev.mavergreen.widget version 2.0-mavericks.3
distribution host-architectures x86_64,arm64
distribution os-version-min 10.9.5
distribution pkg-ref dev.mavergreen.base 1.0.9
distribution pkg-ref dev.mavergreen.widget 2.0-mavericks.3'
same 'facts of the product archive' "$product_facts" "$(sh "$R" facts "$P")"
same 'facts of a flat component' 'component dev.mavergreen.base install-location /
component dev.mavergreen.base script postinstall
component dev.mavergreen.base version 1.0.9' "$(sh "$R" facts "$W/base.pkg")"

same 'plist keys, in the order asked' 'widget
2.0-mavericks.3
Widget & Co for Mavericks' "$(sh "$R" plist "$P" product version name)"
rc=0; sh "$R" plist "$P" version nosuchkey > /dev/null 2> "$W/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'no scalar nosuchkey' "$W/err" || fail "a missing manifest key: exit $rc, $(cat "$W/err")"
rc=0; sh "$R" plist "$W/base.pkg" version > /dev/null 2> "$W/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'found 0' "$W/err" || fail "a pkg with no manifest: exit $rc, $(cat "$W/err")"

sh "$R" payload "$P" dev.mavergreen.widget "$W/p" || fail 'payload failed'
[ "$(cat "$W/p/usr/local/mavergreen/widget/share/a dir/read me")" = doc ] && [ -x "$W/p/usr/local/mavergreen/widget/bin/tool" ] \
  && [ -L "$W/p/usr/local/mavergreen/widget/tool" ] && [ ! -e "$W/p/usr/local/mavergreen/.base" ] \
  || fail "payload did not unpack the widget component, and only it: $(cd "$W/p" && find . | sort)"
sh "$R" payload "$W/x" dev.mavergreen.widget "$W/q" '*usr/local/mavergreen/widget/mavergreen.plist' || fail 'payload with a pattern failed'
same 'payload with a pattern unpacks only what it matches' './usr/local/mavergreen/widget/mavergreen.plist' \
  "$(cd "$W/q" && find . -type f | sort)"

mkdir -p "$W/bad"
printf '#!/bin/sh\nexit 1\n' > "$W/bad/gzip"; printf '#!/bin/sh\ncat > /dev/null\n' > "$W/bad/cpio"; chmod +x "$W/bad/gzip" "$W/bad/cpio"
rc=0; PATH="$W/bad:$PATH" sh "$R" payload "$W/x" dev.mavergreen.widget "$W/r" 2> "$W/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'could not decompress the Payload of dev.mavergreen.widget' "$W/err" || fail "a failing gzip: exit $rc, $(cat "$W/err")"
printf '#!/bin/sh\nexec dd if=/dev/zero bs=65536 count=256 2>/dev/null\n' > "$W/bad/gzip"; printf '#!/bin/sh\nexit 1\n' > "$W/bad/cpio"
rc=0; PATH="$W/bad:$PATH" sh "$R" payload "$W/x" dev.mavergreen.widget "$W/r" 2> "$W/err" || rc=$?
[ "$rc" -eq 1 ] && grep -q 'could not unpack the Payload of dev.mavergreen.widget' "$W/err" && ! grep -q decompress "$W/err" \
  || fail "a failing cpio is not blamed on the gzip it stops reading: exit $rc, $(cat "$W/err")"

FD_TAG=10.5.0-mavericks.18
FD="$(sh "$ROOT/scripts/fetch-release-pkg.sh" fd "$FD_TAG" "fd-$FD_TAG.pkg" "$W/fd")" || fail "could not fetch and verify fd-$FD_TAG.pkg"
same 'facts of the published fd pkg' 'component dev.mavergreen.base install-location /
component dev.mavergreen.base script postinstall
component dev.mavergreen.base version 1.0.827
component dev.mavergreen.fd install-location /
component dev.mavergreen.fd script postinstall
component dev.mavergreen.fd script preinstall
component dev.mavergreen.fd version 10.5.0-mavericks.18
distribution host-architectures x86_64
distribution os-version-min 10.9.5
distribution pkg-ref dev.mavergreen.base 1.0.827
distribution pkg-ref dev.mavergreen.fd 10.5.0-mavericks.18' "$(sh "$R" facts "$FD")"
same 'plist of the published fd pkg' "fd
$FD_TAG" "$(sh "$R" plist "$FD" product version)"
sh "$R" list "$FD" dev.mavergreen.fd > "$W/fd.list"
sh "$R" list "$FD" dev.mavergreen.base > "$W/base.list"
same 'the published fd pkg lists its fd binary' './usr/local/mavergreen/fd/bin/fd	100755	0	0' \
  "$(grep '^\./usr/local/mavergreen/fd/bin/fd	' "$W/fd.list")"
same 'the published fd pkg lists the same entries on every host' '319 ff47b243' \
  "$(wc -l < "$W/fd.list" | tr -d ' ') $(cksum < "$W/fd.list" | awk '{ printf "%08x", $1 }')"

if [ "$(uname -s)" = Darwin ]; then
  for pkg in "$P" "$FD"; do
    rm -rf "$W/pu"
    # platform: guarded macOS-only call -- the cross-check of stevedore's reading against Apple's own tools
    pkgutil --expand "$pkg" "$W/pu" || fail "pkgutil --expand $pkg"
    same "facts read from pkgutil --expand of ${pkg##*/}" "$(sh "$R" facts "$pkg")" "$(sh "$R" facts "$W/pu")"
    for pi in "$W"/pu/*/PackageInfo; do
      id="$(xmllint --xpath 'string(/pkg-info/@identifier)' "$pi")"
      ver="$(xmllint --xpath 'string(/pkg-info/@version)' "$pi")"
      loc="$(xmllint --xpath 'string(/pkg-info/@install-location)' "$pi")"
      grep -qxF "component $id version $ver" "$W/got" && grep -qxF "component $id install-location $loc" "$W/got" \
        || fail "facts disagree with xmllint on $pi: $id $ver $loc"
      # platform: guarded macOS-only call -- lsbom reads the component's Bom, which pkg_read.sh never does
      lsbom -p fmug "${pi%/PackageInfo}/Bom" | sort > "$W/bom"
      sh "$R" list "$pkg" "$id" > "$W/lst"
      diff "$W/bom" "$W/lst" > "$W/diff" || { cat "$W/diff"; fail "list of $id in ${pkg##*/} disagrees with lsbom -p fmug"; }
    done
    ha="$(xmllint --xpath 'string(//options/@hostArchitectures)' "$W/pu/Distribution")"
    grep -qxF "distribution host-architectures $ha" "$W/got" || fail "facts disagree with xmllint on hostArchitectures $ha"
  done
fi
echo 'PASS: pkg_read.sh expands, lists, unpacks and reads the manifest and facts of a built and a published pkg'
