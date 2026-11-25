#!/bin/sh
# platform: host-agnostic
#   usage: fetch_clang22.sh PIN_DIR
#          Prints the root of the clang22 release PIN_DIR/version names, for this host: a prefix holding
#          bin/clang, bin/ld64.lld and bin/llvm-{lipo,otool,nm,strings}. PIN_DIR is a product's
#          components/clang22. On x86_64 Linux: the prefix /usr/local/mavergreen/clang22, where
#          install@v1's `products: clang22@VERSION` puts it (CLANG22_INSTALLED replaces the path); when
#          the prefix holds no mavergreen.plist, install-products.sh installs the release there from its
#          linux-x86_64 archive, verified against its SHA256SUMS, keeping its downloads
#          in MAVERGREEN_TAR_CACHE and MAVERGREEN_PKG_CACHE (default ~/.cache/mavergreen-clang22 for
#          both, so a CI cache of that directory skips them). With MAVERGREEN_CLANG22_CACHE set, or
#          when this user is not root, has no working `sudo -n` and cannot write /usr/local/mavergreen,
#          Linux instead unpacks the archive once into
#          ${MAVERGREEN_CLANG22_CACHE:-~/.cache/mavergreen-clang22}/VERSION/linux through
#          fetch_product_tar.sh, saying on stderr in the second case that path parity is not in
#          effect. A prefix whose mavergreen.plist names another release is never replaced: the release
#          goes to that same per-user cache, beside it, saying so on stderr in one line naming both. When install-products.sh cannot install the release at the prefix, for any reason,
#          Linux falls back to that same per-user cache, saying on stderr in one line why, so the archive
#          alone remains clang22 on Linux. On a Mac: the clang22-cross pkg (on Mac OS X 10.9, whose cross pkg does
#          not run there, the native clang22 pkg), through fetch_product_pkg.sh and stevedore, verified
#          against the release's SHA256SUMS; an installed /usr/local/mavergreen/clang22-cross (clang22 on
#          10.9) at that release is used instead, and CLANG22_INSTALLED replaces that path. A Mac fetch
#          is unpacked once into ${MAVERGREEN_CLANG22_CACHE:-~/Library/Caches/mavergreen-clang22}/VERSION
#          and kept, so a CI cache of that directory skips the download. CLANG22_HOST (linux, mac or
#          mac109) replaces the host's own answer. Whatever the path, the printed prefix holds each SDK
#          its bin/clang.cfg and bin/clang++.cfg name as -isysroot <CFGDIR>/../SDKs/NAME: an installed
#          prefix with no SDKs links it to ../sdkNNN/SDKs, the SDK product beside it, as its pkg does; a
#          tree this script unpacked gets fetch_sdk.sh's pin for NAME, through its own bin/setup-sdk
#          when it ships one, else through its SDKs link or a link in SDKs/. Exit 1 on a failed fetch or
#          install, an archive SHA256SUMS does not list, or an SDK the prefix cannot be given, 2 on a
#          usage error or a malformed pin.
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
die() { echo "fetch_clang22: $*" >&2; exit 1; }
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: fetch_clang22.sh PIN_DIR (a components/clang22 directory)" >&2; exit 2; }
P="$(cd "$1" && pwd)"
[ -f "$P/version" ] || { echo "fetch_clang22: $P has no version file" >&2; exit 2; }
V="$(tr -d ' \t\n' < "$P/version")"
case "$V" in ''|.|..|*[!a-zA-Z0-9._-]*) echo "fetch_clang22: $P/version holds '$V', not a release tag" >&2; exit 2 ;; esac
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
sudo_works() {
  if [ "${SUDO+set}" = set ]; then [ -n "$SUDO" ]; return; fi
  command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}
