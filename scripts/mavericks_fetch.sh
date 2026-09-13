#!/bin/sh
#   usage: mav_fetch_pinned URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          Sourced POSIX-sh helper for the mavericks-* fetch scripts. Provides the
#          download+verify+extract skeleton they all share. SOURCE it, don't execute it; the caller
#          owns the sentinel guard, any post-processing, and the final path echo. Idempotent: the
#          tarball is cached and only downloaded once. Returns non-zero on an HTTP error (curl
#          --fail) or a checksum mismatch, and does NOT extract in either case -- independent of the
#          caller's `set -e` state, since this is a supply-chain integrity boundary.
mav_fetch_pinned() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4; shift 4   # remaining args: tar members
  mkdir -p "$_cache" || return 1
  _tb="$_cache/$_tarball"
  [ -f "$_tb" ] || curl -sL --fail -o "$_tb" "$_url" || { rm -f "$_tb"; return 1; }
  echo "$_sha  $_tb" | shasum -a 256 -c - >&2 || return 1
  tar xf "$_tb" -C "$_cache" "$@"
}
