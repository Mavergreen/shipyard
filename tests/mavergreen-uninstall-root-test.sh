#!/bin/sh
# platform: host-agnostic
#   usage: mavergreen-uninstall-root-test.sh
#          scripts/mavergreen.sh against a staged --root, as a product's package test drives it: a
#          fixture pkg's payloads and postinstalls go into a temporary root, then the installed helper
#          `$ROOT/usr/local/bin/mavergreen --root $ROOT uninstall shipyard` leaves exactly what the base
#          component installed -- no tree, farm link, updater app or LaunchAgent. It reads the manifest
#          with PlistBuddy where there is one and with stevedore (STEVEDORE, or on PATH) everywhere,
#          and both remove the same. With no plist reader at all it fails and removes nothing.
#          Exit 0 clean, 1 on failure.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
S="$root/scripts"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/mavergreen-uninstall-root.XXXXXX")"
trap 'chmod -R u+w "$w" 2>/dev/null; rm -rf "$w"' EXIT
w="$(cd -P "$w" && pwd)"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
STEVEDORE="$(sh "$S/fetch_stevedore.sh")"; export STEVEDORE

sp="$w/sp"
mkdir -p "$sp/bin" "$sp/share/cmake/MavericksShipyard"
for c in cmake ctest cpack; do
  printf '#!/bin/sh\n' > "$sp/bin/shipyard-$c"; chmod +x "$sp/bin/shipyard-$c"
  ln -s "shipyard-$c" "$sp/bin/$c"
done
: > "$sp/share/cmake/MavericksShipyard/MavericksShipyardConfig.cmake"
_tc=/usr/local/mavergreen/shipyard/share/cmake/MavericksShipyard/MavericksToolchain.cmake
printf '{ "configurePresets": [ { "name": "a",\n    "toolchainFile": "%s" } ] }\n' "$_tc" \
  > "$sp/share/cmake/MavericksShipyard/mavericks-presets.json"
app_rel="$(sh "$S/product-name.sh" updater-app shipyard)"
agent="Library/LaunchAgents/$(sh "$S/product-name.sh" agent-label shipyard).plist"
app="$w/app/${app_rel##*/}"
mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\n' > "$app/Contents/MacOS/shipyard-updater"; chmod +x "$app/Contents/MacOS/shipyard-updater"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$(sh "$S/product-name.sh" updater-bundle-id shipyard)</string>
  <key>SUFeedURL</key>
  <string>$(sh "$S/product-name.sh" feed shipyard)</string>
</dict>
</plist>
EOF
sh "$S/package-pkg.sh" --shipyard-prefix "$sp" --app "$app" --version 1.2.3 --out "$w/o.pkg" \
  > "$w/pkg.log" 2>&1 || { echo "FAIL: package-pkg.sh failed:"; sed 's/^/    | /' "$w/pkg.log"; exit 1; }
sh "$S/pkg_read.sh" expand "$w/o.pkg" "$w/x" \
  || { echo "FAIL: could not expand the fixture pkg"; exit 1; }
base="$(grep -lF 'identifier="dev.mavergreen.base"' "$w"/x/*/PackageInfo)"; base="${base%/PackageInfo}"
comp="$(grep -LF 'identifier="dev.mavergreen.base"' "$w"/x/*/PackageInfo)"; comp="${comp%/PackageInfo}"
[ -d "$base" ] && [ -d "$comp" ] || { echo "FAIL: the fixture pkg must carry the base component and shipyard's"; exit 1; }

entries() {  # $1 = root: every file and link under it, sorted
  ( cd "$1" && find . \( -type f -o -type l \) | LC_ALL=C sort ) || exit 1
}
install_into() {  # $1 = root
  mkdir -p "$1"
  for _c in "$base" "$comp"; do
    ( cd "$1" && gzip -dc < "$_c/Payload" | cpio -id --quiet ) || return 1
  done
  sh "$base/Scripts/postinstall" pkg dest "$1" && sh "$comp/Scripts/postinstall" pkg dest "$1"
}

mkdir "$w/base-only"
install_into "$w/full" > "$w/install.log" 2>&1 \
  || { echo "FAIL: the fixture's payloads and postinstalls did not install:"; sed 's/^/    | /' "$w/install.log"; exit 1; }
( cd "$w/base-only" && gzip -dc < "$base/Payload" | cpio -id --quiet ) || exit 1
sh "$base/Scripts/postinstall" pkg dest "$w/base-only" > /dev/null 2>&1 || { echo "FAIL: the base postinstall failed"; exit 1; }
entries "$w/base-only" > "$w/want" || exit 1

run_uninstall() {  # $1 = label  $2 = root  [env assignments...]: uninstall shipyard; leave only the base
  _l="$1"; _r="$2"; shift 2
  install_into "$_r" > /dev/null 2>&1 || { fail "$_l: the fixture did not install"; return 0; }
  [ -d "$_r/$app_rel" ] && [ -f "$_r/$agent" ] || fail "$_l: the fixture installs the updater app and its LaunchAgent"
  _farm="$(cd "$_r/usr/local/mavergreen/bin" && ls | tr '\n' ' ')"
  [ "$_farm" = "shipyard-cmake shipyard-cpack shipyard-ctest " ] \
    || fail "$_l: link reads exports-exclude, so the farm holds only shipyard-cmake, -cpack, -ctest; got '$_farm'"
  _rc=0
  env "$@" "$_r/usr/local/bin/mavergreen" --root "$_r" uninstall shipyard > "$w/un.out" 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] || { fail "$_l: uninstall exited $_rc:"; sed 's/^/    | /' "$w/un.out"; }
  entries "$_r" > "$w/got" || exit 1
  cmp -s "$w/want" "$w/got" || { fail "$_l: uninstall must leave only the base component (< want, > left):"; diff "$w/want" "$w/got" | sed 's/^/    | /' | head -20; }
}

nopb="$w/no-plistbuddy"
run_uninstall "stevedore from STEVEDORE" "$w/r1" MAVERGREEN_PLISTBUDDY="$nopb" STEVEDORE="$STEVEDORE"
mkdir "$w/path"; ln -s "$STEVEDORE" "$w/path/stevedore"
run_uninstall "stevedore on PATH" "$w/r2" MAVERGREEN_PLISTBUDDY="$nopb" STEVEDORE= PATH="$w/path:$PATH"
if [ -x /usr/libexec/PlistBuddy ]; then
  run_uninstall "PlistBuddy" "$w/r3" STEVEDORE=
else
  echo "not run here: the PlistBuddy case (no /usr/libexec/PlistBuddy)"
fi

install_into "$w/r4" > /dev/null 2>&1 || fail "no reader: the fixture did not install"
entries "$w/r4" > "$w/before" || exit 1
_rc=0
env MAVERGREEN_PLISTBUDDY="$nopb" STEVEDORE= PATH="/usr/bin:/bin" \
  "$w/r4/usr/local/bin/mavergreen" --root "$w/r4" uninstall shipyard > "$w/un.out" 2>&1 || _rc=$?
[ "$_rc" -ne 0 ] || fail "with neither PlistBuddy nor stevedore, uninstall must fail, not leave the updater behind"
grep -q stevedore "$w/un.out" || fail "the refusal must say stevedore would do; got '$(cat "$w/un.out")'"
entries "$w/r4" > "$w/after" || exit 1
cmp -s "$w/before" "$w/after" || fail "with no plist reader, uninstall must remove nothing"

[ "$fails" -eq 0 ] || exit 1
echo "PASS: mavergreen-uninstall-root"
