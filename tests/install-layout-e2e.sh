#!/bin/sh
# platform: macOS-only -- Installer, hdiutil and diskutil
#   usage: sudo MAVERGREEN_E2E=1 MAVERGREEN_E2E_PKG=/path/to/shipyard-V.pkg sh tests/install-layout-e2e.sh
#          Installs MAVERGREEN_E2E_PKG onto fresh scratch disk images (HFS+ before 10.13, APFS after),
#          never onto /, and checks the /opt layout end to end: a first install, a group-writable /opt
#          refused, an Applications/Mavergreen symlink refused, an upgrade, and an uninstall whose
#          launchctl, pkgutil and sudo are logging stubs. Exits 77 unless run as root with
#          MAVERGREEN_E2E=1 and MAVERGREEN_E2E_PKG set. Fetches stevedore and the cmake release named
#          by .mavergreen/products/shipyard/requires/cmake/min, into its own work directory unless
#          STEVEDORE, STEVEDORE_CACHE or MAVERGREEN_PKG_CACHE say otherwise.
set -eu
umask 022
LC_ALL=C; export LC_ALL
[ "$(uname -s)" = Darwin ] || { echo "SKIP: install-layout-e2e runs on macOS only"; exit 77; }
[ "$(id -u)" = 0 ] && [ "${MAVERGREEN_E2E:-}" = 1 ] && [ -n "${MAVERGREEN_E2E_PKG:-}" ] || {
  echo "SKIP: run as root with MAVERGREEN_E2E=1 and MAVERGREEN_E2E_PKG=<shipyard pkg>"; exit 77; }
[ -f "$MAVERGREEN_E2E_PKG" ] || { echo "install-layout-e2e: no such pkg: $MAVERGREEN_E2E_PKG" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd)"
S="$root/scripts"
PKG="$(cd "$(dirname "$MAVERGREEN_E2E_PKG")" && pwd -P)/$(basename "$MAVERGREEN_E2E_PKG")"
W="$(mktemp -d "${TMPDIR:-/tmp}/install-layout-e2e.XXXXXX")"
DEVS=""
host_state() {
  for _p in $(pkgutil --pkgs 2>/dev/null | grep '^dev\.mavergreen\.' | sort); do
    printf 'receipt %s %s\n' "$_p" "$(pkgutil --pkg-info "$_p" 2>/dev/null | grep -E '^(version|install-time):' | tr '\n' ' ')"
  done
  for _f in /opt/mavergreen /usr/local/mavergreen /usr/local/bin/mavergreen /etc/paths.d/mavergreen /Applications/Mavergreen /Library/LaunchAgents/dev.mavergreen.*; do
    if [ -e "$_f" ] || [ -L "$_f" ]; then ls -ldT "$_f"; else echo "absent $_f"; fi
  done
}
HOST_BEFORE="$(host_state)"; HOST_REPORTED=""
host_changed() {
  _now="$(host_state)"
  [ "$_now" != "$HOST_BEFORE" ] || return 1
  [ -n "$HOST_REPORTED" ] && return 0
  HOST_REPORTED=1
  echo "FAIL THE RUNNING SYSTEM CHANGED: its Mavergreen receipts or paths differ from before the run"
  echo "  before:"; printf '%s\n' "$HOST_BEFORE" | sed 's/^/    /'
  echo "  after:"; printf '%s\n' "$_now" | sed 's/^/    /'
}
cleanup() {
  _rc=$?
  for d in $DEVS; do hdiutil detach -quiet "$d" 2>/dev/null || hdiutil detach -quiet -force "$d" 2>/dev/null || true; done
  if host_changed; then _rc=1; fi
  rm -rf "$W"
  exit "$_rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

: "${SOURCE_DATE_EPOCH:=$(date +%s)}"; export SOURCE_DATE_EPOCH
: "${MAVERGREEN_PKG_CACHE:=$W/pkg-cache}"; export MAVERGREEN_PKG_CACHE
[ -n "${STEVEDORE:-}" ] || { : "${STEVEDORE_CACHE:=$W/stevedore-cache}"; export STEVEDORE_CACHE; }
STEVEDORE="$(sh "$S/fetch_stevedore.sh")"; export STEVEDORE

case "$(sw_vers -productVersion)" in
  10.[0-9]|10.[0-9].*|10.1[0-2]|10.1[0-2].*) FS=HFS+ ;;
  *) FS=APFS ;;
