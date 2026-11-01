#!/bin/sh
# platform: macOS-only -- launches the Cocoa updater app
#   usage: launch-updater.sh TAR
#          Unpacks shipyard-updater.app from TAR (tests/updater-linux-test.sh's UPDATER_TEST_OUT tarball)
#          and launches it in check-only mode (--background: a silent probe of its feed, no UI, no
#          install), giving it 180 seconds to exit by itself. Exit 0 when it started, logged its check and
#          exited 0; 1 otherwise, printing its output. Runs on Mac OS X 10.9 without the Command Line Tools.
set -eu
[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: launch-updater.sh TAR" >&2; exit 2; }
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/launch-updater.XXXXXX")"; trap 'rm -rf "$t"' EXIT
tar -xf "$1" -C "$t"
exe="$t/shipyard-updater.app/Contents/MacOS/shipyard-updater"
[ -x "$exe" ] || { echo "FAIL: $1 holds no shipyard-updater.app/Contents/MacOS/shipyard-updater"; exit 1; }
"$exe" --background > "$t/log" 2>&1 &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$waited" -ge 180 ]; then
    kill "$pid" 2>/dev/null || :
    cat "$t/log"; echo "FAIL: the updater was still running after ${waited}s of a check-only launch"; exit 1
  fi
  sleep 1; waited=$((waited + 1))
done
rc=0; wait "$pid" || rc=$?
cat "$t/log"
[ "$rc" -eq 0 ] || { echo "FAIL: the check-only launch exited $rc"; exit 1; }
grep -q 'start: mode=background' "$t/log" || { echo 'FAIL: the updater never logged its start, so it did not run its own code'; exit 1; }
grep -q -E 'silent probe|auto-check disabled' "$t/log" || { echo 'FAIL: the updater started but never reached its check'; exit 1; }
echo "PASS: the updater launched check-only and exited 0 after ${waited}s"
