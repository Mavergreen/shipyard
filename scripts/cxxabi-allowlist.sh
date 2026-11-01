#!/bin/sh
# platform: host-agnostic
#   usage: [NM=<nm>] cxxabi-allowlist.sh [ARCHIVE]
#          Prints the C++ runtime machinery names the pinned Recaulk defines, sorted with LC_ALL=C, one per
#          line: the external symbols ARCHIVE defines that match scripts/cxxabi-machinery.txt. With no
#          ARCHIVE it reads lib/librecaulk.a of the Recaulk release scripts/recaulk.pin names, through
#          fetch_product_pkg.sh. NM is the Mach-O symbol reader (default nm; on a host without Apple's,
#          clang22's llvm-nm). Exit 1, printing nothing, when NM is missing, the archive cannot be
#          fetched or read, or it defines no machinery.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
die() { echo "cxxabi-allowlist: $*" >&2; exit 1; }
[ $# -le 1 ] || { echo "usage: cxxabi-allowlist.sh [ARCHIVE]" >&2; exit 2; }
command -v "${NM:-nm}" >/dev/null 2>&1 || die "${NM:-nm} (not found); set NM to a Mach-O nm such as clang22's llvm-nm"
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/cxxabi-allowlist.XXXXXX")"; trap 'rm -rf "$t"' EXIT
if [ $# -eq 1 ]; then
  archive="$1"
else
  version="$(sed -n 's/^RECAULK_VERSION=//p' "$SELF/recaulk.pin")"
  [ -n "$version" ] || die "$SELF/recaulk.pin names no RECAULK_VERSION"
  sh "$SELF/fetch_product_pkg.sh" recaulk "$version" "$t/recaulk" > /dev/null || die "could not fetch recaulk $version"
  archive="$t/recaulk/lib/librecaulk.a"
fi
[ -f "$archive" ] || die "no archive at $archive"
"${NM:-nm}" -gU "$archive" > "$t/nm" 2>"$t/err" || { cat "$t/err" >&2; die "${NM:-nm} could not read $archive"; }
awk 'NF == 3 && $2 != "U" && $2 != "u" { print $3 }' "$t/nm" | grep -E -f "$SELF/cxxabi-machinery.txt" | LC_ALL=C sort -u > "$t/names" || :
[ -s "$t/names" ] || die "$archive defines no C++ runtime machinery"
cat "$t/names"