esac

BL="$W/build.log"; : > "$BL"
die() { echo "install-layout-e2e: $*" >&2; tail -n 40 "$BL" | sed 's/^/    | /' >&2; exit 1; }
pkg_version() {
  rm -rf "$W/expand"; pkgutil --expand "$1" "$W/expand" >/dev/null
  for _pi in "$W"/expand/*/PackageInfo; do
    grep -q "identifier=\"$2\"" "$_pi" || continue
    sed -n 's/.*<pkg-info[^>]*[[:space:]]version="\([^"]*\)".*/\1/p' "$_pi" | sed -n 1p
  done
}

V0="$(pkg_version "$PKG" dev.mavergreen.shipyard)"
case "$V0" in ''|*[!0-9.]*|.*|*.|*..*) die "$PKG has no dev.mavergreen.shipyard component with a dotted numeric version (got '$V0')" ;; esac
V1="${V0%.*}.$((${V0##*.} + 1))"
MIN="$(sed -n 1p "$root/.mavergreen/products/shipyard/requires/cmake/min")"
CMAKE_WANT="$(printf '%s\n' "$MIN" | sed 's/-mavericks\..*//; s/-mavergreen\..*//')"
CMAKE_REPO="$(sed -n 1p "$root/.mavergreen/ingredients/cmake/REPO")"
checkout_head() {
  _gd="$root/.git"
  if [ -f "$_gd" ]; then _gd="$(sed -n 's/^gitdir: //p' "$_gd")"; case "$_gd" in /*) ;; *) _gd="$root/$_gd" ;; esac; fi
  _cd="$_gd"
  if [ -f "$_gd/commondir" ]; then _cd="$(sed -n 1p "$_gd/commondir")"; case "$_cd" in /*) ;; *) _cd="$_gd/$_cd" ;; esac; fi
  _h="$(sed -n 1p "$_gd/HEAD" 2>/dev/null)" || _h=""
  case "$_h" in
    'ref: '*)
      _r="${_h#ref: }"
      sed -n 1p "$_gd/$_r" 2>/dev/null || sed -n 1p "$_cd/$_r" 2>/dev/null \
        || sed -n "s|^\([0-9a-f]*\) $_r\$|\1|p" "$_cd/packed-refs" 2>/dev/null || echo unknown ;;
    '') echo "unknown (no .git)" ;;
    *) printf '%s\n' "$_h" ;;
  esac
}
echo "install-layout-e2e: $PKG (shipyard $V0, upgrade to $V1), $FS images, cmake seed $MIN on macOS $(sw_vers -productVersion) $(uname -m)"
echo "install-layout-e2e: the upgrade, seed and toy pkgs, and their dev.mavergreen.base, are built from this checkout ($root, HEAD $(checkout_head))"

fixture_repo() {
  mkdir -p "$W/repo/.mavergreen/products/$1"
  printf '%s\n' "$2" > "$W/repo/.mavergreen/products/$1/noun"
  : > "$W/repo/.mavergreen/products/$1/built-on-install"
}
fixture_pkg() {
  _short="$1"; _ver="$2"; _st="$3"; shift 3
  rm -rf "$W/scr-$_short"
  MAVERGREEN_REPO_ROOT="$W/repo" sh "$S/stage_product.sh" --stage "$_st" --product "$_short" --version "$_ver" \
    --scripts-out "$W/scr-$_short" "$@" >> "$BL" 2>&1 || return 1
  MAVERGREEN_REPO_ROOT="$W/repo" sh "$S/build_component_pkg.sh" --root "$_st" --identifier "dev.mavergreen.$_short" \
    --version "$_ver" --install-location / --scripts "$W/scr-$_short" --out "$W/comp/$_short.pkg" >> "$BL" 2>&1 || return 1
  MAVERGREEN_REPO_ROOT="$W/repo" sh "$S/set_install_floor.sh" --short "$_short" --version "$_ver" \
    --component "$W/comp/$_short.pkg" --dist "$W/dist" --base-version 0.0.1 --require-scripts \
    --host-arch x86_64,arm64 2>> "$BL"
}
mkdir -p "$W/comp" "$W/dist"

sh "$S/fetch_product_pkg.sh" --repo "$CMAKE_REPO" cmake "$MIN" "$W/cmake-tree" >> "$BL" 2>&1 \
  || die "could not fetch $CMAKE_REPO $MIN's cmake tree"
fixture_repo cmake CMake
mkdir -p "$W/seed/opt/mavergreen"
cp -R "$W/cmake-tree" "$W/seed/opt/mavergreen/cmake"
rm -f "$W/seed/opt/mavergreen/cmake/mavergreen.plist"
SEED="$(fixture_pkg cmake "$MIN" "$W/seed" --exclude bin/cmake --exclude bin/ctest --exclude bin/cpack)" \
  || die "could not build the cmake seed pkg"

fixture_repo e2etoy "E2E Toy"
TA="$W/toy/Applications/Mavergreen/E2EToy.app/Contents"
mkdir -p "$TA/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$TA/MacOS/E2EToy"; chmod 755 "$TA/MacOS/E2EToy"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict>' \
  '<key>CFBundleIdentifier</key><string>dev.mavergreen.e2etoy</string>' \
  '<key>CFBundleExecutable</key><string>E2EToy</string>' \
  '<key>CFBundlePackageType</key><string>APPL</string>' \
  '<key>CFBundleVersion</key><string>1</string>' \
  '</dict></plist>' > "$TA/Info.plist"
TOY="$(fixture_pkg e2etoy 1 "$W/toy")" || die "could not build the toy pkg"

rm -rf "$W/up"; mkdir -p "$W/up/root"
pkg_version "$PKG" dev.mavergreen.shipyard >/dev/null
for _pi in "$W"/expand/*/PackageInfo; do
  grep -q 'identifier="dev.mavergreen.shipyard"' "$_pi" || continue
  ( cd "$W/up/root" && gzip -dc "$(dirname "$_pi")/Payload" | cpio -id --quiet )
done
rm -f "$W/up/root/opt/mavergreen/shipyard/mavergreen.plist"
UPGRADE="$W/up/dist/shipyard-$V1.pkg"
sh "$S/package-pkg.sh" --shipyard-prefix "$W/up/root/opt/mavergreen/shipyard" \
  --app "$W/up/root/Library/Application Support/Mavergreen/shipyard-updater.app" \
  --version "$V1" --dist "$W/up/dist" >> "$BL" 2>&1 \
  || die "could not repackage $PKG's payload as shipyard $V1"
[ -f "$UPGRADE" ] || die "package-pkg.sh made no $UPGRADE"
sh "$S/assert_pkg_installs_in_place.sh" "$PKG" "$UPGRADE" "$SEED" "$TOY" >> "$BL" 2>&1 \
  || die "a pkg would not install in place"

n=0; VOL=""
fresh_volume() {
  n=$((n + 1))
  _name="MGE2E$$-$n"
  hdiutil create -quiet -size 600m -fs "$FS" -volname "$_name" "$W/$_name.dmg" || return 1
  _out="$(hdiutil attach -nobrowse -owners on "$W/$_name.dmg")" || return 1
  _dev="$(printf '%s\n' "$_out" | sed -n '1s/[[:space:]].*//p')"
  VOL="$(printf '%s\n' "$_out" | sed -n 's|.*[[:space:]]\(/Volumes/[^[:space:]]*\)[[:space:]]*$|\1|p' | sed -n '$p')"
  case "$_dev" in
    /dev/disk[0-9]*) DEVS="$_dev $DEVS" ;;
    *) echo "attach named no /dev/diskN: $_out"; return 1 ;;
  esac
  [ "$VOL" = "/Volumes/$_name" ] || { echo "attach did not mount /Volumes/$_name: $_out"; return 1; }
  _info="$(diskutil info "$VOL")" || return 1
  _d="${_dev#/dev/}"
  _whole="$(printf '%s\n' "$_info" | sed -n 's/^ *Part of Whole: *//p')"
  _store="$(printf '%s\n' "$_info" | sed -n 's/^ *APFS Physical Store: *//p')"
  case "$_whole" in "$_d") ;; *)
    case "$_store" in "${_d}s"[0-9]*) ;; *) echo "$VOL is on $_whole (store '$_store'), not the image's $_dev"; return 1 ;; esac ;;
  esac
  if ! printf '%s\n' "$_info" | grep -q 'Owners:.*Enabled'; then
    diskutil enableOwnership "$VOL" >/dev/null || return 1
    diskutil info "$VOL" | grep -q 'Owners:.*Enabled' || { echo "ownership is still off on $VOL"; return 1; }
  fi
  mkdir "$VOL/.e2e-owner-probe" && chown 1:1 "$VOL/.e2e-owner-probe" || return 1
  [ "$(stat -f %u:%g "$VOL/.e2e-owner-probe")" = 1:1 ] \
    || { echo "$VOL does not honor ownership: a chown 1:1 reads back $(stat -f %u:%g "$VOL/.e2e-owner-probe")"; return 1; }
  rmdir "$VOL/.e2e-owner-probe"
  chown root:wheel "$VOL" && chmod 755 "$VOL" || return 1
  [ "$(stat -f '%u:%g %Lp' "$VOL")" = "0:0 755" ] || { echo "$VOL is $(stat -f '%u:%g %Lp' "$VOL"), not 0:0 755: ownership is not honored"; return 1; }
  mkdir -p "$VOL/System/Library/CoreServices"
  cp /System/Library/CoreServices/SystemVersion.plist "$VOL/System/Library/CoreServices/"
}
drop_volume() {
  hdiutil detach -quiet "$_dev" 2>/dev/null || hdiutil detach -quiet -force "$_dev"
  DEVS="$(printf '%s\n' "$DEVS" | sed "s|$_dev ||")"
  rm -f "$W/$_name.dmg"
}
install_to() {
  _log="$W/install-$n-$(basename "$1").log"
  _off="$(wc -c < /var/log/install.log 2>/dev/null | tr -d ' ')" || _off=0
  _rc=0; installer -verbose -dumplog -pkg "$1" -target "$VOL" > "$_log" 2>&1 || _rc=$?
  tail -c +"$((${_off:-0} + 1))" /var/log/install.log >> "$_log" 2>/dev/null || :
  return "$_rc"
}
bad() { echo "    FAIL: $*"; [ -z "${_log:-}" ] || { echo "    last installer log ($_log), tail:"; tail -n 40 "$_log" | sed 's/^/    | /'; }; return 1; }
mode_is() { [ "$(stat -f '%Su:%Sg %Lp' "$1")" = "$2" ] || bad "$1 is $(stat -f '%Su:%Sg %Lp' "$1"), not $2"; }
mg() { sh "$VOL/opt/mavergreen/bin/mavergreen" --root "$VOL" "$@"; }
seed_and_install() {
  install_to "$SEED" || bad "the cmake seed did not install" || return 1
  install_to "$PKG" || bad "shipyard $V0 did not install" || return 1
}

