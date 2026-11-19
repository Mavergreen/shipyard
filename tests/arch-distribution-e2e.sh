#!/bin/sh
# platform: macOS-only -- Installer, hdiutil and diskutil
#   usage: sudo MAVERGREEN_E2E=1 sh tests/arch-distribution-e2e.sh
#          Builds one product archive per Distribution class (an Intel-only payload with and without
#          the newer-macos deviation, a universal payload whose arm64 slice needs macOS 13 and one
#          whose needs macOS 28, a payload with no Mach-O file with and without the deviation) from
#          a scratch MAVERGREEN_REPO_ROOT, and installs each onto a fresh scratch disk image with
#          installer -pkg P -target V, never onto /. On a 10.9 or 10.10 Intel Mac every archive
#          installs; on an Apple Silicon Mac running macOS 13 through 27 the archives install or
#          are refused as the class says, and the run records which refusal message the Intel-only
#          archive got. Exits 77 unless run as root with MAVERGREEN_E2E=1, or on a host it has no
#          expectations for. Fetches stevedore into its own work directory unless STEVEDORE or
#          STEVEDORE_CACHE say otherwise.
set -eu
umask 022
LC_ALL=C; export LC_ALL
[ "$(uname -s)" = Darwin ] || { echo "SKIP: arch-distribution-e2e runs on macOS only"; exit 77; }
[ "$(id -u)" = 0 ] && [ "${MAVERGREEN_E2E:-}" = 1 ] || {
  echo "SKIP: run as root with MAVERGREEN_E2E=1"; exit 77; }
OSV="$(sw_vers -productVersion)"
case "$OSV:$(uname -m)" in
  10.9:x86_64|10.9.*:x86_64|10.10:x86_64|10.10.*:x86_64) BOX=old-intel ;;
  1[3-9]*:arm64|2[0-7]*:arm64) BOX=arm64 ;;
  *) echo "SKIP: arch-distribution-e2e has expectations for 10.9 and 10.10 Intel Macs and for macOS 13 through 27 on Apple Silicon, not macOS $OSV $(uname -m)"; exit 77 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd)"
S="$root/scripts"
FX="$root/tests/fixtures/macho"
W="$(mktemp -d "${TMPDIR:-/tmp}/arch-distribution-e2e.XXXXXX")"
. "$root/tests/lib/e2e-volume.sh"
HOST_BEFORE="$(host_state)"; HOST_REPORTED=""
cleanup() {
  _rc=$?
  e2e_detach_all
  if host_changed; then _rc=1; fi
  rm -rf "$W"
  exit "$_rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

: "${SOURCE_DATE_EPOCH:=$(date +%s)}"; export SOURCE_DATE_EPOCH
[ -n "${STEVEDORE:-}" ] || { : "${STEVEDORE_CACHE:=$W/stevedore-cache}"; export STEVEDORE_CACHE; }
STEVEDORE="$(sh "$S/fetch_stevedore.sh")"; export STEVEDORE

BL="$W/build.log"; : > "$BL"
die() { echo "arch-distribution-e2e: $*" >&2; tail -n 40 "$BL" | sed 's/^/    | /' >&2; exit 1; }

REPO="$W/repo"
NEWER="uni13 uni28 x86new neutralnew"
for _s in x86 x86new uni13 uni28 neutral neutralnew; do
  mkdir -p "$REPO/.mavergreen/products/$_s"
  printf 'Arch %s\n' "$_s" > "$REPO/.mavergreen/products/$_s/noun"
  : > "$REPO/.mavergreen/products/$_s/built-on-install"
done
for _s in $NEWER; do
  _dv="$REPO/.mavergreen/deviations/newer-macos/e2e-$_s"
  mkdir -p "$_dv"
  printf '%s\n' "$_s" > "$_dv/scope"
  printf 'this e2e proves the class that serves newer macOS, not a product that does\n' > "$_dv/reason"
  printf 'the arch e2e builds products of real classes\n' > "$_dv/revisit"
done

mkdir -p "$W/comp" "$W/dist"
archive() {
  _short="$1"; _payload="$2"
  rm -rf "$W/st-$_short"; mkdir -p "$W/st-$_short/opt/mavergreen/$_short/bin"
  case "$_payload" in
    sh) printf '#!/bin/sh\nexit 0\n' > "$W/st-$_short/opt/mavergreen/$_short/bin/tool" ;;
    *) cp "$FX/$_payload" "$W/st-$_short/opt/mavergreen/$_short/bin/tool" ;;
  esac
  chmod 755 "$W/st-$_short/opt/mavergreen/$_short/bin/tool"
  rm -rf "$W/scr-$_short"
  MAVERGREEN_REPO_ROOT="$REPO" sh "$S/stage_product.sh" --stage "$W/st-$_short" --product "$_short" --version 1 \
    --scripts-out "$W/scr-$_short" >> "$BL" 2>&1 || return 1
  MAVERGREEN_REPO_ROOT="$REPO" sh "$S/build_component_pkg.sh" --root "$W/st-$_short" --identifier "dev.mavergreen.$_short" \
    --version 1 --install-location / --scripts "$W/scr-$_short" --out "$W/comp/$_short.pkg" >> "$BL" 2>&1 || return 1
  MAVERGREEN_REPO_ROOT="$REPO" sh "$S/set_install_floor.sh" --short "$_short" --version 1 \
    --component "$W/comp/$_short.pkg" --dist "$W/dist" --base-version 0.0.1 --require-scripts 2>> "$BL"
}
echo "arch-distribution-e2e: macOS $OSV $(uname -m), box $BOX, built from this checkout ($root)"
PKG_x86="$(archive x86 clean)" || die "could not build x86"
PKG_x86new="$(archive x86new clean)" || die "could not build x86new"
PKG_uni13="$(archive uni13 fat130)" || die "could not build uni13"
PKG_uni28="$(archive uni28 fat280)" || die "could not build uni28"
PKG_neutral="$(archive neutral sh)" || die "could not build neutral"
PKG_neutralnew="$(archive neutralnew sh)" || die "could not build neutralnew"

