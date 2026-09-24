#!/usr/bin/env bats
# platform: host-agnostic
# Unit test for updater/relaunch_decision.h -- the post-relaunch decision factored out of main.m.in so
# the retry logic is testable without a GUI. Compiles a tiny C driver against the header and runs it.

setup() {
  HDR_DIR="$BATS_TEST_DIRNAME/../updater"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/relaunch_decision_test.XXXXXX")"
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

@test "relaunch decision truth table" {
  cat > "$WORK/t.c" <<'EOF'
#include <stdio.h>
#include "relaunch_decision.h"
static int fails = 0;
static void chk(mav_relaunch_action_t got, mav_relaunch_action_t want, const char *name) {
    if (got != want) { fprintf(stderr, "FAIL %s: got %d want %d\n", name, got, want); fails++; }
}
int main(void) {
    /* args: marker_present, marker_fresh, background, pending_version, installed_version */
    chk(mav_relaunch_decide(0,0,0,"a","b"),        MAV_RELAUNCH_NONE,         "no-marker");
    chk(mav_relaunch_decide(1,1,1,"a","b"),        MAV_RELAUNCH_BG_KEEP_EXIT, "bg-fresh");
    chk(mav_relaunch_decide(1,0,1,"a","b"),        MAV_RELAUNCH_STALE_CHECK,  "bg-stale");
    chk(mav_relaunch_decide(1,0,0,"a","b"),        MAV_RELAUNCH_STALE_CHECK,  "fg-stale");
    chk(mav_relaunch_decide(1,1,0,"v18","v18"),    MAV_RELAUNCH_SHOW_UPDATED, "fg-fresh-match");
    chk(mav_relaunch_decide(1,1,0,"v18","v16"),    MAV_RELAUNCH_OFFER_RETRY,  "fg-fresh-mismatch");
    chk(mav_relaunch_decide(1,1,0,"",   "v16"),    MAV_RELAUNCH_SHOW_UPDATED, "fg-fresh-no-target-legacy");
    chk(mav_relaunch_decide(1,1,0,(void*)0,"v16"), MAV_RELAUNCH_SHOW_UPDATED, "fg-fresh-null-target-legacy");
    chk(mav_relaunch_decide(1,1,0,"v18",""),       MAV_RELAUNCH_OFFER_RETRY,  "fg-fresh-installed-unknown");
    chk(mav_relaunch_decide(1,1,0,"v18",(void*)0), MAV_RELAUNCH_OFFER_RETRY,  "fg-fresh-null-installed");
    return fails ? 1 : 0;
}
EOF
  cc -Wall -Wextra -I "$HDR_DIR" -o "$WORK/t" "$WORK/t.c"
  run "$WORK/t"
  [ "$status" -eq 0 ]
}
