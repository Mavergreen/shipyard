#!/bin/sh
# platform: host-agnostic
#   usage: install-shipyard-prefix.sh [--root DIR] [--version V]
#          Lays down shipyard's pkg payload from this checkout, without a pkg, where install@v1 on Linux
#          wants it: DIR$(mavergreen_prefix shipyard) (DIR default /), staged by
#          stage-shipyard-prefix.sh and package-pkg.sh --tree-only, so it is the pkg's prefix and
#          mavergreen.plist, less the updater. Its exported names (bin/ less the manifest's
#          exports-exclude) are linked into the bin/ beside that prefix, as the mavergreen helper
#          links them on a Mac. Prints the installed prefix on stdout.
#          The prefix is root-owned, as the pkg leaves it: every write there runs as root, or under
#          sudo when `sudo -n true` succeeds (SUDO= overrides); with neither it exits 1 before staging.
#          The tree is staged privately, copied as root into .install-products/shipyard beside the
#          prefix, chowned to root and renamed into place whole, an older tree renamed aside first,
#          under that directory's lock, the one install-products.sh takes for shipyard (waiting up to
#          SHIPYARD_LOCK_WAIT seconds, default 900).
#          --version is the version the tree and its manifest carry; without it, CMakeLists.txt's.
#          Exit 1 on a failed stage or install, 2 on a usage error.
# spec: tests/linux-shipyard-prefix-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
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
P="$MG/shipyard"
[ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ] || die "installing into $MG needs root: run it as root, or where sudo -n works"
_cu="${MAVERGREEN_CHAIN_UID:-0}"; if [ "$_cu" = 0 ]; then _co=0:0; else _co=$_cu; fi

T="$(mktemp -d "${TMPDIR:-/tmp}/install-shipyard.XXXXXX")"
stg=""; lk=""
trap 'rm -rf "$T"; [ -z "$stg" ] || $SUDO rm -rf "$stg"; [ -z "$lk" ] || $SUDO rm -f "$lk"' EXIT
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
$SUDO mkdir -p "$wd" || die "cannot make $wd as root"
lw=0
until $SUDO sh -c 'set -C; echo "$1" > "$2"' sh $$ "$wd/lock" 2>/dev/null; do
  hp="$(cat "$wd/lock" 2>/dev/null || :)"
  case "$hp" in
    ''|*[!0-9]*) : ;;
    *) ps -p "$hp" > /dev/null 2>&1 || { [ "$(cat "$wd/lock" 2>/dev/null || :)" != "$hp" ] || $SUDO rm -f "$wd/lock"; continue; } ;;
  esac
  [ "$lw" -lt "${SHIPYARD_LOCK_WAIT:-900}" ] || die "$wd/lock is still held${hp:+ by process $hp} after ${lw}s"
  sleep 1; lw=$((lw + 1))
done
lk="$wd/lock"
stg="$($SUDO mktemp -d "$wd/stage.XXXXXX")" || die "cannot stage in $wd as root"
{ $SUDO cp -pRP "$T/tree" "$stg/tree" && $SUDO chown -R "$_co" "$stg/tree" && $SUDO chmod 755 "$stg/tree"; } \
  || die "cannot stage the tree in $stg, owned by root"
if [ -e "$P" ] || [ -h "$P" ]; then $SUDO mv "$P" "$stg/old" || die "cannot move the old $P aside"; fi
if ! $SUDO mv "$stg/tree" "$P"; then
  [ ! -e "$stg/old" ] || $SUDO mv "$stg/old" "$P" || :
  die "cannot move the new tree into $P"
fi
$SUDO rm -rf "$stg" || :
stg=""

ex="$(awk '/<key>exports-exclude<\/key>/ { on = 1; next }
  on && /<\/array>/ { exit }
  on && /<string>/ { sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print }' "$P/mavergreen.plist")"
fs=$SUDO
$fs mkdir -p "$MG/bin" || die "cannot make $MG/bin"
for f in "$P"/bin/*; do
  [ -f "$f" ] || [ -h "$f" ] || continue
  n="${f##*/}"
  ! printf '%s\n' "$ex" | grep -qxF -- "bin/$n" || continue
  $fs rm -f "$MG/bin/$n" && $fs ln -s "../shipyard/bin/$n" "$MG/bin/$n" || die "cannot link $MG/bin/$n"
done
$SUDO rm -f "$lk"; lk=""
echo "install-shipyard-prefix: shipyard $V is at $P; its commands are linked in $MG/bin" >&2
printf '%s\n' "$P"