n=0; VOL=""
fresh_volume() {
  n=$((n + 1))
  VOL="$(e2e_volume "$n")"
}
drop_volume() {
  e2e_volume_detach "$VOL"
}
install_to() {
  _log="$W/install-$n-$(basename "$1").log"
  _off="$(wc -c < /var/log/install.log 2>/dev/null | tr -d ' ')" || _off=0
  _rc=0; installer -verbose -dumplog -pkg "$1" -target "$VOL" > "$_log" 2>&1 || _rc=$?
  tail -c +"$((${_off:-0} + 1))" /var/log/install.log >> "$_log" 2>/dev/null || :
  return "$_rc"
}
bad() { echo "    FAIL: $*"; [ -z "${_log:-}" ] || { echo "    last installer log ($_log), tail:"; tail -n 40 "$_log" | sed 's/^/    | /'; }; return 1; }

installs() {
  install_to "$1" || bad "$2 did not install" || return 1
  [ -d "$VOL/opt/mavergreen/$2" ] || bad "$VOL/opt/mavergreen/$2 is not there" || return 1
  [ -f "$VOL/opt/mavergreen/$2/mavergreen.plist" ] || bad "$2 has no mavergreen.plist" || return 1
}
refused() {
  ! install_to "$1" || bad "$2 installed, and the class refuses it here" || return 1
  [ ! -e "$VOL/opt/mavergreen/$2" ] && [ ! -L "$VOL/opt/mavergreen/$2" ] || bad "$2 left a tree behind" || return 1
  [ -z "${3:-}" ] || grep -qF "$3" "$_log" || bad "the installer output does not say '$3'" || return 1
}
which_refusal() {
  if grep -qF 'built for Intel Macs.' "$_log"; then echo "    x86 refused with the installation-check's message: built for Intel Macs."
  elif grep -qF 'built for Intel Macs running' "$_log"; then echo "    x86 refused with the installation-check's message: built for Intel Macs running Mac OS X 10.9 or 10.10."
  else echo "    x86 refused with another message: $(grep -iE 'cannot|requires|not supported|operating system|version' "$_log" | sed -n 1p)"; fi
}

run_case() {
  _short="$1"; _want="$2"; _msg="$3"
  eval "_pkg=\$PKG_$_short"
  _log=""
  if fresh_volume; then
    if ( case "$_want" in
           install) installs "$_pkg" "$_short" ;;
           *) refused "$_pkg" "$_short" "$_msg" && { [ "$_short" != x86 ] || which_refusal; } ;;
         esac ); then echo "PASS $_short ($_want)"; else echo "FAIL $_short (expected $_want)"; fails=$((fails + 1)); fi
    drop_volume
  else
    echo "FAIL $_short (no scratch volume)"; fails=$((fails + 1))
  fi
}

fails=0
case "$BOX" in
  old-intel)
    run_case x86 install ""
    run_case x86new install ""
    run_case uni13 install ""
    run_case uni28 install ""
    run_case neutral install ""
    run_case neutralnew install "" ;;
  arm64)
    run_case x86 refuse ""
    run_case x86new refuse "built for Intel Macs."
    run_case uni28 refuse "needs macOS 28.0 or later"
    run_case uni13 install ""
    run_case neutral refuse ""
    run_case neutralnew install "" ;;
esac
if host_changed; then fails=$((fails + 1)); fi
echo "arch-distribution-e2e: $fails failed"
[ "$fails" -eq 0 ]
