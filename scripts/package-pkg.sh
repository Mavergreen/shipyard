#!/bin/sh
#   usage: package-pkg.sh --cmake-tree DIR --shipyard-prefix DIR --app APP --version V --out PKG
#          package-pkg.sh --emit-preinstall FILE     (for tests)
#          Packages shipyard as ONE prefix -- /usr/local/mavergreen-shipyard holding shipyard's own
#          CMake (bin/{cmake,ctest,cpack}, share/cmake-X.Y) and shipyard itself
#          (share/cmake/MavericksShipyard) -- plus /usr/local/bin/shipyard-{cmake,ctest,cpack}
#          symlinked into it, and one universal updater. A preinstall clears the product dir first:
#          Installer never deletes a file a newer payload no longer carries, so every CMake bump
#          would otherwise leave the old share/cmake-X.Y behind. The updater is a stopgap until
#          Mavericks Lineup exists.
# spec: 2026-09-11 -- a cmake always searches its own install prefix, and finds that prefix through a
#       symlink, so shipyard-cmake finds shipyard with no registry, no PATH change and no
#       CMAKE_PREFIX_PATH, and MavericksShipyardConfig.cmake refuses every other cmake.
#       /usr/local/bin is on macOS's default PATH (/etc/paths) and the three names are ours alone, so
#       nothing shared is written into.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "On-target/
#       off-target parity" -- shipyard's own .pkg is the worked example: one artifact serves both
#       boxes because developing under Mavericks and developing under modern macOS are equally
#       first-class, and two pkgs would make someone choose, silently wrong when they choose badly.
#       --host-arch x86_64,arm64 is BOTH arches -- without arm64, Installer on Apple Silicon offers
#       Rosetta for a pkg with scripts and runs them translated, the very prompt this pkg exists to
#       avoid.
# spec: tests/shipyard-package-pkg-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
TREE=""; SPREFIX=""; APP=""; VER=""; OUT=""; EMIT_PRE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --cmake-tree) TREE="${2%/}"; shift 2;;
    --shipyard-prefix) SPREFIX="${2%/}"; shift 2;;
    --app) APP="${2%/}"; shift 2;;
    --version) VER="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --emit-preinstall) EMIT_PRE="$2"; shift 2;;
    *) echo "package-pkg: unknown option $1" >&2; exit 2;;
  esac
done

ID="dev.mavergreen.mavericks-shipyard"
PREFIX_DIR="/usr/local/mavergreen-shipyard"
APPDIR="/Library/Application Support/Mavergreen"
APP_NAME="MavericksShipyardUpdater.app"
LABEL="dev.mavergreen.mavericks-shipyard-updatecheck"