scenario_fresh() {
  [ ! -e "$VOL/opt" ] && [ ! -L "$VOL/opt" ] || bad "a fresh volume already has opt" || return 1
  ! install_to "$PKG" || bad "shipyard $V0 installed with no cmake on the volume" || return 1
  ! grep -qF "/opt/mavergreen: missing" "$_log" || bad "shipyard's preinstall ran before base's" || return 1
  grep -qF "needs cmake installed first" "$_log" || bad "the install log does not name the missing cmake" || return 1
  [ ! -e "$VOL/opt/mavergreen/shipyard" ] || bad "opt/mavergreen/shipyard was installed without cmake" || return 1
  mode_is "$VOL/opt" "root:wheel 755" || return 1
  mode_is "$VOL/opt/mavergreen" "root:wheel 755" || return 1
  seed_and_install || return 1
  mode_is "$VOL/opt" "root:wheel 755" || return 1
  mode_is "$VOL/opt/mavergreen" "root:wheel 755" || return 1
  [ "$(readlink "$VOL/opt/mavergreen/bin/mavergreen")" = ../mavergreen/bin/mavergreen ] \
    || bad "opt/mavergreen/bin/mavergreen links to '$(readlink "$VOL/opt/mavergreen/bin/mavergreen" || :)'" || return 1
  [ -f "$VOL/opt/mavergreen/mavergreen/bin/mavergreen" ] && [ ! -L "$VOL/opt/mavergreen/mavergreen/bin/mavergreen" ] \
    || bad "opt/mavergreen/bin/mavergreen does not resolve to a file in opt/mavergreen/mavergreen/" || return 1
  [ "$(mg version)" = "$V0" ] || bad "the helper is version '$(mg version)', not the pkg's $V0" || return 1
  grep -qx /opt/mavergreen/bin "$VOL/etc/paths.d/mavergreen" \
    || bad "etc/paths.d/mavergreen does not name /opt/mavergreen/bin: $(cat "$VOL/etc/paths.d/mavergreen" 2>&1)" || return 1
  mg list | grep -qx "shipyard shipyard - $V0 selected" || bad "list has no shipyard line: $(mg list 2>&1)" || return 1
  _c="$(mg check 2>&1)" && [ -z "$_c" ] || bad "check is not silent with exit 0: $_c" || return 1
  sh "$S/assert-installed-shipyard.sh" --cmake-version "$CMAKE_WANT" --root "$VOL" || bad "assert-installed-shipyard.sh failed" || return 1
  [ ! -e "$VOL/usr/local" ] && [ ! -L "$VOL/usr/local" ] || bad "something was installed under usr/local: $(ls -A "$VOL/usr/local")" || return 1
  echo "    receipts on the volume: $(find "$VOL/var/db/receipts" "$VOL/Library/Receipts" -type f 2>/dev/null | sed "s|^$VOL/||" | tr '\n' ' ')"
}

