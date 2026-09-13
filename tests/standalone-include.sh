#!/bin/sh
set -eu
SC="${SHIPYARD_CMAKE:-$(command -v shipyard-cmake 2>/dev/null || true)}"
[ -n "$SC" ] || { echo "SKIP: no shipyard-cmake (install the shipyard pkg, or set SHIPYARD_CMAKE)"; exit 77; }
# spec: scripts/run-repo-tests.sh -- exit 77 is the family's SKIP idiom, not a failure. Called
#       bare, as the shared runner does when it globs tests/*.sh, there is nothing configured to
#       test; ctest itself always supplies the config dir (see add_test).
[ "$#" -ge 1 ] || { echo "no config dir given (ctest supplies it) -- skipping" >&2; exit 77; }
CFGDIR="${1:?config dir required}"
SRC=$(cd "$(dirname "$0")/standalone-include" && pwd)
WORK="$(mktemp -d -t standalone_include)"
trap 'rm -rf "$WORK"' EXIT
"$SC" -S "$SRC" -B "$WORK" -DMavericksShipyard_DIR="$CFGDIR" >/dev/null
echo "standalone-include: OK"
