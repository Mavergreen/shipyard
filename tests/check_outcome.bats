#!/usr/bin/env bats
# platform: host-agnostic
# Unit test for updater/check_outcome.h -- pane-hint mode records <PANE_HINT_KEY>CheckedAt only when a
# check completed, and exits non-zero only when it failed -- and for main.m.in's use of it at each
# delegate. Compiles a tiny C driver against the header and runs it.

setup() {
  HDR_DIR="$BATS_TEST_DIRNAME/../updater"
  MAIN="$HDR_DIR/main.m.in"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/check_outcome_test.XXXXXX")"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

probe() {
  cat > "$WORK/t.c" <<EOF2
#include <stdio.h>
#include "check_outcome.h"
int main(void) {
    printf("%d %d\n", mav_check_records_completion($1, $2), mav_check_exit_status($1, $2));
    return 0;
}
EOF2
  cc -Wall -Wextra -I "$HDR_DIR" -o "$WORK/t" "$WORK/t.c"
  run "$WORK/t"
  [ "$status" -eq 0 ]
}

method_body() {
  awk -v sig="$1" 'index($0, sig) == 1 { on = 1 } on && /^- \(/ && index($0, sig) != 1 { exit } on && /^@end/ { exit } on { print }' "$MAIN"
}

@test "a found update records CheckedAt and exits 0" {
  probe 1 MAV_CHECK_FOUND
  [ "$output" = "1 0" ]
  method_body '- (void)updater:(SUUpdater *)updater didFindValidUpdate:' | grep -q 'resolveCheck:MAV_CHECK_FOUND'
}

@test "no update records CheckedAt and exits 0" {
  probe 1 MAV_CHECK_NOT_FOUND
  [ "$output" = "1 0" ]
  method_body '- (void)updaterDidNotFindUpdate:' | grep -q 'resolveCheck:MAV_CHECK_NOT_FOUND'
}

@test "an abort or error records no CheckedAt and exits 1" {
  probe 1 MAV_CHECK_ABORTED
  [ "$output" = "0 1" ]
  method_body '- (void)updater:(SUUpdater *)updater didAbortWithError:' | grep -q 'resolveCheck:MAV_CHECK_ABORTED'
}

@test "a watchdog timeout records no CheckedAt and exits 1" {
  probe 1 MAV_CHECK_TIMED_OUT
  [ "$output" = "0 1" ]
  method_body '- (void)watchdogFired:' | grep -q 'resolveCheck:MAV_CHECK_TIMED_OUT'
}

@test "without PANE_HINT_KEY no outcome records CheckedAt or exits non-zero" {
  for o in MAV_CHECK_FOUND MAV_CHECK_NOT_FOUND MAV_CHECK_ABORTED MAV_CHECK_TIMED_OUT; do
    probe 0 "$o"
    [ "$output" = "0 0" ]
  done
  grep -q 'if (strlen(MAVERICKS_PANE_HINT_KEY) > 0)$' "$MAIN"
  [ "$(grep -c 'NSApplicationWillTerminateNotification' "$MAIN")" -eq 1 ]
}

@test "CheckedAt is written only through resolveCheck, under the hint's key" {
  grep -q 'kCheckedAtKey = @"@MAVERICKS_C_PANE_HINT_KEY@CheckedAt"' "$MAIN"
  [ "$(grep -c 'forKey:kCheckedAtKey' "$MAIN")" -eq 1 ]
  method_body '- (void)resolveCheck:' | grep -q 'forKey:kCheckedAtKey'
  [ "$(grep -c 'resolveCheck:MAV_CHECK_' "$MAIN")" -eq 4 ]
}

main_body() {
  awk '/^int main\(/ { on = 1 } on { print } on && /^}/ { exit }' "$MAIN"
}

@test "only mav_foreground activates, and it makes the app Regular first" {
  [ "$(grep -c 'activateIgnoringOtherApps' "$MAIN")" -eq 1 ]
  awk '/^static void mav_foreground\(void\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$MAIN" > "$WORK/fg"
  [ "$(sed -n 2p "$WORK/fg")" = '    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];' ]
  [ "$(sed -n 3p "$WORK/fg")" = '    [NSApp activateIgnoringOtherApps:YES];' ]
}

@test "the app launches as LSUIElement and only mav_foreground changes its activation policy" {
  awk '/<key>LSUIElement<\/key>/ { getline; print; exit }' "$HDR_DIR/Info.plist.in" > "$WORK/ui"
  [ "$(tr -d '[:space:]' < "$WORK/ui")" = '<true/>' ]
  [ "$(grep -c 'setActivationPolicy:' "$MAIN")" -eq 1 ]
}

@test "the silent probe activates only under gUserInitiated" {
  main_body > "$WORK/main"
  run awk '
    /^        if \(gUserInitiated\) \{$/ { branch = "user"; next }
    branch == "user" && /^        \} else \{$/ { branch = "probe"; next }
    branch == "probe" && /^        \}$/ { branch = "done"; next }
    /mav_foreground\(\)|activateIgnoringOtherApps/ { n[branch ? branch : "before"]++ }
    /\[NSApp run\]/ { ran = 1 }
    END { printf "%d %d %d %s %d\n", n["user"], n["probe"], n["done"], branch, ran }
  ' <(awk '/\[updater setDelegate:gDelegate\];/ { on = 1 } on { print } /\[NSApp run\]/ { exit }' "$WORK/main")
  [ "$output" = "1 0 0 done 1" ]
}

@test "every post-relaunch alert is brought forward by mav_foreground" {
  main_body > "$WORK/main"
  [ "$(grep -c 'runModal\]' "$WORK/main")" -eq 2 ]
  [ "$(grep -B1 'NSAlert \*[a-z]* = \[\[NSAlert alloc\] init\];' "$WORK/main" | grep -c 'mav_foreground();')" -eq 2 ]
}

@test "every --user relaunch goes through LaunchServices as a new instance" {
  [ "$(grep -c 'NSTask launchedTaskWithLaunchPath' "$MAIN")" -eq 0 ]
  [ "$(grep -c 'mav_relaunch_user();' "$MAIN")" -eq 2 ]
  awk '/^static void mav_relaunch_user\(void\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$MAIN" > "$WORK/rl"
  grep -q 'launchApplicationAtURL:\[\[NSBundle mainBundle\] bundleURL\]' "$WORK/rl"
  grep -q 'options:NSWorkspaceLaunchNewInstance' "$WORK/rl"
  grep -q 'NSWorkspaceLaunchConfigurationArguments: @\[@"--user"\]' "$WORK/rl"
}
