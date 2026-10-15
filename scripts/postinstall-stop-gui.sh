#!/bin/sh
# platform: macOS-only -- sourced by a pkg postinstall, on the Mac it installs to
#   usage: SOURCED by a product's postinstall (never executed). Defines shipyard_stop_gui_instance
#          Contents/MacOS/<exec> <console-uid>, the stop-the-old-instance step a postinstall that
#          relaunches a GUI menu-bar app must call first (assert_gui_relaunch_safe.sh gates on this).
#          Staged into the pkg's Scripts dir by package-pkg.sh, so it is present when the postinstall
#          runs on the target -- a shared script on the build host is NOT.
# platform: launchd's own unload does not reliably kill a process that ignores SIGTERM, and `open -a`
#           / a fresh agent load then starts the new instance beside the survivor -- an update leaves
#           the OLD instance running beside the NEW one ("two menu-bar icons until I quit the old
#           one").
# platform: `pkill -f` matches a process's own recorded command line, which still reads the OLD
#           Contents/MacOS/<exec> path even after the .app on disk is renamed -- a renamed bundle's
#           already-running instance keeps its original invocation path until it exits.
# spec: tests/assert_gui_relaunch_safe.bats "helper: sourcing defines shipyard_stop_gui_instance" -- no
#       `exit` and _shipyard_-prefixed vars, so sourcing this file cannot disturb the caller.
shipyard_stop_gui_instance() {  # $1 = Contents/MacOS/<exec>   $2 = console uid
    _shipyard_exec="$1"; _shipyard_uid="$2"
    [ -n "$_shipyard_exec" ] || return 0
    case "$_shipyard_uid" in ''|*[!0-9]*) return 0;; esac   # no numeric console uid -> nothing to stop
    [ "$_shipyard_uid" -gt 0 ] || return 0
    pkill -TERM -U "$_shipyard_uid" -f "$_shipyard_exec" 2>/dev/null || true
    sleep 1
    pkill -KILL -U "$_shipyard_uid" -f "$_shipyard_exec" 2>/dev/null || true
}

# spec: SKILL.md "shipyard: consume its facilities" -- the mav_* names answer until the family calls shipyard_*
mav_stop_gui_instance() { shipyard_stop_gui_instance "$@"; }
