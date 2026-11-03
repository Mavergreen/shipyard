#!/bin/sh
# platform: macOS-only -- reads the installed updater's slices with lipo, which 10.9 has only with the Command Line Tools; run by hand on the maintainer's Mac (tests/maintainer-tests)
#   usage: installed-shipyard-test.sh
#          The shipyard installed at / passes scripts/assert-installed-shipyard.sh, slices included, against
#          the cmake product this checkout pins. Exits 77 when no shipyard is installed.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
[ -d /usr/local/mavergreen/shipyard ] || { echo "SKIP: no shipyard installed at /usr/local/mavergreen/shipyard"; exit 77; }
exec sh "$root/scripts/assert-installed-shipyard.sh" --cmake-version "$(sed 's/-mavericks\..*//' "$root/components/cmake/version")" --root /
