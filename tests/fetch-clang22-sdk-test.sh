#!/bin/sh
# platform: host-agnostic
#   usage: fetch-clang22-sdk-test.sh
#          The clang22 prefix fetch_clang22.sh prints holds the SDK its clang.cfg names -- per-user
#          cache, installed prefix and Mac pkg tree alike -- against file:// fixtures.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
H="$here/../scripts/fetch_clang22.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/fetch-clang22-sdk-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
V=22.1.8-mavericks.99
printf 'clang22 dev.mavergreen.clang.clang22 clang-22\nclang22-cross dev.mavergreen.clang.clang22-cross clang-22\n' > "$w/names"
export MAVERGREEN_PRODUCT_NAMES="$w/names" MAVERGREEN_RELEASES="file://$w/releases" MAVERGREEN_TAR_CACHE="$w/tars"
export HOME="$w/home" SHIPYARD_FETCH_TRIES=1 SHIPYARD_FETCH_BACKOFF=0
mkdir -p "$HOME" "$w/pin"
printf '%s\n' "$V" > "$w/pin/version"

mkdir -p "$w/src/MacOSX10.9.sdk/usr/lib" "$w/src/MacOSX10.9.sdk/usr/include"
: > "$w/src/MacOSX10.9.sdk/usr/lib/libSystem.tbd"
( cd "$w/src" && tar -czf "$w/sdk.tar" MacOSX10.9.sdk ) || exit 1
export MAVERICKS_SDK_CACHE="$w/sdkcache" MAVERICKS_SDK_URL="file://$w/sdk.tar"
MAVERICKS_SDK_SHA256="$(shasum -a 256 "$w/sdk.tar" | awk '{print $1}')"; export MAVERICKS_SDK_SHA256
SDK="$w/sdkcache/MacOSX10.9.sdk"

cfg='--target=x86_64-apple-macos
-isysroot <CFGDIR>/../SDKs/MacOSX10.9.sdk
-mmacosx-version-min=10.9'
setup_sdk="#!/bin/sh
echo \"\$1\" >> '$w/setup-sdk.log'
here=\"\$(cd \"\$(dirname \"\$0\")/..\" && pwd -P)\"
mkdir -p \"\$here/SDKs\" && ln -s \"\$(cd \"\$1\" && pwd -P)\" \"\$here/SDKs/MacOSX10.9.sdk\"
echo \"\$here/SDKs/MacOSX10.9.sdk\""
tools() {
  mkdir -p "$1/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$1/bin/$t"; chmod 755 "$1/bin/$t"; done
  printf '%s\n' "$cfg" > "$1/bin/clang.cfg"
  printf '%s\n' "$cfg" > "$1/bin/clang++.cfg"
}
REL="$w/releases/Mavergreen/clang-22/releases/download/$V"
mkdir -p "$REL" "$w/arc/opt/mavergreen/clang22"
tools "$w/arc/opt/mavergreen/clang22"
printf '%s\n' "$setup_sdk" > "$w/arc/opt/mavergreen/clang22/bin/setup-sdk"; chmod 755 "$w/arc/opt/mavergreen/clang22/bin/setup-sdk"
ASSET="clang22-$V-linux-x86_64.tar.gz"
( cd "$w/arc" && tar -czf "$REL/$ASSET" opt ) || exit 1
printf '%s  %s\n' "$(shasum -a 256 "$REL/$ASSET" | awk '{print $1}')" "$ASSET" > "$REL/SHA256SUMS"
real() { ( cd "$1" && pwd -P ) || exit 1; }

