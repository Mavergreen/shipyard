#!/bin/sh
# platform: host-agnostic
#   usage: shipyard_curl [--quiet|--progress-bar] URL OUT|-
#          shipyard_latest_tag REPO
#          shipyard_fetch_pinned URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          shipyard_release_sha RELEASE_URL ASSET
#          shipyard_fetch_verified URL SHA256 CACHE_DIR TARBALL_NAME
#          shipyard_fetch_extract URL SHA256 CACHE_DIR TARBALL_NAME [tar-member...]
#          shipyard_fetch_publish CACHE_DIR EXTRACT_DIR
#          shipyard_lock_take LOCK SECONDS
#          shipyard_lock_release LOCK
#          Sourced POSIX-sh helpers for the fetch scripts. SOURCE it, don't execute it.
#          shipyard_curl downloads URL to its own OUT.part.XXXXXX (mktemp, so concurrent fetches of one OUT
#          never share a file) and renames it to OUT only when an attempt succeeds;
#          with OUT "-" it prints the body on stdout, once, after the attempt that succeeded. It
#          retries curl exits 6, 7, 18, 28, 35, 52, 55 and 56 and HTTP 429 and 5xx, from scratch,
#          up to SHIPYARD_FETCH_TRIES attempts (default 5), waiting 2, 4, 8, then 16s between them,
#          one stderr line per retry and one when it gives up. Any other failure, a 404 say, is not
#          retried. On failure it returns non-zero (the last curl exit status when an attempt failed)
#          and leaves no OUT.part.XXXXXX. The last attempt's HTTP code (000 for file://) is in
#          $shipyard_curl_http, which is empty when no attempt ran. Each attempt fails a transfer
#          slower than 1KB/s for 60s. --quiet drops curl's own error line; --progress-bar shows
#          curl's progress bar. SHIPYARD_FETCH_BACKOFF=0 skips the waits (test-only).
#          shipyard_release_sha prints ASSET's SHA-256 from RELEASE_URL/SHA256SUMS, fetched afresh on every call, so
#          a Mavergreen release's own published digest, never one committed beside a pin, is what verifies it. It
#          returns 1, saying why on stderr, when SHA256SUMS cannot be fetched or does not list ASSET exactly once
#          (a "*"-prefixed binary-mode name counts): an asset the file does not cover is never reported verified.
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
#          lock file CACHE_DIR/.mav-publish.lock (shipyard_lock_take), then removes EXTRACT_DIR. It waits for the lock once
#          a second for up to 120 tries, then returns 1 naming the lock. SHIPYARD_FETCH_LOCK_TRIES
#          overrides the 120 (test-only).
#          shipyard_fetch_pinned is extract-then-publish, the skeleton the fetch scripts share: the caller owns
#          the sentinel guard (call it only when the target is absent), any post-processing, and the final
#          path echo. Idempotent: the tarball is cached and only downloaded once. It does NOT extract after
#          a failed verification. A CACHE_DIR entry therefore appears only when complete, so an extract that
#          fails or is interrupted never leaves a partial tree for a caller to trust.
#          A tar member is extracted only as spelled in the archive (GNU tar is strict): pass "./x" for an archive whose members are "./x/...".
#          shipyard_latest_tag prints the tag https://github.com/Mavergreen/REPO/releases/latest redirects to,
#          read from the redirect's Location with no API call. MAVERGREEN_RELEASES replaces https://github.com;
#          a file:// root is read as ROOT/Mavergreen/REPO/releases/latest, one line holding the tag.
#          The https read retries like shipyard_curl (same curl exits, HTTP 429 and 5xx, SHIPYARD_FETCH_TRIES, backoff) and
#          gives up after 60s per attempt. It returns 1 when the tag is empty or cannot be found.
#          shipyard_lock_take holds LOCK, a regular file, once this call creates it; it tries again once a
#          second for up to SECONDS seconds, then returns 1. $shipyard_lock_waited is the seconds it waited.
#          Anything already at LOCK, a directory an older shipyard left say, is held.
#          shipyard_lock_release LOCK removes it. A holder that is killed leaves LOCK behind.
shipyard_curl_http=""

# platform: uutils mkdir (Ubuntu 26.04, where ubuntu-latest can land) let 6 of 200 racers win, so mkdir
#           is no mutex; the shell's own noclobber create is open(O_CREAT|O_EXCL) in dash, bash 3.2 and 5.x.
shipyard_lock_take() {
  shipyard_lock_waited=0
  until (set -C; : > "$1") 2>/dev/null; do
    [ "$shipyard_lock_waited" -lt "$2" ] || return 1
    sleep 1
    shipyard_lock_waited=$((shipyard_lock_waited + 1))
  done
}

shipyard_lock_release() {
  rm -f "$1"
}

_shipyard_curl_to() {
  _sc_n=1; _sc_wait=2
  while :; do
    _sc_rc=0
    _sc_part="$(mktemp "$2.part.XXXXXX")" || return 1
    shipyard_curl_http="$(curl -fL $_sc_show --connect-timeout 20 --speed-limit 1024 --speed-time 60 \
      -w '%{http_code}' -o "$_sc_part" "$1")" || _sc_rc=$?
    if [ "$_sc_rc" -eq 0 ]; then
      mv -f "$_sc_part" "$2" && return 0
      rm -f "$_sc_part"; return 1
    fi
    rm -f "$_sc_part"
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
  rm -f "$_sc_tmp"
  return "$_sc_out"
}

