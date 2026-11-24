#!/bin/sh
# platform: host-agnostic -- GNU tar on Linux, bsdtar on macOS; 10.9's bsdtar 2.8 cannot record root:wheel
#   usage: . det-tar.sh     (sourced; defines det_tar_gz)
#          det_tar_gz WORK TOP OUT EPOCH WHO   archives WORK/TOP as OUT: entries sorted, stamped at EPOCH,
#                                              root:wheel with no Mac metadata where this tar can say so,
#                                              gzipped without a name or time, so one tree gives one
#                                              archive. WHO prefixes the warning a tar that cannot gets.
# spec: scripts/stage_standalone.sh, scripts/split-debug.sh -- the release's tarballs are built one way.

det_tar_gz() {
  _dt_w="$1" _dt_top="$2" _dt_out="$3" _dt_e="$4" _dt_who="$5"
  _dt_stamp="$(date -u -d "@$_dt_e" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "$_dt_e" +%Y%m%d%H%M.%S)"
  (cd "$_dt_w" && find "$_dt_top" -exec env TZ=UTC0 touch -h -t "$_dt_stamp" {} +)
  (cd "$_dt_w" && find "$_dt_top" | LC_ALL=C sort) > "$_dt_w/.det-tar-list"
  mkdir -p "$(dirname "$_dt_out")"
  if tar --version 2>/dev/null | head -1 | grep -q 'GNU tar'; then
    set -- --format=gnu --owner=root:0 --group=wheel:0 --mtime="@$_dt_e"
  else
    set -- --uid 0 --gid 0 --uname root --gname wheel --no-mac-metadata
    if ! (cd "$_dt_w" && COPYFILE_DISABLE=1 tar -c -f /dev/null --no-recursion "$@" "$_dt_top") 2>/dev/null; then
      echo "$_dt_who: this tar ($(tar --version 2>&1 | head -1)) cannot record root:wheel or omit Mac metadata; the archive keeps this machine's owner" >&2
      set --
    fi
  fi
  (cd "$_dt_w" && COPYFILE_DISABLE=1 tar -c -f .det-tar-out.tar --no-recursion "$@" -T .det-tar-list) || return 1
  rm -f "$_dt_w/.det-tar-out.tar.gz"
  gzip -n -9 "$_dt_w/.det-tar-out.tar" || return 1
  mv "$_dt_w/.det-tar-out.tar.gz" "$_dt_out"
  rm -f "$_dt_w/.det-tar-list"
}