out="$(MAVERGREEN_CLANG22_CACHE="$w/c1" CLANG22_HOST=linux sh "$H" "$w/pin")" || fail "the per-user cache fetch must succeed"
[ "$out" = "$w/c1/$V/linux" ] || fail "the per-user cache prefix must be printed, got: $out"
[ -d "$out/SDKs/MacOSX10.9.sdk/usr/include" ] || fail "the per-user cache prefix must hold SDKs/MacOSX10.9.sdk, the SDK its clang.cfg names"
[ "$(real "$out/SDKs/MacOSX10.9.sdk")" = "$(real "$SDK")" ] || fail "SDKs/MacOSX10.9.sdk must be fetch_sdk.sh's pinned SDK"
[ "$(cat "$w/setup-sdk.log")" = "$SDK" ] || fail "the toolchain's own bin/setup-sdk must wire the SDK fetch_sdk.sh prints, got: $(cat "$w/setup-sdk.log")"
MAVERGREEN_CLANG22_CACHE="$w/c1" CLANG22_HOST=linux sh "$H" "$w/pin" > /dev/null || fail "a second fetch must succeed"
[ "$(wc -l < "$w/setup-sdk.log" | tr -d ' ')" = 1 ] || fail "a prefix already holding its SDK must not run setup-sdk again"
rm -rf "$w/sdkcache"
out="$(MAVERICKS_SDK_CACHE="$w/sdkcache2" MAVERGREEN_CLANG22_CACHE="$w/c1" CLANG22_HOST=linux sh "$H" "$w/pin")" || fail "a fetch after the SDK cache was swept must succeed"
[ "$out" = "$w/c1/$V/linux" ] || fail "stdout must be only the prefix after setup-sdk printed, got: $out"
[ -d "$out/SDKs/MacOSX10.9.sdk/usr/include" ] || fail "a link left dangling by a swept SDK cache must be replaced"
[ "$(real "$out/SDKs/MacOSX10.9.sdk")" = "$(real "$w/sdkcache2/MacOSX10.9.sdk")" ] || fail "the replaced link must name the SDK fetched now"

inst="$w/root/usr/local/mavergreen/clang22"
tools "$inst"
printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$V" > "$inst/mavergreen.plist"
mkdir -p "$w/root/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk/usr/include"
out="$(CLANG22_INSTALLED="$inst" CLANG22_HOST=linux sh "$H" "$w/pin")" || fail "an installed prefix must be used"
[ "$out" = "$inst" ] || fail "the installed prefix must be printed, got: $out"
[ -L "$inst/SDKs" ] && [ "$(readlink "$inst/SDKs")" = ../sdk109/SDKs ] \
  || fail "an installed Linux prefix must link SDKs to the sdk109 product beside it, as its pkg does"
if [ "$(id -u)" -ne 0 ]; then
  before="$(ls -ilR "$inst")"
  chmod 555 "$inst"
  out="$(CLANG22_INSTALLED="$inst" CLANG22_HOST=linux sh "$H" "$w/pin")" || { chmod 755 "$inst"; fail "an installed prefix whose SDK resolves must need no write"; }
  chmod 755 "$inst"
  [ "$out" = "$inst" ] && [ "$(ls -ilR "$inst")" = "$before" ] || fail "an installed prefix whose SDK resolves must be left as it is"
fi

if SD="$(sh "$here/../scripts/fetch_stevedore.sh" 2>/dev/null)"; then
  export STEVEDORE="$SD"
  CROSS="$w/stage/root/usr/local/mavergreen/clang22-cross"
  tools "$CROSS"
  ln -s ../sdk109/SDKs "$CROSS/SDKs"
  sh "$here/../scripts/render-manifest.sh" --stage "$w/stage/root" --product clang22-cross --name clang22-cross --version "$V" > /dev/null 2>&1 \
    || fail "the Mac pkg fixture's manifest must render"
  SOURCE_DATE_EPOCH=1700000000 sh "$here/../scripts/build_component_pkg.sh" --root "$w/stage/root" --identifier dev.mavergreen.clang.clang22-cross \
    --version 1.0 --install-location / --out "$w/stage/comp.pkg" > /dev/null 2>&1 || fail "the Mac pkg fixture's component must build"
  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<installer-gui-script minSpecVersion="1">' \
    '  <pkg-ref id="dev.mavergreen.clang.clang22-cross" version="1.0">comp.pkg</pkg-ref>' \
    '  <choices-outline><line choice="dev.mavergreen.clang.clang22-cross"/></choices-outline>' \
    '  <choice id="dev.mavergreen.clang.clang22-cross"><pkg-ref id="dev.mavergreen.clang.clang22-cross"/></choice>' \
    '</installer-gui-script>' > "$w/stage/dist.xml"
  PKG="mavericks-clang-22-cross-$V.pkg"
  "$SD" product --distribution "$w/stage/dist.xml" --package "$w/stage/comp.pkg" \
    --mtime 1700000000 --out "$REL/$PKG" > /dev/null || fail "the Mac pkg fixture must build"
  printf '%s  %s\n' "$(shasum -a 256 "$REL/$PKG" | awk '{print $1}')" "$PKG" >> "$REL/SHA256SUMS"
  out="$(MAVERGREEN_PKG_CACHE="$w/pkgs" MAVERGREEN_CLANG22_CACHE="$w/mc" CLANG22_INSTALLED="$w/absent" CLANG22_HOST=mac sh "$H" "$w/pin" 2> "$w/err")" \
    || fail "the Mac pkg fetch must succeed: $(cat "$w/err")"
  [ "$out" = "$w/mc/$V/clang22-cross" ] || fail "the Mac per-user cache prefix must be printed, got: $out"
  [ -L "$out/SDKs" ] && [ "$(readlink "$out/SDKs")" = ../sdk109/SDKs ] || fail "the pkg's own SDKs link must stay as it shipped"
  [ -d "$out/SDKs/MacOSX10.9.sdk/usr/include" ] || fail "the Mac per-user cache prefix must hold SDKs/MacOSX10.9.sdk through its SDKs link"
  [ "$(real "$out/SDKs/MacOSX10.9.sdk")" = "$(real "$SDK")" ] || fail "the Mac per-user cache's SDK must be fetch_sdk.sh's pinned SDK"

  rm -rf "$w/sdkcache"
  out="$(MAVERICKS_SDK_CACHE="$w/sdkcache3" MAVERGREEN_PKG_CACHE="$w/pkgs" MAVERGREEN_CLANG22_CACHE="$w/mc" CLANG22_INSTALLED="$w/absent" CLANG22_HOST=mac sh "$H" "$w/pin" 2> "$w/err")" \
    || fail "a Mac pkg fetch after the SDK cache was swept must succeed: $(cat "$w/err")"
  [ -d "$out/SDKs/MacOSX10.9.sdk/usr/include" ] || fail "the Mac cache's link left dangling by a swept SDK cache must be replaced"
  [ "$(real "$out/SDKs/MacOSX10.9.sdk")" = "$(real "$w/sdkcache3/MacOSX10.9.sdk")" ] || fail "the Mac cache's replaced link must name the SDK fetched now"