# spec: tests/shipyard-package-pkg-test.sh -- a destructive path must not be one empty variable away
#       from "$ROOT" alone, so the preinstall spells it out literally and the test's fixture pins the
#       same path.
emit_preinstall() {  # $1 = destination file
  cat > "$1" <<'PRE'
#!/bin/sh
# Rendered by package-pkg.sh -- do not edit here.
#
# Clear the product dir before Installer lays down the new one. Installer only adds and overwrites; it
# never deletes a file a newer payload no longer carries -- a removed script would keep working here
# while CI fails, and every CMake bump would leave the old share/cmake-X.Y behind. The dir is
# product-owned, so nothing but shipyard lives there. The path is a FIXED constant under the target
# volume, never built from a variable that could be empty; with no target volume ($3 unset, which
# Installer never does) this removes nothing rather than assume "/".
#
# Never fails the install: whatever this cannot remove, the payload still overwrites.
[ -n "${3:-}" ] || { echo "mavericks-shipyard: preinstall got no target volume; removing nothing" >&2; exit 0; }
ROOT="${3%/}"
rm -rf "$ROOT/usr/local/mavergreen-shipyard" \
  || echo "mavericks-shipyard: could not clear $ROOT/usr/local/mavergreen-shipyard; files dropped from this version may linger" >&2

# ONE-TIME MIGRATION off the ModernMavericks identity (flag day 2026-09-22): the prefix was
# /usr/local/mavericks-shipyard. Spelled out in full, like the line above. The old updater and its
# agent are retired by updater/agent-load.in, as for every product.
# DELETABLE once no pre-flag-day install survives.
rm -rf "$ROOT/usr/local/mavericks-shipyard" \
  || echo "mavericks-shipyard: could not remove the pre-rename prefix $ROOT/usr/local/mavericks-shipyard" >&2

# ONE-TIME MIGRATION off the two-updater design (spec 2026-09-11, R-P1-24).
#
# Up to v1.0.151 the pkg carried two updaters and its postinstall deleted the one that did not match
# the box: an Apple Silicon machine was left running MavericksShipyardCrossUpdater.app under
# dev.modernmavericks.mavericks-shipyard-cross-updatecheck. This version ships ONE universal updater
# under the plain name, and Installer never removes a file a newer payload does not carry -- so
# without this, every existing arm64 install would quietly run TWO Sparkle updaters against the same
# appcast, daily, forever. Nobody would see it; both would "work".
#
# Names spelled out in full, as with the rm -rf above: a destructive path must not be one empty
# variable away from "$ROOT" alone. Best-effort throughout -- a box that cannot unload the agent must
# still get the new version.
#
# DELETABLE once no v1.0.151-or-earlier install survives. Nothing else refers to these names.
#
# The unload only happens when installing to the BOOT volume ($3 = "/", so ROOT is ""): launchctl
# talks to the running system, and unloading a job because a file of the same name exists on some
# other disk would be wrong. Installing elsewhere still removes the files; the agent on that volume
# was never loaded from here anyway. Mirrors updater/agent-load.in's load, in reverse: bootstrap is
# 10.11+, and on 10.9 the fallback must run as the console user, because a root postinstall's own
# launchctl talks to root's session and not the Aqua one.
if [ -z "$ROOT" ] && [ -f /Library/LaunchAgents/dev.modernmavericks.mavericks-shipyard-cross-updatecheck.plist ]; then
  mav_uid=$(stat -f %u /dev/console 2>/dev/null || echo 0)
  mav_user=$(stat -f %Su /dev/console 2>/dev/null || echo root)
  if [ "${mav_uid:-0}" -gt 0 ] && [ "$mav_user" != root ]; then
    launchctl bootout gui/"$mav_uid" /Library/LaunchAgents/dev.modernmavericks.mavericks-shipyard-cross-updatecheck.plist 2>/dev/null \
      || sudo -u "$mav_user" launchctl unload -w /Library/LaunchAgents/dev.modernmavericks.mavericks-shipyard-cross-updatecheck.plist 2>/dev/null \
      || true
  fi
fi
rm -f "$ROOT/Library/LaunchAgents/dev.modernmavericks.mavericks-shipyard-cross-updatecheck.plist" \
  || echo "mavericks-shipyard: could not remove the superseded cross-updater LaunchAgent; it would keep checking the same appcast alongside the new updater" >&2
rm -rf "$ROOT/Library/Application Support/ModernMavericks/MavericksShipyardCrossUpdater.app" \
  || echo "mavericks-shipyard: could not remove the superseded MavericksShipyardCrossUpdater.app" >&2
exit 0
PRE
  chmod +x "$1"
}

if [ -n "$EMIT_PRE" ]; then emit_preinstall "$EMIT_PRE"; exit 0; fi

: "${TREE:?package-pkg: --cmake-tree required}"
: "${SPREFIX:?package-pkg: --shipyard-prefix required}"
: "${APP:?package-pkg: --app required}"
: "${VER:?package-pkg: --version required}"
: "${OUT:?package-pkg: --out required}"

[ "$(basename "$APP")" = "$APP_NAME" ] \
  || { echo "package-pkg: --app must be a $APP_NAME (its LaunchAgent runs that name); got $APP" >&2; exit 2; }
[ -d "$APP" ] || { echo "package-pkg: no such app: $APP" >&2; exit 1; }
for f in bin/cmake bin/ctest bin/cpack; do
  [ -x "$TREE/$f" ] || { echo "package-pkg: --cmake-tree has no $f: $TREE" >&2; exit 1; }
