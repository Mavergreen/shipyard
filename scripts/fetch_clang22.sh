#!/bin/sh
# platform: host-agnostic
#   usage: fetch_clang22.sh ROOT
#          Prints the root of the clang22 release ROOT/.mavergreen/ingredients/clang22/VERSION names, for
#          this host: a prefix holding bin/clang, bin/ld64.lld and bin/llvm-{lipo,otool,nm,strings}. ROOT is
#          a product repo. On x86_64 Linux: that release's linux-x86_64 archive, through
#          fetch_product_tar.sh, verified against the digest in the same directory's LINUX_SHA256 (the
#          archive's digest in the release's SHA256SUMS). On a Mac: the clang22-cross pkg (on Mac OS X
#          10.9, whose cross pkg does not run there, the native clang22 pkg), through fetch_product_pkg.sh and stevedore, verified
#          against the release's SHA256SUMS; an installed /usr/local/mavergreen/clang22-cross (clang22 on
#          10.9) at that release is used instead, and CLANG22_INSTALLED replaces that path. A fetch is
#          unpacked once into $MAVERGREEN_CLANG22_CACHE (default ~/Library/Caches/mavergreen-clang22 on a
#          Mac, ~/.cache/mavergreen-clang22 elsewhere)/VERSION and kept, so a CI cache of that directory
#          skips the download. CLANG22_HOST (linux, mac or mac109) replaces the host's own answer. Exit 1
#          on a failed fetch or a missing digest, 2 on a usage error or a malformed pin.
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
die() { echo "fetch_clang22: $*" >&2; exit 1; }
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: fetch_clang22.sh ROOT (a repo holding .mavergreen/ingredients/clang22)" >&2; exit 2; }
. "$S/mavergreen-meta.sh"
MAVERGREEN_ROOT="$(cd "$1" && pwd)"
P="$MAVERGREEN_ROOT/.mavergreen/ingredients/clang22"
V="$(mg_value ingredients/clang22/VERSION)" || { echo "fetch_clang22: $P has no VERSION" >&2; exit 2; }
case "$V" in ''|.|..|*[!a-zA-Z0-9._-]*) echo "fetch_clang22: $P/VERSION holds '$V', not a release tag" >&2; exit 2 ;; esac
host="${CLANG22_HOST:-}"
if [ -z "$host" ]; then
  case "$(uname -s)" in
    Linux)
      [ "$(uname -m)" = x86_64 ] || die "clang22 publishes a Linux archive for x86_64 hosts only, not $(uname -m)"
      host=linux ;;
    Darwin) if [ "$(uname -r | cut -d. -f1)" = 13 ]; then host=mac109; else host=mac; fi ;;
    *) die "clang22 runs on Linux and on a Mac, not on $(uname -s)" ;;
  esac
fi
case "$host" in
  linux) def="$HOME/.cache/mavergreen-clang22" ;;
  mac|mac109) def="$HOME/Library/Caches/mavergreen-clang22" ;;
  *) echo "fetch_clang22: CLANG22_HOST is '$host', not linux, mac or mac109" >&2; exit 2 ;;
esac
W="${MAVERGREEN_CLANG22_CACHE:-$def}/$V"
has_tools() {
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do [ -x "$1/bin/$t" ] || return 1; done
}
manifest_version() {
  awk '/<key>version<\/key>/ { getline; sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print; exit }' "$1/mavergreen.plist" 2>/dev/null
}
from_pkg() {
  inst="${CLANG22_INSTALLED:-/usr/local/mavergreen/$1}"
  if has_tools "$inst" && [ "$(manifest_version "$inst")" = "$V" ]; then
    printf '%s\n' "$inst"; exit 0
  fi
  d="$W/$1"
  sh "$S/fetch_product_pkg.sh" --asset "$2" "$1" "$V" "$d" >/dev/null || die "could not fetch and verify $2"
}
case "$host" in
  linux)
    asset="clang22-$V-linux-x86_64.tar.gz"
    sums="https://github.com/Mavergreen/clang-22/releases/download/$V/SHA256SUMS"
    sha="$(mg_value ingredients/clang22/LINUX_SHA256)" || die "$P has no LINUX_SHA256 for $asset (copy its digest from $sums)"
    case "$sha" in ''|*[!0-9a-f]*) die "$P/LINUX_SHA256 holds '$sha', not the SHA-256 of $asset (copy its digest from $sums)" ;; esac
    [ "${#sha}" -eq 64 ] || die "$P/LINUX_SHA256 holds '$sha', not the SHA-256 of $asset (copy its digest from $sums)"
    d="$W/linux"
    sh "$S/fetch_product_tar.sh" clang22 "$V" "$sha" "$d" >/dev/null || die "could not fetch and verify $asset against $P/LINUX_SHA256 (its digest is in $sums)" ;;
  mac109) from_pkg clang22 "mavericks-clang-22-native-$V.pkg" ;;
  mac) from_pkg clang22-cross "mavericks-clang-22-cross-$V.pkg" ;;
esac
has_tools "$d" || die "$d lacks clang, ld64.lld or one of llvm-{lipo,otool,nm,strings}"
printf '%s\n' "$d"
