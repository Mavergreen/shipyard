#!/bin/sh
# platform: host-agnostic
#   usage: shipyard_curl [--quiet|--progress-bar] URL OUT|-
#          shipyard_fetch_pinned URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          shipyard_fetch_verified URL SHA256 CACHE_DIR TARBALL_NAME
#          shipyard_fetch_extract URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          shipyard_fetch_publish CACHE_DIR EXTRACT_DIR
#          Sourced POSIX-sh helpers for the fetch scripts. SOURCE it, don't execute it.
#          shipyard_curl downloads URL to OUT.part and renames it to OUT only when an attempt succeeds;
#          with OUT "-" it prints the body on stdout, once, after the attempt that succeeded. It
#          retries curl exits 6, 7, 18, 28, 35, 52, 55 and 56 and HTTP 429 and 5xx, from scratch,
#          up to SHIPYARD_FETCH_TRIES attempts (default 5), waiting 2, 4, 8, then 16s between them,
#          one stderr line per retry and one when it gives up. Any other failure, a 404 say, is not
#          retried. On failure it returns non-zero (the last curl exit status when an attempt failed)
#          and leaves no OUT.part. The last attempt's HTTP code (000 for file://) is in
#          $shipyard_curl_http, which is empty when no attempt ran. Each attempt fails a transfer
#          slower than 1KB/s for 60s. --quiet drops curl's own error line; --progress-bar shows
#          curl's progress bar. SHIPYARD_FETCH_BACKOFF=0 skips the waits (test-only).
#          shipyard_fetch_verified downloads URL through shipyard_curl to a unique mktemp file,
#          CACHE_DIR/.TARBALL_NAME.XXXXXX, verifies it there against
#          SHA256, and only then renames it to CACHE_DIR/TARBALL_NAME, so concurrent fetches never see a
#          half-written tarball. A TARBALL_NAME already in CACHE_DIR is verified in place and not downloaded.
#          On a failed download or a checksum mismatch it returns non-zero, says which SHA-256 it
#          got, and deletes only the file it checked, so the next run downloads again -- independent of the
#          caller's `set -e` state, since this is a supply-chain integrity boundary. A mismatch is
#          never retried.
#          shipyard_fetch_extract is shipyard_fetch_verified plus an extract into a fresh CACHE_DIR/.mav-extract.XXXXXX;
#          it prints that directory's path, and on failure returns 1 and leaves no directory behind.
#          The caller may post-process the extract before publishing it.
#          shipyard_fetch_publish moves each top-level entry of EXTRACT_DIR to CACHE_DIR/<name> only if that path
#          does not exist yet (a present entry is a concurrent publisher's complete copy), under a
#          `mkdir` lock at CACHE_DIR/.mav-publish.lock, then removes EXTRACT_DIR. It waits for the lock once
#          a second for up to 120 tries, then returns 1 naming the lock. SHIPYARD_FETCH_LOCK_TRIES
#          overrides the 120 (test-only).
#          shipyard_fetch_pinned is extract-then-publish, the skeleton the fetch scripts share: the caller owns
#          the sentinel guard (call it only when the target is absent), any post-processing, and the final
#          path echo. Idempotent: the tarball is cached and only downloaded once. It does NOT extract after
#          a failed verification. A CACHE_DIR entry therefore appears only when complete, so an extract that
#          fails or is interrupted never leaves a partial tree for a caller to trust.
#          A tar member is extracted only as spelled in the archive (GNU tar is strict): pass "./x" for an archive whose members are "./x/...".
shipyard_curl_http=""

_shipyard_curl_to() {
  _sc_n=1; _sc_wait=2
  while :; do
    _sc_rc=0
    shipyard_curl_http="$(curl -fL $_sc_show --connect-timeout 20 --speed-limit 1024 --speed-time 60 \
      -w '%{http_code}' -o "$2.part" "$1")" || _sc_rc=$?
    if [ "$_sc_rc" -eq 0 ]; then
      mv -f "$2.part" "$2" && return 0
      rm -f "$2.part"; return 1
    fi
    rm -f "$2.part"
    case "$_sc_rc" in
      6|7|18|28|35|52|55|56) _sc_why="curl exit $_sc_rc" ;;
      22) case "$shipyard_curl_http" in
            429|5??) _sc_why="HTTP $shipyard_curl_http" ;;
            *) return "$_sc_rc" ;;
          esac ;;
      *) return "$_sc_rc" ;;
    esac
    if [ "$_sc_n" -ge "$_sc_tries" ]; then
      echo "shipyard_curl: $1: $_sc_why; giving up after $_sc_n tries" >&2
      return "$_sc_rc"
    fi
    echo "shipyard_curl: $1: $_sc_why; retry $_sc_n of $_sc_tries in ${_sc_wait}s" >&2
    [ "${SHIPYARD_FETCH_BACKOFF:-}" = 0 ] || sleep "$_sc_wait"
    _sc_n=$((_sc_n + 1))
    [ "$_sc_wait" -ge 16 ] || _sc_wait=$((_sc_wait * 2))
  done
}

