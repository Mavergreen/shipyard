#!/bin/sh
# platform: host-agnostic
#   usage: mav_fetch_pinned URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          mav_fetch_verified URL SHA256 CACHE_DIR TARBALL_NAME
#          mav_fetch_extract URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          mav_fetch_publish CACHE_DIR EXTRACT_DIR
#          Sourced POSIX-sh helpers for the mavericks-* fetch scripts. SOURCE it, don't execute it.
#          mav_fetch_verified downloads URL to a unique mktemp file, CACHE_DIR/.TARBALL_NAME.XXXXXX, verifies it there against
#          SHA256, and only then renames it to CACHE_DIR/TARBALL_NAME, so concurrent fetches never see a
#          half-written tarball. A TARBALL_NAME already in CACHE_DIR is verified in place and not downloaded.
#          On an HTTP error (curl --fail) or a checksum mismatch it returns non-zero, says which SHA-256 it
#          got, and deletes only the file it checked, so the next run downloads again -- independent of the
#          caller's `set -e` state, since this is a supply-chain integrity boundary.
#          mav_fetch_extract is mav_fetch_verified plus an extract into a fresh CACHE_DIR/.mav-extract.XXXXXX;
#          it prints that directory's path, and on failure returns 1 and leaves no directory behind.
#          The caller may post-process the extract before publishing it.
#          mav_fetch_publish moves each top-level entry of EXTRACT_DIR to CACHE_DIR/<name> only if that path
#          does not exist yet (a present entry is a concurrent publisher's complete copy), under a
#          `mkdir` lock at CACHE_DIR/.mav-publish.lock, then removes EXTRACT_DIR. It waits for the lock once
#          a second for up to 120 tries, then returns 1 naming the lock. MAV_FETCH_LOCK_TRIES overrides the
#          120 (test-only).
#          mav_fetch_pinned is extract-then-publish, the skeleton the fetch scripts share: the caller owns
#          the sentinel guard (call it only when the target is absent), any post-processing, and the final
#          path echo. Idempotent: the tarball is cached and only downloaded once. It does NOT extract after
#          a failed verification. A CACHE_DIR entry therefore appears only when complete, so an extract that
#          fails or is interrupted never leaves a partial tree for a caller to trust.
#          A tar member is extracted only as spelled in the archive (GNU tar is strict): pass "./x" for an archive whose members are "./x/...".
mav_fetch_verified() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4
  mkdir -p "$_cache" || return 1
  _tb="$_cache/$_tarball"
  _chk="$_tb"
  if [ ! -f "$_tb" ]; then
    # platform: mktemp gives every call its own file, so concurrent downloads (even subshells of one
    #           shell, which share $$) never interleave into one file
    _chk="$(mktemp "$_cache/.$_tarball.XXXXXX")" || return 1
    curl -sL --fail -o "$_chk" "$_url" || { rm -f "$_chk"; return 1; }
  fi
  echo "$_sha  $_chk" | shasum -a 256 -c - >&2 || {
    echo "mav_fetch: $_tb ($_url) is sha256 $(shasum -a 256 < "$_chk" | cut -c1-64), not the pinned $_sha" >&2
    rm -f "$_chk"; return 1; }
  [ "$_chk" = "$_tb" ] || mv -f "$_chk" "$_tb" || { rm -f "$_chk"; return 1; }
}

mav_fetch_extract() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4; shift 4   # remaining args: tar members
  mav_fetch_verified "$_url" "$_sha" "$_cache" "$_tarball" || return 1
  _x="$(mktemp -d "$_cache/.mav-extract.XXXXXX")" || return 1
  tar xf "$_cache/$_tarball" -C "$_x" "$@" || { rm -rf "$_x"; return 1; }
  echo "$_x"
}

mav_fetch_publish() {
  _cache=$1; _x=$2
  [ -n "$_x" ] && [ -d "$_x" ] || return 1
  _lock="$_cache/.mav-publish.lock"
  for _e in "$_x"/* "$_x"/.[!.]* "$_x"/..?*; do
    [ -e "$_e" ] || [ -h "$_e" ] || continue   # an unmatched glob stays literal
    _d="$_cache/${_e##*/}"
    _try=1
    until mkdir "$_lock" 2>/dev/null; do
      [ "$_try" -lt "${MAV_FETCH_LOCK_TRIES:-120}" ] || {
        echo "mav_fetch: $_lock held for ${MAV_FETCH_LOCK_TRIES:-120}s -- remove it if no fetch is running" >&2
        rm -rf "$_x"; return 1; }
      _try=$((_try + 1))
      sleep 1
    done
    # platform: mv onto an existing directory moves INTO it. Both callers fetch only when their
    #           target is absent, so a present entry is a concurrent publisher's complete copy: keep it.
    #           The `||` chain keeps a failing mv from tripping the caller's `set -e` while the lock is held.
    _rc=0
    [ -e "$_d" ] || [ -h "$_d" ] || mv "$_e" "$_d" || _rc=1
    rmdir "$_lock"
    [ "$_rc" -eq 0 ] || { rm -rf "$_x"; return 1; }
  done
  rm -rf "$_x"
}

mav_fetch_pinned() {
  _px="$(mav_fetch_extract "$@")" && mav_fetch_publish "$3" "$_px"
}
