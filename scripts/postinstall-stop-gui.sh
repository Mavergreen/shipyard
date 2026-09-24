#!/bin/sh
# platform: macOS-only -- sourced by a pkg postinstall, on the Mac it installs to
#   usage: SOURCED by a product's postinstall (never executed). Defines mav_stop_gui_instance
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
# spec: tests/assert_gui_relaunch_safe.bats "helper: sourcing defines mav_stop_gui_instance" -- no
#       `exit` and mav_-prefixed vars, so sourcing this file cannot disturb the caller.
mav_stop_gui_instance() {  # $1 = Contents/MacOS/<exec>   $2 = console uid
    _mav_exec="$1"; _mav_uid="$2"
    [ -n "$_mav_exec" ] || return 0
    case "$_mav_uid" in ''|*[!0-9]*) return 0;; esac   # no numeric console uid -> nothing to stop
    [ "$_mav_uid" -gt 0 ] || return 0
    pkill -TERM -U "$_mav_uid" -f "$_mav_exec" 2>/dev/null || true
    sleep 1
    pkill -KILL -U "$_mav_uid" -f "$_mav_exec" 2>/dev/null || true
}