scenario_group_writable_opt() {
  mkdir -m 755 "$VOL/opt"; chown root:wheel "$VOL/opt"; chmod g+w "$VOL/opt"
  ! install_to "$PKG" || bad "Installer accepted a group-writable opt" || return 1
  [ ! -e "$VOL/opt/mavergreen/shipyard" ] || bad "opt/mavergreen/shipyard was installed" || return 1
  grep -qF "$VOL/opt: group-writable" "$_log" || bad "the install log does not name $VOL/opt as group-writable" || return 1
}

scenario_symlinked_applications() {
  mkdir -m 755 "$VOL/elsewhere" "$VOL/Applications"
  ln -s "$VOL/elsewhere" "$VOL/Applications/Mavergreen"
  ! install_to "$TOY" || bad "Installer accepted an Applications/Mavergreen symlink" || return 1
  [ -z "$(ls -A "$VOL/elsewhere")" ] || bad "elsewhere is not empty: $(ls -A "$VOL/elsewhere")" || return 1
  [ -L "$VOL/Applications/Mavergreen" ] && [ "$(readlink "$VOL/Applications/Mavergreen")" = "$VOL/elsewhere" ] \
    || bad "Applications/Mavergreen is no longer the symlink it was" || return 1
  grep -qF "$VOL/Applications/Mavergreen: symlink" "$_log" || bad "the install log does not name the Applications/Mavergreen symlink" || return 1
}

