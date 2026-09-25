#!/bin/sh
# platform: host-agnostic
#   usage: mav_fetch_pinned URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          Sourced POSIX-sh helper for the mavericks-* fetch scripts. Provides the
#          download+verify+extract skeleton they all share. SOURCE it, don't execute it; the caller
#          owns the sentinel guard, any post-processing, and the final path echo. Idempotent: the
#          tarball is cached and only downloaded once. Returns non-zero on an HTTP error (curl
#          --fail) or a checksum mismatch, and does NOT extract in either case -- independent of the
#          caller's `set -e` state, since this is a supply-chain integrity boundary. A tarball that
#          fails its checksum is deleted, so the next run downloads it again. The extract is atomic:
#          into a temp dir inside CACHE_DIR, then each top-level entry is moved into place, so an
#          extract that fails or is interrupted never leaves a partial tree for a caller to trust.
#          A tar member is extracted only as spelled in the archive (GNU tar is strict): pass "./x" for an archive whose members are "./x/...".
mav_fetch_pinned() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4; shift 4   # remaining args: tar members
  mkdir -p "$_cache" || return 1
  _tb="$_cache/$_tarball"
  [ -f "$_tb" ] || curl -sL --fail -o "$_tb" "$_url" || { rm -f "$_tb"; return 1; }
  echo "$_sha  $_tb" | shasum -a 256 -c - >&2 || { rm -f "$_tb"; return 1; }
  _x="$(mktemp -d "$_cache/.mav-extract.XXXXXX")" || return 1
  tar xf "$_tb" -C "$_x" "$@" || { rm -rf "$_x"; return 1; }
  for _e in "$_x"/* "$_x"/.[!.]* "$_x"/..?*; do
    [ -e "$_e" ] || [ -h "$_e" ] || continue   # an unmatched glob stays literal
    _d="$_cache/${_e##*/}"
    # platform: mv onto an existing directory would move INTO it, so a stale entry (left by an
    #           extract from before this was atomic) is replaced, not merged into.
    { rm -rf "$_d" && mv "$_e" "$_d"; } || { rm -rf "$_x"; return 1; }
  done
  rmdir "$_x"
}
