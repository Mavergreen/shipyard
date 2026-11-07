#!/bin/sh
# platform: host-agnostic
set -eu
SC="${CMAKE:-$(command -v shipyard-cmake || echo cmake)}"
command -v "$SC" >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
CFGDIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SRC=$(cd "$(dirname "$0")/standalone-include" && pwd)
WORK="$(mktemp -d "${TMPDIR:-/tmp}/standalone_include.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
"$SC" -S "$SRC" -B "$WORK" -DMavergreenShipyard_DIR="$CFGDIR" >/dev/null
echo "standalone-include: OK"
