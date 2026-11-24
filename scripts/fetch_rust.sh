#!/bin/sh
# platform: host-agnostic
#   usage: fetch_rust.sh PIN_DIR
#          Prints the prefix of the Mavergreen/rust release PIN_DIR/version names, for this x86_64 host: a
#          prefix holding bin/cargo, bin/rustc and bin/rustdoc, whose rustc targets x86_64-apple-darwin at
#          10.9 with Recaulk. PIN_DIR is a product's components/rust. An installed
#          /usr/local/mavergreen/rust (RUST_INSTALLED replaces the path) whose mavergreen.plist names that
#          release is used as it is. Otherwise, on Linux, the release's rust-VERSION-linux-x86_64.tar.gz,
#          verified against its SHA256SUMS by fetch_product_tar.sh, is unpacked into
#          ${MAVERGREEN_RUST_CACHE:-~/.cache/mavergreen-rust}/VERSION/linux, and on a Mac the release's
#          rust-VERSION.pkg, through fetch_product_pkg.sh, into
#          ${MAVERGREEN_RUST_CACHE:-~/Library/Caches/mavergreen-rust}/VERSION/mac. Neither needs root.
#          RUST_HOST (linux or mac) replaces the host's own answer. Exit 1 on a failed fetch, a non-x86_64
#          host, or a prefix lacking a tool; 2 on a usage error or a malformed pin.
set -eu
S="$(cd "$(dirname "$0")" && pwd)"
die() { echo "fetch_rust: $*" >&2; exit 1; }
[ $# -eq 1 ] && [ -d "$1" ] || { echo "usage: fetch_rust.sh PIN_DIR (a components/rust directory)" >&2; exit 2; }
P="$(cd "$1" && pwd)"
[ -f "$P/version" ] || { echo "fetch_rust: $P has no version file" >&2; exit 2; }
V="$(tr -d ' \t\n' < "$P/version")"
case "$V" in ''|.|..|*[!a-zA-Z0-9._-]*) echo "fetch_rust: $P/version holds '$V', not a release tag" >&2; exit 2 ;; esac
host="${RUST_HOST:-}"
if [ -z "$host" ]; then
  [ "$(uname -m)" = x86_64 ] || die "the 10.9 Rust toolchain runs on x86_64 hosts here, not $(uname -m)"
  case "$(uname -s)" in
    Linux) host=linux ;;
    Darwin) host=mac ;;
    *) die "rust runs on Linux and on a Mac, not on $(uname -s)" ;;
  esac
fi
case "$host" in
  linux) def="$HOME/.cache/mavergreen-rust" ;;
  mac) def="$HOME/Library/Caches/mavergreen-rust" ;;
  *) echo "fetch_rust: RUST_HOST is '$host', not linux or mac" >&2; exit 2 ;;
esac
has_tools() {
  for t in cargo rustc rustdoc; do [ -x "$1/bin/$t" ] || return 1; done
}
inst="${RUST_INSTALLED:-/usr/local/mavergreen/rust}"
have="$(awk '/<key>version<\/key>/ { getline; sub(/.*<string>/, ""); sub(/<\/string>.*/, ""); print; exit }' "$inst/mavergreen.plist" 2>/dev/null || :)"
if [ "$have" = "$V" ] && has_tools "$inst"; then printf '%s\n' "$inst"; exit 0; fi
W="${MAVERGREEN_RUST_CACHE:-$def}/$V"
case "$host" in
  linux)
    d="$W/linux"
    sh "$S/fetch_product_tar.sh" rust "$V" "$d" >/dev/null || die "could not fetch and verify rust-$V-linux-x86_64.tar.gz" ;;
  mac)
    d="$W/mac"
    sh "$S/fetch_product_pkg.sh" --asset "rust-$V.pkg" rust "$V" "$d" >/dev/null || die "could not fetch and verify rust-$V.pkg" ;;
esac
has_tools "$d" || die "$d lacks cargo, rustc or rustdoc"
printf '%s\n' "$d"