can_make() {
  [ "$(id -u)" -ne 0 ] || return 0
  _a=$1/clang22
  while [ ! -e "$_a" ]; do _a="$(dirname "$_a")"; done
  { [ -d "$_a" ] && [ -w "$_a" ]; } || sudo_works
}
. "$S/sdk-pins.sh"
wire_sdk() {
  _ws=""
  for _wa in x86_64 arm64; do
    _wp="$(shipyard_sdk_pin "$_wa")" || continue
    [ "${_wp##* }" != "$2" ] || { _ws=$_wa; break; }
  done
  [ -n "$_ws" ] || die "$1/bin/clang.cfg names SDKs/$2, which no pin in sdk-pins.sh provides"
  _wv="${2#MacOSX}"; _wv="${_wv%.sdk}"; _wprod="sdk$(printf '%s' "$_wv" | tr -d .)"
  case "$1" in
    "$W"/*) : ;;
    *)
      [ -d "$1/../$_wprod/SDKs/$2" ] \
        || die "$1 has no SDKs/$2, which its clang.cfg names, and no $_wprod product beside it holds one: install $_wprod (install-products.sh $_wprod@TAG)"
      if [ ! -e "$1/SDKs" ] && [ ! -L "$1/SDKs" ]; then
        ln -s "../$_wprod/SDKs" "$1/SDKs" 2>/dev/null \
          || die "$1 has no SDKs/$2, which its clang.cfg names, and cannot be written to link SDKs to ../$_wprod/SDKs"
      fi
      [ -d "$1/SDKs/$2" ] \
        || die "$1 has an SDKs that is not ../$_wprod/SDKs and holds no $2, which its clang.cfg names: reinstall clang22"
      return 0 ;;
  esac
  _wsdk="$(MAVERICKS_SDK_SETTINGS_JSON='' sh "$S/fetch_sdk.sh" --arch "$_ws")" || die "fetch_sdk.sh --arch $_ws could not provide $2 for $1"
  if [ -L "$1/SDKs" ]; then
    _wt="$(readlink "$1/SDKs")"
    case "$_wt" in /*) : ;; *) _wt="$1/$_wt" ;; esac
  else
    _wt="$1/SDKs"
  fi
  if [ -L "$_wt/$2" ] && [ ! -d "$_wt/$2" ]; then rm -f "$_wt/$2" || :; fi
  if [ ! -L "$1/SDKs" ] && [ "$2" = MacOSX10.9.sdk ] && [ -x "$1/bin/setup-sdk" ]; then
    "$1/bin/setup-sdk" "$_wsdk" > /dev/null || :
  else
    { mkdir -p "$_wt" && ln -s "$_wsdk" "$_wt/$2"; } 2>/dev/null || :
  fi
  [ -d "$1/SDKs/$2" ] || die "$1 has no SDKs/$2, which its clang.cfg names, and $_wsdk could not be wired there"
}
hand_back() {
  for _n in $(cat "$1/bin/clang.cfg" "$1/bin/clang++.cfg" 2>/dev/null \
    | awk '$1 == "-isysroot" && index($2, "<CFGDIR>/../SDKs/") == 1 { print substr($2, 18) }' | LC_ALL=C sort -u); do
    case "$_n" in ''|.|..|*/*) die "$1/bin/clang.cfg names SDKs/$_n, not an SDK directory" ;; esac
    [ -d "$1/SDKs/$_n" ] || wire_sdk "$1" "$_n"
  done
  printf '%s\n' "$1"; exit 0
}
from_pkg() {
  inst="${CLANG22_INSTALLED:-/usr/local/mavergreen/$1}"
  if has_tools "$inst" && [ "$(manifest_version "$inst")" = "$V" ]; then
    hand_back "$inst"
  fi
  d="$W/$1"
  sh "$S/fetch_product_pkg.sh" --asset "$2" "$1" "$V" "$d" >/dev/null || die "could not fetch and verify $2"
}
case "$host" in
  linux)
    asset="clang22-$V-linux-x86_64.tar.gz"
    inst="${CLANG22_INSTALLED:-/usr/local/mavergreen/clang22}"
    have="$(manifest_version "$inst" || :)"
    if has_tools "$inst" && [ "$have" = "$V" ]; then
      hand_back "$inst"
    fi
    if [ -n "$have" ] && [ "$have" != "$V" ] && [ -z "${MAVERGREEN_CLANG22_CACHE:-}" ]; then
      echo "fetch_clang22: $inst holds clang22 $have, not $V, and is left alone, so clang22 $V goes beside it to $W/linux" >&2
      MAVERGREEN_CLANG22_CACHE="${W%/*}"
    fi
    case "$inst" in
      */usr/local/mavergreen/clang22) : ;;
      *) [ -n "${MAVERGREEN_CLANG22_CACHE:-}" ] \
           || die "$inst does not end in usr/local/mavergreen/clang22, so install-products.sh cannot install clang22 $V there" ;;
    esac
    root="${inst%/usr/local/mavergreen/clang22}"
    if [ -z "${MAVERGREEN_CLANG22_CACHE:-}" ] && ! can_make "${inst%/clang22}"; then
      echo "fetch_clang22: no root, sudo or writable ${inst%/clang22}, so clang22 $V goes to $W/linux, without path parity with $inst" >&2
      MAVERGREEN_CLANG22_CACHE="${W%/*}"
    fi
    if [ -z "${MAVERGREEN_CLANG22_CACHE:-}" ]; then
      ipe="$(mktemp "${TMPDIR:-/tmp}/fetch_clang22.XXXXXX")" || die "cannot make a temporary file"
      if INSTALL_PRODUCTS_HOST=linux MAVERGREEN_TAR_CACHE="${MAVERGREEN_TAR_CACHE:-$HOME/.cache/mavergreen-clang22}" \
        MAVERGREEN_PKG_CACHE="${MAVERGREEN_PKG_CACHE:-$HOME/.cache/mavergreen-clang22}" \
        sh "$S/install-products.sh" --root "${root:-/}" "clang22@$V" 2> "$ipe"; then
        cat "$ipe" >&2; rm -f "$ipe"
        d=$inst
      else
        why="$(grep '^install-products: ' "$ipe" | tail -n 1)"
        [ -n "$why" ] || why="$(grep . "$ipe" | tail -n 1)"
        grep -v '^install-products: ' "$ipe" >&2 || :
        rm -f "$ipe"
        echo "fetch_clang22: could not install clang22 $V at $inst (${why:-install-products.sh failed}), so clang22 $V goes to $W/linux, without path parity with $inst" >&2
        MAVERGREEN_CLANG22_CACHE="${W%/*}"
      fi
    fi
    if [ -n "${MAVERGREEN_CLANG22_CACHE:-}" ]; then
      d="$W/linux"
      sh "$S/fetch_product_tar.sh" clang22 "$V" "$d" >/dev/null || die "could not fetch and verify $asset"
    fi ;;
  mac109) from_pkg clang22 "mavericks-clang-22-native-$V.pkg" ;;
  mac) from_pkg clang22-cross "mavericks-clang-22-cross-$V.pkg" ;;
esac
has_tools "$d" || die "$d lacks clang, ld64.lld or one of llvm-{lipo,otool,nm,strings}"
hand_back "$d"