shipyard_curl() {
  shipyard_curl_http=
  _sc_show=-sS
  case "${1:-}" in
    --quiet) _sc_show=-s; shift ;;
    --progress-bar) _sc_show=--progress-bar; shift ;;
  esac
  [ "$#" -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] \
    || { echo "usage: shipyard_curl [--quiet|--progress-bar] URL OUT|-" >&2; return 2; }
  _sc_tries="${SHIPYARD_FETCH_TRIES:-5}"
  case "$_sc_tries" in
    ''|*[!0-9]*|0) echo "shipyard_curl: SHIPYARD_FETCH_TRIES must be a positive integer, not '$_sc_tries'" >&2; return 2 ;;
  esac
  if [ "$2" != - ]; then
    _shipyard_curl_to "$1" "$2" || return $?
    return 0
  fi
  _sc_tmp="$(mktemp "${TMPDIR:-/tmp}/shipyard_curl.XXXXXX")" || return 1
  _sc_out=0
  _shipyard_curl_to "$1" "$_sc_tmp" || _sc_out=$?
  [ "$_sc_out" -ne 0 ] || cat "$_sc_tmp" || _sc_out=1
  rm -f "$_sc_tmp" "$_sc_tmp.part"
  return "$_sc_out"
}

shipyard_fetch_verified() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4
  mkdir -p "$_cache" || return 1
  _tb="$_cache/$_tarball"
  _chk="$_tb"
  if [ ! -f "$_tb" ]; then
    # platform: mktemp gives every call its own file, so concurrent downloads (even subshells of one
    #           shell, which share $$) never interleave into one file
    _chk="$(mktemp "$_cache/.$_tarball.XXXXXX")" || return 1
    if [ "${MAVERGREEN_PROGRESS:-}" != 1 ]; then
      shipyard_curl --quiet "$_url" "$_chk" || { rm -f "$_chk"; return 1; }
    elif [ -t 2 ]; then
      shipyard_curl --progress-bar "$_url" "$_chk" || { rm -f "$_chk"; return 1; }
    else
      echo "shipyard_fetch: downloading $_tarball" >&2
      shipyard_curl "$_url" "$_chk" || { rm -f "$_chk"; return 1; }
      echo "shipyard_fetch: downloaded $_tarball" >&2
    fi
  fi
  if [ "${MAVERGREEN_PROGRESS:-}" = 1 ]; then
    _vout="$(printf '%s  %s\n' "$_sha" "$_chk" | shasum -a 256 -c - 2>&1)" && _vok=1 || { _vok=0; printf '%s\n' "$_vout" >&2; }
  else
    echo "$_sha  $_chk" | shasum -a 256 -c - >&2 && _vok=1 || _vok=0
  fi
  [ "$_vok" -eq 1 ] || {
    echo "shipyard_fetch: $_tb ($_url) is sha256 $(shasum -a 256 < "$_chk" | cut -c1-64), not the pinned $_sha" >&2
    rm -f "$_chk"; return 1; }
  [ "${MAVERGREEN_PROGRESS:-}" != 1 ] || echo "shipyard_fetch: verified $_tarball" >&2
  [ "$_chk" = "$_tb" ] || mv -f "$_chk" "$_tb" || { rm -f "$_chk"; return 1; }
}

shipyard_fetch_extract() {
  _url=$1; _sha=$2; _cache=$3; _tarball=$4; shift 4   # remaining args: tar members
  shipyard_fetch_verified "$_url" "$_sha" "$_cache" "$_tarball" || return 1
  _x="$(mktemp -d "$_cache/.mav-extract.XXXXXX")" || return 1
  [ "${MAVERGREEN_PROGRESS:-}" != 1 ] || echo "shipyard_fetch: unpacking $_tarball" >&2
  tar xf "$_cache/$_tarball" -C "$_x" "$@" || { rm -rf "$_x"; return 1; }
  echo "$_x"
}

shipyard_fetch_publish() {
  _cache=$1; _x=$2
  [ -n "$_x" ] && [ -d "$_x" ] || return 1
  _lock="$_cache/.mav-publish.lock"
  for _e in "$_x"/* "$_x"/.[!.]* "$_x"/..?*; do
    [ -e "$_e" ] || [ -h "$_e" ] || continue   # an unmatched glob stays literal
    _d="$_cache/${_e##*/}"
    _try=1
    until mkdir "$_lock" 2>/dev/null; do
      [ "$_try" -lt "${SHIPYARD_FETCH_LOCK_TRIES:-${MAV_FETCH_LOCK_TRIES:-120}}" ] || {
        echo "shipyard_fetch: $_lock held for ${SHIPYARD_FETCH_LOCK_TRIES:-${MAV_FETCH_LOCK_TRIES:-120}}s -- remove it if no fetch is running" >&2
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

shipyard_fetch_pinned() {
  _px="$(shipyard_fetch_extract "$@")" && shipyard_fetch_publish "$3" "$_px"
}

# spec: SKILL.md "shipyard: consume its facilities" -- the mav_* names answer until the family calls shipyard_*
mav_fetch_verified() { shipyard_fetch_verified "$@"; }
mav_fetch_extract() { shipyard_fetch_extract "$@"; }
mav_fetch_publish() { shipyard_fetch_publish "$@"; }
mav_fetch_pinned() { shipyard_fetch_pinned "$@"; }
