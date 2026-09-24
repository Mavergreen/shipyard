#!/usr/bin/env bats
# platform: host-agnostic
# Tests for scripts/assert_gui_relaunch_safe.sh (the "two menu-bar icons after an update" gate) and
# the mav_stop_gui_instance helper it points offenders at. Pure text/process fixtures; no pkg install.

setup() {
  GATE="$BATS_TEST_DIRNAME/../scripts/assert_gui_relaunch_safe.sh"
  HELPER="$BATS_TEST_DIRNAME/../scripts/postinstall-stop-gui.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/gui_relaunch_test.XXXXXX")"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

pi() { printf '%s\n' "$2" > "$WORK/$1"; echo "$WORK/$1"; }

@test "open -a with a stop step (pkill): passes" {
  f="$(pi ok_open 'pkill -TERM -U 501 -f Contents/MacOS/Foo
launchctl asuser 501 open -a "/Applications/Foo.app"')"
  run sh "$GATE" "$f"
  [ "$status" -eq 0 ]
}

@test "asuser launchctl load with mav_stop_gui_instance: passes" {
  f="$(pi ok_helper 'mav_stop_gui_instance Contents/MacOS/Foo 501
launchctl asuser 501 launchctl load -w /Library/LaunchAgents/foo.systray.plist')"
  run sh "$GATE" "$f"
  [ "$status" -eq 0 ]
}

@test "the ok message claims presence, not order, because order is never checked" {
  f="$(pi stop_after 'launchctl asuser 501 open -a "/Applications/Foo.app"
pkill -TERM -U 501 -f Contents/MacOS/Foo')"
  run sh "$GATE" "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'presence, not order'
  [ "${output#*before relaunching}" = "$output" ]
}

@test "open -a with NO stop: rejected" {
  f="$(pi bad_open 'launchctl asuser 501 open -a "/Applications/Foo.app"')"
  run sh "$GATE" "$f"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'two menu-bar icons'
}

@test "asuser load with NO stop: rejected" {
  f="$(pi bad_load 'launchctl asuser 501 launchctl load -w /Library/LaunchAgents/foo.systray.plist')"
  run sh "$GATE" "$f"
  [ "$status" -ne 0 ]
}

@test "update-check agent-load patterns only (bootstrap gui / sudo -u load): not a GUI relaunch, passes" {
  f="$(pi updateronly 'launchctl bootstrap gui/501 /Library/LaunchAgents/x.plist
sudo -u bob launchctl load -w /Library/LaunchAgents/x.plist')"
  run sh "$GATE" "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'does not relaunch a GUI app'
}

@test "root LaunchDaemon load only (no asuser, no open -a): passes trivially" {
  f="$(pi daemon 'launchctl load -w /Library/LaunchDaemons/foo.daemon.plist')"
  run sh "$GATE" "$f"
  [ "$status" -eq 0 ]
}

@test "helper: sourcing defines mav_stop_gui_instance; a no-uid call is a safe no-op" {
  run sh -c ". '$HELPER'; mav_stop_gui_instance Contents/MacOS/Nope 0 && command -v mav_stop_gui_instance"
  [ "$status" -eq 0 ]
}
