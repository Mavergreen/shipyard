#!/bin/sh
# platform: host-agnostic
#   usage: [NM=<nm>] [LIPO=<lipo>] [OTOOL=<otool>] cxxabi-allowlist.sh [ARCHIVE]
#          Prints the C++ runtime machinery the pinned Recaulk defines, one "<name> <visible|hidden>" per
#          line, sorted with LC_ALL=C: each symbol ARCHIVE defines that matches scripts/cxxabi-machinery.txt,
#          read by macho-cxxabi.sh, visible when any member exports it. With no ARCHIVE it reads
#          lib/librecaulk.a of the Recaulk release scripts/recaulk.pin names, through fetch_product_pkg.sh and
#          shipyard's own registry, whatever $MAVERGREEN_PRODUCT_NAMES says. NM is the Mach-O symbol reader
#          (default nm; on a host without Apple's, clang22's llvm-nm). Exit 1, printing nothing, when NM is
#          missing, the archive cannot be fetched or read, or it defines no machinery.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib/mach-nm.sh"; NM="$(shipyard_mach_nm)"; export NM
die() { echo "cxxabi-allowlist: $*" >&2; exit 1; }
[ $# -le 1 ] || { echo "usage: cxxabi-allowlist.sh [ARCHIVE]" >&2; exit 2; }
command -v "$NM" >/dev/null 2>&1 || die "$NM (not found); set NM to a Mach-O nm such as clang22's llvm-nm"
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/cxxabi-allowlist.XXXXXX")"; trap 'rm -rf "$t"' EXIT
if [ $# -eq 1 ]; then
  archive="$1"
else
  version="$(sed -n 's/^RECAULK_VERSION=//p' "$SELF/recaulk.pin")"
  [ -n "$version" ] || die "$SELF/recaulk.pin names no RECAULK_VERSION"
  MAVERGREEN_PRODUCT_NAMES="$SELF/product-names" sh "$SELF/fetch_product_pkg.sh" recaulk "$version" "$t/recaulk" > /dev/null || die "could not fetch recaulk $version"
  archive="$t/recaulk/lib/librecaulk.a"
fi
[ -f "$archive" ] || die "no archive at $archive"
sh "$SELF/macho-cxxabi.sh" "$archive" > "$t/cx" 2>"$t/err" \
  || { cat "$t/err" >&2; why="$(sed -n 's/^macho-cxxabi: //p' "$t/err" | head -1)"; die "${why:-$archive is not Mach-O}"; }
awk '$2 == "defines" { if (v[$3] != "visible") v[$3] = $4 } END { for (n in v) print n, v[n] }' "$t/cx" | LC_ALL=C sort > "$t/names"
[ -s "$t/names" ] || die "$archive defines no C++ runtime machinery"
cat "$t/names"
