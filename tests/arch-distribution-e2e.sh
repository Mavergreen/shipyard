#!/bin/sh
# platform: macOS-only -- Installer, hdiutil and diskutil
#   usage: sudo MAVERGREEN_E2E=1 sh tests/arch-distribution-e2e.sh
#          Builds one product archive per Distribution class (an Intel-only payload with and without
#          the newer-macos deviation, a universal payload whose arm64 slice needs macOS 13 and one
#          whose needs macOS 28, a payload with no Mach-O file with and without the deviation) from
#          a scratch MAVERGREEN_REPO_ROOT, and installs each onto a fresh scratch disk image with
#          installer -pkg P -target V, never onto /. On a 10.9 or 10.10 Intel Mac every archive
#          installs; on an Apple Silicon Mac running macOS 11 through 27 the archives install or
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
  1[1-9]*:arm64|2[0-7]*:arm64) BOX=arm64 ;;
  *) echo "SKIP: arch-distribution-e2e has expectations for 10.9 and 10.10 Intel Macs and for macOS 11 through 27 on Apple Silicon, not macOS $OSV $(uname -m)"; exit 77 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd)"
S="$root/scripts"
FX="$root/tests/fixtures/macho"
W="$(mktemp -d "${TMPDIR:-/tmp}/arch-distribution-e2e.XXXXXX")"
. "$root/tests/lib/e2e-volume.sh"
. "$root/scripts/lib/vercmp.sh"
HOST_BEFORE="$(host_state)"; HOST_REPORTED=""
e2e_trap

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
  rm -rf "$W/st-$_short" && mkdir -p "$W/st-$_short/opt/mavergreen/$_short/bin" || return 1
  case "$_payload" in
    sh) printf '#!/bin/sh\nexit 0\n' > "$W/st-$_short/opt/mavergreen/$_short/bin/tool" || return 1 ;;
    *) cp "$FX/$_payload" "$W/st-$_short/opt/mavergreen/$_short/bin/tool" || return 1 ;;
  esac
  chmod 755 "$W/st-$_short/opt/mavergreen/$_short/bin/tool" || return 1
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

installs() {
  install_to "$1" || bad "$2 did not install" || return 1
  [ -d "$VOL/opt/mavergreen/$2" ] || bad "$VOL/opt/mavergreen/$2 is not there" || return 1
  [ -f "$VOL/opt/mavergreen/$2/mavergreen.plist" ] || bad "$2 has no mavergreen.plist" || return 1
}
SCRIPTS_FAIL='error occurred while running scripts|preinstall'
INTEL_MSG='built for Intel Macs'
OS_MSG='The version of macOS is too new'
refusal_lines() { grep -iE "$INTEL_MSG|$OS_MSG|needs macOS|refus|cannot|failed|not (supported|compatible)" "$_log" | sed -n 1,12p | sed 's/^/    | /'; }
refused() {
  ! install_to "$1" || bad "$2 installed, and the class refuses it here" || return 1
  [ ! -e "$VOL/opt/mavergreen/$2" ] && [ ! -L "$VOL/opt/mavergreen/$2" ] || bad "$2 left a tree behind" || return 1
  if grep -qiE "$SCRIPTS_FAIL" "$_log"; then
    bad "$2 was refused by a failing install script, not by its Distribution; the refusal lines:" "$(refusal_lines)" || return 1
  fi
  if [ -n "${3:-}" ]; then
    grep -qF "$3" "$_log" && { echo "    $2 refused with the installation-check's message: $(grep -F "$3" "$_log" | sed -n 1p)"; return 0; }
    bad "$2's refusal does not say '$3'; the refusal lines:" "$(refusal_lines)" || return 1
  fi
  if grep -qiE "$OS_MSG" "$_log"; then
    echo "    $2 refused by allowed-os-versions: $(grep -iE "$OS_MSG" "$_log" | sed -n 1p)"; return 0
  fi
  bad "$2 was refused with no recognised refusal; the refusal lines:" "$(refusal_lines)" || return 1
}

run_case() {
  _short="$1"; _want="$2"; _msg="$3"
  eval "_pkg=\$PKG_$_short"
  _log=""
  if fresh_volume; then
    if ( case "$_want" in
           install) installs "$_pkg" "$_short" ;;
           *) refused "$_pkg" "$_short" "$_msg" ;;
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
    run_case x86 refuse "built for Intel Macs running Mac OS X 10.9 or 10.10."
    run_case x86new refuse "built for Intel Macs."
    run_case uni28 refuse "needs macOS 28.0 or later"
    if [ "$(mavergreen_vercmp "$OSV" 13.0)" = -1 ]; then run_case uni13 refuse "needs macOS 13.0 or later"
    else run_case uni13 install ""; fi
    run_case neutral refuse ""
    run_case neutralnew install "" ;;
esac
if host_changed; then fails=$((fails + 1)); fi
echo "arch-distribution-e2e: $fails failed"
[ "$fails" -eq 0 ]
