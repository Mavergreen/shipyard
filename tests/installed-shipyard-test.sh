#!/bin/sh
# platform: macOS-only -- reads the cmake product's slices with lipo, which 10.9 has only with the Command Line Tools; run by hand on Golden Gate (tests/maintainer-tests)
#   usage: installed-shipyard-test.sh
#          The shipyard installed at / passes scripts/assert-installed-shipyard.sh, slices included, against
#          the cmake product this checkout pins. Exits 77 when no shipyard is installed.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
sy="$(. "$root/scripts/mavergreen-meta.sh" && . "$root/scripts/lib/name-rules.sh" && mavergreen_prefix shipyard)"
[ -d "$sy" ] || { echo "SKIP: no shipyard installed at $sy"; exit 77; }
exec sh "$root/scripts/assert-installed-shipyard.sh" --cmake-version "$(. "$root/scripts/mavergreen-meta.sh" && MAVERGREEN_REPO_ROOT="$root" mg_value ingredients/cmake/VERSION | sed 's/-mavergreen\..*//')" --root /
