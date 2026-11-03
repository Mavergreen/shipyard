#!/bin/sh
# platform: macOS-only -- launches the installed Cocoa updater app; runs in the 10.9 guest (tests/on-target-tests)
#   usage: installed-updater-launch-test.sh
#          The updater the shipyard pkg installed launches check-only and exits 0 (tests/lib/launch-updater.sh).
#          Exits 77 when no shipyard updater is installed.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="/Library/Application Support/Mavergreen/shipyard-updater.app"
[ -d "$app" ] || { echo "SKIP: no installed $app"; exit 77; }
exec sh "$here/lib/launch-updater.sh" "$app"