scenario_upgrade() {
  seed_and_install || return 1
  mkdir -p "$VOL/opt/mavergreen/var/shipyard"; echo kept > "$VOL/opt/mavergreen/var/shipyard/e2e-marker"
  [ "$(cat "$VOL/opt/mavergreen/var/mavergreen/selections/shipyard" 2>/dev/null)" = shipyard ] \
    || bad "the first install selected nothing for the shipyard group" || return 1
  install_to "$UPGRADE" || bad "shipyard $V1 did not install over $V0" || return 1
  mg list | grep -qx "shipyard shipyard - $V1 selected" || bad "list after the upgrade: $(mg list 2>&1)" || return 1
  [ "$(cat "$VOL/opt/mavergreen/var/shipyard/e2e-marker" 2>/dev/null)" = kept ] || bad "var/shipyard did not survive the upgrade" || return 1
  [ "$(cat "$VOL/opt/mavergreen/var/mavergreen/selections/shipyard" 2>/dev/null)" = shipyard ] \
    || bad "the shipyard selection did not survive the upgrade" || return 1
  [ "$(cat "$VOL/opt/mavergreen/.base/installed-version")" = "$V1" ] && [ ! -e "$VOL/opt/mavergreen/.base/$V1" ] \
    || bad "the base did not record $V1 and clear its staging: $(ls -A "$VOL/opt/mavergreen/.base")" || return 1
  _c="$(mg check 2>&1)" && [ -z "$_c" ] || bad "check after the upgrade: $_c" || return 1
}