done
require_only() {  # $1 = flag  $2 = dir  $3 = allowed top-level names, space-separated
  _flag="$1"; _dir="$2"; _allowed="$3"
  for _e in "$_dir"/* "$_dir"/.*; do
    [ -e "$_e" ] || continue                        # an unmatched glob stays literal
    _b="$(basename "$_e")"
    case "$_b" in
      .|..) continue ;;
      ._*) continue ;;                              # stripped from the stage below, so it never ships
    esac
    _ok=no
    for _a in $_allowed; do
      if [ "$_b" = "$_a" ]; then _ok=yes; fi
    done
    [ "$_ok" = yes ] || {
      echo "package-pkg: $_flag has an unexpected top-level entry: $_b" >&2
      echo "    everything at the root of $_dir is installed into $PREFIX_DIR, and the payload is" >&2
      echo "    specified exactly (spec 2026-09-11 decision 1): $_allowed" >&2
      echo "    move $_dir/$_b elsewhere, or add it to the payload deliberately" >&2
      exit 1
    }
  done
}
# spec: 2026-09-11 decision 1 -- both roots BECOME the product prefix verbatim, so the enumeration of
#       the payload is a gate rather than a description: a stray shipyard-cmake-tree.tar.gz left
#       beside the tree it was made from shipped a copy of the whole payload inside the payload, and
#       nothing complained. `man` is allowed though our build does not produce it -- CMake installs
#       man pages there when Sphinx is present, and a doc-enabled build must not become a packaging
#       failure.
require_only --cmake-tree "$TREE" "bin doc man share"
[ -f "$SPREFIX/share/cmake/MavericksShipyard/MavericksShipyardConfig.cmake" ] \
  || { echo "package-pkg: --shipyard-prefix has no share/cmake/MavericksShipyard: $SPREFIX" >&2; exit 1; }
# spec: CMakeLists.txt -- every install() targets ${CMAKE_INSTALL_DATADIR}/cmake/MavericksShipyard,
#       so `share` is the only thing that may be here; anything else means a build dir, a source tree
#       or a shared prefix was passed by mistake.
require_only --shipyard-prefix "$SPREFIX" "share"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-pkg.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"; SCR="$WORK/scripts"
mkdir -p "$STAGE$PREFIX_DIR" "$STAGE/usr/local/bin" "$SCR" "$WORK/component" "$(dirname "$OUT")"
COPYFILE_DISABLE=1 cp -R "$TREE"/. "$STAGE$PREFIX_DIR/"
COPYFILE_DISABLE=1 cp -R "$SPREFIX"/. "$STAGE$PREFIX_DIR/"
# platform: the link targets are RELATIVE, so they resolve on whatever volume Installer lays them
#           down on.
ln -s ../mavergreen-shipyard/bin/cmake "$STAGE/usr/local/bin/shipyard-cmake"
ln -s ../mavergreen-shipyard/bin/ctest "$STAGE/usr/local/bin/shipyard-ctest"
ln -s ../mavergreen-shipyard/bin/cpack "$STAGE/usr/local/bin/shipyard-cpack"

sh "$SELF/stage_updater.sh" --stage "$STAGE" --app "$APP" --app-dir "$APPDIR" \
  --agent-label "$LABEL" --scripts-out "$SCR"
emit_preinstall "$SCR/preinstall"

# platform: an NFS or otherwise shared stage sprays AppleDouble "._*" sidecars, which would ship as
#           payload.
find "$STAGE" -name '._*' -delete 2>/dev/null || true

# platform: pkgbuild makes a payload holding a .app relocatable and version-checked, so a locally
#           built updater elsewhere on disk would capture it; build_component_pkg.sh does not.
comp="$WORK/component/mavericks-shipyard.pkg"
sh "$SELF/build_component_pkg.sh" --root "$STAGE" --identifier "$ID" --version "$VER" \
  --install-location / --scripts "$SCR" --out "$comp" >&2

sh "$SELF/set_install_floor.sh" \
  --identifier "$ID" \
  --title "Mavericks Shipyard ${VER}" \
  --component "$comp" \
  --out "$OUT" \
  --host-arch x86_64,arm64 \
  --require-scripts >&2

echo "built $OUT" >&2
