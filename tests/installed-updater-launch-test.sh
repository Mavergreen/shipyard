#!/bin/sh
# platform: macOS-only -- launches the installed Cocoa updater app; run by hand on the maintainer's 10.9 box (tests/maintainer-tests)
#   usage: installed-updater-launch-test.sh
#          The updater the shipyard pkg installed launches check-only and exits 0 (tests/lib/launch-updater.sh).
#          Runs only with SHIPYARD_ON_TARGET=1, the maintainer's opt-in, so a suite run never launches a
#          developer's own installed updater; exits 77 otherwise, and when no shipyard updater is installed.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
[ "${SHIPYARD_ON_TARGET:-}" = 1 ] || { echo "SKIP: this launches the installed shipyard updater; set SHIPYARD_ON_TARGET=1 to opt in (tests/maintainer-tests)"; exit 77; }
app="/Library/Application Support/Mavergreen/shipyard-updater.app"
[ -d "$app" ] || { echo "SKIP: no installed $app"; exit 77; }
exec sh "$here/lib/launch-updater.sh" "$app"
