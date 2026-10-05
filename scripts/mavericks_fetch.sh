#!/bin/sh
# platform: host-agnostic
#   usage: mav_fetch_pinned URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          mav_fetch_verified URL SHA256 CACHE_DIR TARBALL_NAME
#          Sourced POSIX-sh helpers for the mavericks-* fetch scripts. SOURCE it, don't execute it.
#          mav_fetch_verified downloads URL to CACHE_DIR/TARBALL_NAME unless it is already there, and
#          verifies it against SHA256: on an HTTP error (curl --fail) or a checksum mismatch it returns
#          non-zero, says which SHA-256 it got, and deletes the tarball, so the next run downloads it
#          again -- independent of the caller's `set -e` state, since this is a supply-chain integrity
#          boundary. mav_fetch_pinned is that plus the extract skeleton the fetch scripts share: the
#          caller owns the sentinel guard, any post-processing, and the final path echo. Idempotent: the
#          tarball is cached and only downloaded once. It does NOT extract after a failed verification.
#          The extract is atomic: into a temp dir inside CACHE_DIR, then each top-level entry is moved
#          into place, so an extract that fails or is interrupted never leaves a partial tree for a
#          caller to trust.
#          A tar member is extracted only as spelled in the archive (GNU tar is strict): pass "./x" for an archive whose members are "./x/...".
mav_fetch_verified() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4
  mkdir -p "$_cache" || return 1
  _tb="$_cache/$_tarball"
  [ -f "$_tb" ] || curl -sL --fail -o "$_tb" "$_url" || { rm -f "$_tb"; return 1; }
  echo "$_sha  $_tb" | shasum -a 256 -c - >&2 || {
    echo "mav_fetch: $_tb ($_url) is sha256 $(shasum -a 256 < "$_tb" | cut -c1-64), not the pinned $_sha" >&2
    rm -f "$_tb"; return 1; }
}

mav_fetch_pinned() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4; shift 4   # remaining args: tar members
  mav_fetch_verified "$_url" "$_sha" "$_cache" "$_tarball" || return 1
  _tb="$_cache/$_tarball"
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
