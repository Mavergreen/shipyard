#!/bin/sh
# platform: macOS-only -- lsbom reads receipt BOMs
#   usage: gen-os-inventory.sh [RECEIPTS_DIR]
#          Prints every path of every com.apple.pkg.*.bom in RECEIPTS_DIR (default /var/db/receipts),
#          relative to /, once each, in C order. Exits 1 when there is no such BOM.
# spec: explain/os-overwrite.md
set -eu
dir="${1:-/var/db/receipts}"
set -- "$dir"/com.apple.pkg.*.bom
[ -f "$1" ] || { echo "gen-os-inventory: no com.apple.pkg.*.bom in $dir" >&2; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/gen-os-inventory.XXXXXX")"; trap 'rm -rf "$w"' EXIT
for b in "$@"; do lsbom -s "$b" >> "$w/paths"; done
sed -e 's|^\./||' -e '/^\.$/d' "$w/paths" | LC_ALL=C sort -u
