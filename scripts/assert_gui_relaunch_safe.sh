#!/bin/sh
# platform: host-agnostic
#   usage: assert_gui_relaunch_safe.sh <postinstall-file> [more...]
#          assert_gui_relaunch_safe.sh        (under shipyard-check --dist: the postinstall of every
#                                              component of every .pkg in the dist)
# platform: presence gate for the "two menu-bar icons after an update" bug: a postinstall that
#           (re)launches a GUI menu-bar app MUST also stop the prior instance, or macOS runs both.
#           This behavior is dynamic -- there is no artifact to inspect like a PackageInfo -- so this
#           lints the postinstall script the pkg actually ships.
#           "Relaunches a GUI menu-bar app" means `open -a` of an app, or a
#           `launchctl asuser ... launchctl load` of a per-user agent (the systray's LaunchAgent) --
#           the shared update-check agent loads via `launchctl bootstrap gui/` or
#           `sudo -u ... launchctl load`, neither of which matches, and a root LaunchDaemon load
#           (`launchctl load` with no asuser) is not a GUI relaunch either. "Stops the prior
#           instance" means a call to shipyard_stop_gui_instance (postinstall-stop-gui.sh), a pkill, or a
#           `launchctl asuser ... unload`.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/lib/pkg-read.sh"
chk_ran gui-relaunch-safe

rule="a postinstall that relaunches a GUI app also stops the old instance"
fix="call shipyard_stop_gui_instance (postinstall-stop-gui.sh) before the relaunch, or pkill / launchctl unload the old one"

lint() {  # $1 = the postinstall file, $2 = the name to report it by
  launches=0
  grep -Eq 'open[[:space:]]+-a' "$1" && launches=1
  # platform: `launchctl[[:space:]]+load` does NOT match `launchctl unload`, so an asuser-unload
  #           line alone won't be read as a launch.
  grep -Eq 'asuser.*launchctl[[:space:]]+load' "$1" && launches=1

  if [ "$launches" -eq 0 ]; then
    echo "assert_gui_relaunch_safe: ok — $2 does not relaunch a GUI app (nothing to guard)"
    return 0
  fi
  if grep -Eq 'shipyard_stop_gui_instance|pkill|launchctl[[:space:]]+unload' "$1"; then
    echo "assert_gui_relaunch_safe: ok — $2 relaunches a GUI app and also stops an old instance (presence, not order: nothing here checks the stop comes first)"
  else
    chk_fail gui-relaunch-safe "$rule" "$2 relaunches a GUI app but never stops the old instance -- an update will leave two menu-bar icons" "$fix"
  fi
}

if [ "$#" -eq 0 ] && [ -n "${SHIPYARD_CHECK_DIST:-}" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gui-relaunch.XXXXXX")"; trap 'af_rm "$tmp"' EXIT
  n=0; seen=0
  for pkg in "$SHIPYARD_CHECK_DIST"/*.pkg; do
    [ -f "$pkg" ] || continue
    n=$((n + 1)); x="$tmp/$n"; mkdir -p "$x"
    rc=0; af_extract "$pkg" "$x" || rc=$?
    if [ "$rc" -ne 0 ]; then
      chk_fail gui-relaunch-safe "$rule" "${pkg##*/} cannot be read, so its postinstall cannot be checked$([ "$rc" -ne 2 ] || echo ' (no bsdtar found)')" \
        "install libarchive-tools or set BSDTAR to bsdtar's path, and make sure the pkg is a readable xar"
      continue
    fi
    for sc in $(find "$x" -name Scripts -type f | sed 's/ /%20/g'); do
      sc="$(printf '%s' "$sc" | sed 's/%20/ /g')"
      mkdir -p "$sc.d"
      if ! af_extract "$sc" "$sc.d"; then
        chk_fail gui-relaunch-safe "$rule" "a Scripts archive of ${pkg##*/} cannot be read, so its postinstall cannot be checked" \
          "rebuild the pkg with pkgbuild --scripts"
        continue
      fi
      comp="${sc#"$x"/}"; comp="${comp%Scripts}"; comp="${comp%/}"
      for pi in "$sc.d"/postinstall; do
        [ -f "$pi" ] || continue
        seen=$((seen + 1))
        lint "$pi" "${pkg##*/}${comp:+:$comp}/postinstall"
      done
    done
  done
  [ "$seen" -gt 0 ] || [ "$chk_status" -ne 0 ] || chk_notrun gui-relaunch-safe "no postinstall in $SHIPYARD_CHECK_DIST"
  exit "$chk_status"
fi

[ "$#" -ge 1 ] || { echo "assert_gui_relaunch_safe: need at least one postinstall file" >&2; exit 2; }
for f in "$@"; do
  [ -f "$f" ] || { chk_fail gui-relaunch-safe "$rule" "no such file: $f" "pass the postinstall the pkg ships"; continue; }
  lint "$f" "${f##*/}"
done
exit "$chk_status"
