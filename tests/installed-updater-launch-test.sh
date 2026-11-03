#!/bin/sh
# platform: macOS-only -- launches the installed Cocoa updater app; runs in the 10.9 guest (tests/on-target-tests)
#   usage: installed-updater-launch-test.sh
#          The updater the shipyard pkg installed launches check-only and exits 0 (tests/lib/launch-updater.sh).
#          Runs only with SHIPYARD_ON_TARGET=1, which pkg-smoke.yml's guest exports, so it never launches a
#          developer's own installed updater; exits 77 otherwise, and when no shipyard updater is installed.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
[ "${SHIPYARD_ON_TARGET:-}" = 1 ] || { echo "SKIP: SHIPYARD_ON_TARGET=1 is unset; this launches the installed updater, so it runs only in pkg-smoke's 10.9 guest"; exit 77; }
app="/Library/Application Support/Mavergreen/shipyard-updater.app"
[ -d "$app" ] || { echo "SKIP: no installed $app"; exit 77; }
exec sh "$here/lib/launch-updater.sh" "$app"