shipyard_release_sha() {
  _rs_t="$(mktemp "${TMPDIR:-/tmp}/shipyard_sums.XXXXXX")" || return 1
  shipyard_curl --quiet "$1/SHA256SUMS" "$_rs_t" || {
    rm -f "$_rs_t"; echo "shipyard_fetch: could not fetch $1/SHA256SUMS" >&2; return 1; }
  _rs_sha="$(awk -v f="$2" '$2 == f || $2 == "*" f { print $1 }' "$_rs_t")"
  rm -f "$_rs_t"
  case "$_rs_sha" in
    *[!0-9a-f]*|'') echo "shipyard_fetch: $2 is not listed (once) in $1/SHA256SUMS" >&2; return 1 ;;
  esac
  [ "${#_rs_sha}" -eq 64 ] || { echo "shipyard_fetch: $2 is not listed (once) in $1/SHA256SUMS" >&2; return 1; }
  printf '%s\n' "$_rs_sha"
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
  # platform: 10.9 and macOS have shasum (perl); a Linux without perl has only coreutils' sha256sum,
  #           whose -c prints the same "FILE: OK"; with neither, say so rather than report a mismatch.
  if command -v shasum >/dev/null 2>&1; then _hash="shasum -a 256"
  elif command -v sha256sum >/dev/null 2>&1; then _hash=sha256sum
  else echo "shipyard_fetch: no SHA-256 tool (shasum or sha256sum) to verify $_tarball" >&2; rm -f "$_chk"; return 1
  fi
  if [ "${MAVERGREEN_PROGRESS:-}" = 1 ]; then
    _vout="$(printf '%s  %s\n' "$_sha" "$_chk" | $_hash -c - 2>&1)" && _vok=1 || { _vok=0; printf '%s\n' "$_vout" >&2; }
  else
    echo "$_sha  $_chk" | $_hash -c - >&2 && _vok=1 || _vok=0
  fi
  [ "$_vok" -eq 1 ] || {
    echo "shipyard_fetch: $_tb ($_url) is sha256 $($_hash < "$_chk" | cut -c1-64), not the pinned $_sha" >&2
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
    shipyard_lock_take "$_lock" "$((${SHIPYARD_FETCH_LOCK_TRIES:-120} - 1))" || {
      echo "shipyard_fetch: $_lock held for ${SHIPYARD_FETCH_LOCK_TRIES:-120}s -- remove it if no fetch is running" >&2
      rm -rf "$_x"; return 1; }
    # platform: mv onto an existing directory moves INTO it. Both callers fetch only when their
    #           target is absent, so a present entry is a concurrent publisher's complete copy: keep it.
    #           The `||` chain keeps a failing mv from tripping the caller's `set -e` while the lock is held.
    _rc=0
    [ -e "$_d" ] || [ -h "$_d" ] || mv "$_e" "$_d" || _rc=1
    shipyard_lock_release "$_lock"
    [ "$_rc" -eq 0 ] || { rm -rf "$_x"; return 1; }
  done
  rm -rf "$_x"
}

shipyard_fetch_pinned() {
  _px="$(shipyard_fetch_extract "$@")" && shipyard_fetch_publish "$3" "$_px"
}

shipyard_latest_tag() {
  _lt_root="${MAVERGREEN_RELEASES:-https://github.com}"
  _lt_url="$_lt_root/Mavergreen/$1/releases/latest"
  case "$_lt_root" in
    file://*) _lt_tag="$(head -n 1 "${_lt_url#file://}" 2>/dev/null)" || _lt_tag="" ;;
    *) _lt_loc=""; _lt_http=""; _lt_n=1; _lt_wait=2
       while :; do
         _lt_rc=0
         _lt_loc="$(curl -sS --connect-timeout 20 --max-time 60 -o /dev/null -w '%{http_code} %{redirect_url}' "$_lt_url")" || _lt_rc=$?
         _lt_http="${_lt_loc%% *}"; _lt_loc="${_lt_loc#* }"
         if [ "$_lt_rc" -eq 0 ]; then
           case "$_lt_http" in 429|5??) _lt_why="HTTP $_lt_http" ;; *) break ;; esac
         else
           case "$_lt_rc" in 6|7|18|28|35|52|55|56) _lt_why="curl exit $_lt_rc" ;; *) break ;; esac
         fi
         _lt_loc=""
         if [ "$_lt_n" -ge "${SHIPYARD_FETCH_TRIES:-5}" ]; then
           echo "shipyard_latest_tag: $_lt_url: $_lt_why; giving up after $_lt_n tries" >&2; break
         fi
         echo "shipyard_latest_tag: $_lt_url: $_lt_why; retry $_lt_n of ${SHIPYARD_FETCH_TRIES:-5} in ${_lt_wait}s" >&2
         [ "${SHIPYARD_FETCH_BACKOFF:-}" = 0 ] || sleep "$_lt_wait"
         _lt_n=$((_lt_n + 1))
         [ "$_lt_wait" -ge 16 ] || _lt_wait=$((_lt_wait * 2))
       done
       _lt_tag="${_lt_loc##*/releases/tag/}"
       [ "$_lt_tag" != "$_lt_loc" ] || _lt_tag="" ;;
  esac
  case "$_lt_tag" in
    ''|*[!A-Za-z0-9._+-]*) echo "shipyard_latest_tag: no latest release tag for $1 at $_lt_url${_lt_http:+ (HTTP $_lt_http)}" >&2; return 1 ;;
  esac
  printf '%s\n' "$_lt_tag"
}
