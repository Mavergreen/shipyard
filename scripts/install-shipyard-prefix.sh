#!/bin/sh
# platform: host-agnostic
#   usage: install-shipyard-prefix.sh [--root DIR] [--version V]
#          Lays down shipyard's pkg payload from this checkout, without a pkg, where install@v1 on Linux
#          wants it: DIR$(mavergreen_prefix shipyard) (DIR default /), staged by
#          stage-shipyard-prefix.sh and package-pkg.sh --tree-only, so it is the pkg's prefix and
#          mavergreen.plist, less the updater. Its exported names (bin/ less the manifest's
#          exports-exclude) are linked into the bin/ beside that prefix, as the mavergreen helper
#          links them on a Mac. Prints the installed prefix on stdout.
#          Writes as root, else under sudo (when `sudo -n true` succeeds; SUDO= overrides), else into
#          a writable parent of that prefix; with none of those it installs into
#          ${MAVERGREEN_USER_PREFIX:-$HOME/.local/mavergreen}/shipyard instead, saying so on stderr,
#          and that prefix is the one its presets name. The tree is staged beside the prefix in
#          .install-products/shipyard, owned by the caller, and renamed into place whole, an older
#          tree renamed aside first, under that directory's lock (shipyard_lock_take, waiting up to
#          SHIPYARD_LOCK_WAIT seconds, default 900), the lock install-products.sh takes for shipyard.
#          --version is the version the tree and its manifest carry; without it, CMakeLists.txt's.
#          Exit 1 on a failed stage or install, 2 on a usage error.
# spec: tests/linux-shipyard-prefix-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen_fetch.sh"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
die() { echo "install-shipyard-prefix: $*" >&2; exit 1; }
ROOT=/; V=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root|--version)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "install-shipyard-prefix: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --version) V="$2"; shift 2 ;;
    *) echo "usage: install-shipyard-prefix.sh [--root DIR] [--version V]" >&2; exit 2 ;;
  esac
done
ROOT="${ROOT%/}"

if [ "$(id -u)" -eq 0 ]; then _sudo=""
elif command -v sudo > /dev/null 2>&1 && sudo -n true > /dev/null 2>&1; then _sudo=sudo
else _sudo=""; fi
SUDO="${SUDO-$_sudo}"
AS="$(mavergreen_prefix shipyard)"
MG="$ROOT${AS%/*}"
writable() {
  _a="$1"
  while [ ! -e "$_a" ]; do _a="${_a%/*}"; [ -n "$_a" ] || _a=/; done
  [ -d "$_a" ] && [ -w "$_a" ]
}
if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ] && ! writable "$MG"; then
  MG="${MAVERGREEN_USER_PREFIX:-$HOME/.local/mavergreen}"
  MG="${MG%/}"; AS="$MG/shipyard"
  echo "install-shipyard-prefix: no root, sudo or writable $ROOT${AS%/*}, so shipyard goes to $AS" >&2
fi
P="$MG/shipyard"

T="$(mktemp -d "${TMPDIR:-/tmp}/install-shipyard.XXXXXX")"
stg=""; lk=""
trap 'rm -rf "$T" ${stg:+"$stg"}; [ -z "$lk" ] || shipyard_lock_release "$lk"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
set -- --stage "$T/s" --build "$T/b" --prefix "$AS"
[ -z "$V" ] || set -- "$@" --version "$V"
sp="$(sh "$SELF/stage-shipyard-prefix.sh" "$@")" || die "could not stage shipyard from ${SELF%/*}"
if [ -z "$V" ]; then
  V="$(sed -n 's/^set(PACKAGE_VERSION "\([^"]*\)")$/\1/p' "$sp/share/cmake/MavergreenShipyard/MavergreenShipyardConfigVersion.cmake")"
  [ -n "$V" ] || die "the staged MavergreenShipyardConfigVersion.cmake names no version"
fi
sh "$SELF/package-pkg.sh" --shipyard-prefix "$sp" --version "$V" --tree-only "$T/tree" --installed-as "$AS" \
  || die "package-pkg.sh --tree-only refused the staged prefix"

wd="$MG/.install-products/shipyard"
if ! { mkdir -p "$wd" 2> /dev/null && [ -w "$wd" ]; }; then
  [ -n "$SUDO" ] || die "cannot make $wd: it needs root, sudo, or a writable $MG"
  $SUDO mkdir -p "$wd" && $SUDO chown "$(id -u):$(id -g)" "$wd" || die "cannot make $wd, owned by $(id -u):$(id -g)"
fi
ps=""
if [ ! -w "$MG" ] || { [ -d "$P" ] && [ ! -w "$P" ]; }; then
  [ -n "$SUDO" ] || die "cannot replace $P: it needs root, sudo, or a writable $MG"
  ps=$SUDO
fi
shipyard_lock_take "$wd/lock" "${SHIPYARD_LOCK_WAIT:-900}" || die "$wd/lock is still held after ${shipyard_lock_waited}s"
lk="$wd/lock"
stg="$(mktemp -d "$wd/stage.XXXXXX")" || die "cannot stage in $wd"
cp -R "$T/tree" "$stg/tree" || die "cannot copy the staged tree into $stg"
chmod 755 "$stg/tree" || die "cannot open the staged tree to every user"
if [ -e "$P" ] || [ -h "$P" ]; then $ps mv "$P" "$stg/old" || die "cannot move the old $P aside"; fi
if ! $ps mv "$stg/tree" "$P"; then
  [ ! -e "$stg/old" ] || $ps mv "$stg/old" "$P" || :
  die "cannot move the new tree into $P"
fi
rm -rf "$stg" 2> /dev/null || [ -z "$ps" ] || $ps rm -rf "$stg" || :
stg=""

ex="$(awk '/<key>exports-exclude<\/key>/ { on = 1; next }
  on && /<\/array>/ { exit }
  on && /<string>/ { sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print }' "$P/mavergreen.plist")"
fs=""
{ mkdir -p "$MG/bin" 2> /dev/null && [ -w "$MG/bin" ]; } || fs=$SUDO
$fs mkdir -p "$MG/bin" || die "cannot make $MG/bin"
for f in "$P"/bin/*; do
  [ -f "$f" ] || [ -h "$f" ] || continue
  n="${f##*/}"
  ! printf '%s\n' "$ex" | grep -qxF -- "bin/$n" || continue
  $fs rm -f "$MG/bin/$n" && $fs ln -s "../shipyard/bin/$n" "$MG/bin/$n" || die "cannot link $MG/bin/$n"
done
shipyard_lock_release "$lk"; lk=""
echo "install-shipyard-prefix: shipyard $V is at $P; its commands are linked in $MG/bin" >&2
printf '%s\n' "$P"