else
  echo "skip: no stevedore (offline?), so the Mac pkg case did not run"
fi

bare="$w/bare/usr/local/mavergreen/clang22-cross"
tools "$bare"
printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$V" > "$bare/mavergreen.plist"
ln -s ../sdk109/SDKs "$bare/SDKs"
if CLANG22_INSTALLED="$bare" CLANG22_HOST=mac sh "$H" "$w/pin" > "$w/out" 2> "$w/err"; then
  fail "an installed prefix whose sdk109 product is absent must fail, not be handed back without its SDK"
fi
grep -q "fetch_clang22: $bare.*MacOSX10.9.sdk.*sdk109" "$w/err" || fail "the failure must name the prefix, the SDK and sdk109, got: $(cat "$w/err")"
[ ! -e "$w/bare/usr/local/mavergreen/sdk109" ] || fail "an installed prefix's sdk109 product must not be made up"
grep -q 'no sdk109 product beside it' "$w/err" || fail "a missing sdk109 must be named as missing, got: $(cat "$w/err")"
if [ "$(id -u)" -ne 0 ]; then
  ro="$w/ro/usr/local/mavergreen/clang22"
  tools "$ro"
  printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$V" > "$ro/mavergreen.plist"
  mkdir -p "$w/ro/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk"
  chmod 555 "$ro"
  if CLANG22_INSTALLED="$ro" CLANG22_HOST=linux sh "$H" "$w/pin" > "$w/out" 2> "$w/err"; then chmod 755 "$ro"; fail "an unwritable prefix with no SDKs must fail"; fi
  chmod 755 "$ro"
  grep -q "fetch_clang22: $ro.*cannot be written" "$w/err" && ! grep -q 'no sdk109 product' "$w/err" \
    || fail "an unwritable prefix must be named as unwritable, not as missing sdk109, got: $(cat "$w/err")"
fi

plain="$w/plain/usr/local/mavergreen/clang22"
tools "$plain"; rm "$plain/bin/clang.cfg" "$plain/bin/clang++.cfg"
printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$V" > "$plain/mavergreen.plist"
out="$(CLANG22_INSTALLED="$plain" CLANG22_HOST=linux MAVERICKS_SDK_URL="file://$w/absent.tar" MAVERICKS_SDK_CACHE="$w/none" sh "$H" "$w/pin")" \
  || fail "a prefix whose cfg names no SDK must need none"
[ ! -e "$plain/SDKs" ] && [ ! -e "$w/none" ] || fail "a prefix whose cfg names no SDK must fetch none"
echo "ok: fetch_clang22.sh prints a prefix holding the SDK its clang.cfg names"
