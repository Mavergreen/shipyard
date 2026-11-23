#!/bin/sh
# platform: host-agnostic
#   usage: fetch_clang22.sh ROOT [NAME]
#          Prints the root of the clang22 release ROOT/.mavergreen/ingredients/NAME/VERSION names (NAME
#          defaults to clang22), for this host: a prefix holding bin/clang, bin/ld64.lld and
#          bin/llvm-{lipo,otool,nm,strings}. ROOT is a product repo. It is `shipyard-provision --only NAME`
#          for the host's product: on x86_64
#          Linux the linux-x86_64 archive, verified against the release's SHA256SUMS, fetched afresh on
#          every call; on a Mac the clang22-cross
#          pkg (on Mac OS X 10.9, whose cross pkg does not run there, the native clang22 pkg), verified
#          against the release's SHA256SUMS, or the installed one at that release. A fetch is unpacked once
#          under $MAVERGREEN_CLANG22_CACHE (default ~/Library/Caches/mavergreen-clang22 on a Mac,
#          ~/.cache/mavergreen-clang22 elsewhere) and kept, so a CI cache of that directory skips the
#          download. CLANG22_HOST (linux, mac or mac109) replaces the host's own answer. Exit 1 on a
#          failed fetch or an archive SHA256SUMS does not list, 2 on a usage error or a malformed pin.
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
die() { echo "fetch_clang22: $*" >&2; exit 1; }
{ [ $# -eq 1 ] || [ $# -eq 2 ]; } && [ -d "$1" ] || { echo "usage: fetch_clang22.sh ROOT [NAME] (a repo holding .mavergreen/ingredients/NAME, default clang22)" >&2; exit 2; }
N="${2:-clang22}"
case "$N" in ''|.|..|*[!a-zA-Z0-9._-]*) echo "fetch_clang22: '$N' is not an ingredient name" >&2; exit 2 ;; esac
. "$S/mavergreen-meta.sh"
MAVERGREEN_REPO_ROOT="$(cd "$1" && pwd)"
export MAVERGREEN_REPO_ROOT
P="$MAVERGREEN_REPO_ROOT/.mavergreen/ingredients/$N"
V="$(mg_value "ingredients/$N/VERSION")" || { echo "fetch_clang22: $P has no VERSION" >&2; exit 2; }
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
cache="${MAVERGREEN_CLANG22_CACHE:-$def}"
has_tools() {
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do [ -x "$1/bin/$t" ] || return 1; done
}
provision() {
  _os=$1; shift; _rc=0
  _out="$(CI= SHIPYARD_PROVISION_OS=$_os sh "$S/shipyard-provision" --only "$N" --into "$cache" "$@")" || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    [ "$_os" != Linux ] || [ "$_rc" -ne 1 ] || die "could not fetch and verify clang22-$V-linux-x86_64.tar.gz against its release's SHA256SUMS"
    exit "$_rc"
  fi
  d="${_out#"$N"=}"
}
case "$host" in
  linux) provision Linux ;;
  mac109) provision Darwin --asset "mavericks-clang-22-native-$V.pkg" ;;
  mac) provision Darwin --product clang22-cross --asset "mavericks-clang-22-cross-$V.pkg" ;;
esac
has_tools "$d" || die "$d lacks clang, ld64.lld or one of llvm-{lipo,otool,nm,strings}"
printf '%s\n' "$d"