scenario_uninstall() {
  seed_and_install || return 1
  _id="$(/usr/libexec/PlistBuddy -c 'Print :identifier' "$VOL/opt/mavergreen/shipyard/mavergreen.plist")"
  mkdir -p "$W/stubs"; : > "$W/stub.log"
  for c in launchctl pkgutil sudo; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$c" "$W/stub.log" > "$W/stubs/$c"; chmod 755 "$W/stubs/$c"
  done
  PATH="$W/stubs:/usr/bin:/bin:/usr/sbin:/sbin" sh "$VOL/opt/mavergreen/bin/mavergreen" --root "$VOL" uninstall shipyard \
    || bad "uninstall shipyard failed" || return 1
  [ "$(cat "$W/stub.log")" = "pkgutil --volume $VOL --forget $_id" ] || bad "the stubs logged: $(cat "$W/stub.log")" || return 1
  [ ! -e "$VOL/opt/mavergreen/shipyard" ] || bad "opt/mavergreen/shipyard is still there" || return 1
  _left="$(ls "$VOL/opt/mavergreen/bin" | grep '^shipyard-' || :)"
  [ -z "$_left" ] || bad "farm links left: $_left" || return 1
  [ ! -e "$VOL/opt/mavergreen/var/mavergreen/selections/shipyard" ] || bad "the shipyard selection is still there" || return 1
  [ ! -e "$VOL/Library/Application Support/Mavergreen/shipyard-updater.app" ] || bad "the updater is still there" || return 1
  [ ! -e "$VOL/Library/LaunchAgents/dev.mavergreen.shipyard-updatecheck.plist" ] || bad "the agent plist is still there" || return 1
  [ -x "$VOL/opt/mavergreen/mavergreen/bin/mavergreen" ] && [ -L "$VOL/opt/mavergreen/bin/mavergreen" ] \
    || bad "the helper went with shipyard" || return 1
}

fails=0
for sc in fresh group_writable_opt symlinked_applications upgrade uninstall; do
  _log=""
  if fresh_volume; then
    if ( "scenario_$sc" ); then echo "PASS $sc"; else echo "FAIL $sc"; fails=$((fails + 1)); fi
    drop_volume
  else
    echo "FAIL $sc (no scratch volume)"; fails=$((fails + 1))
  fi
done
if host_changed; then fails=$((fails + 1)); fi
echo "install-layout-e2e: $fails failed"
[ "$fails" -eq 0 ]
