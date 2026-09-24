#!/bin/sh
[ -n "${3:-}" ] || { echo "mavergreen-base: no target volume; installing nothing" >&2; exit 1; }
R="${3%/}"
V="@MAVERGREEN_VERSION@"
S="$R/usr/local/mavergreen/.base/$V"
newer() {
  _a="$1"; _b="$2"
  while [ -n "$_a$_b" ]; do
    _x="${_a%%.*}"; _y="${_b%%.*}"
    [ "${_x:-0}" -gt "${_y:-0}" ] && return 0
    [ "${_x:-0}" -lt "${_y:-0}" ] && return 1
    case "$_a" in *.*) _a="${_a#*.}" ;; *) _a="" ;; esac
    case "$_b" in *.*) _b="${_b#*.}" ;; *) _b="" ;; esac
  done
  return 1
}
cur="$(cat "$R/usr/local/mavergreen/.base/installed-version" 2>/dev/null || true)"
if [ ! -x "$R/usr/local/bin/mavergreen" ] || [ -z "$cur" ] || newer "$V" "$cur"; then
  [ -f "$S/mavergreen" ] || { echo "mavergreen-base: no staged helper at $S" >&2; exit 1; }
  mkdir -p "$R/usr/local/bin" "$R/etc/paths.d" "$R/etc/manpaths.d"
  cp "$S/mavergreen" "$R/usr/local/bin/mavergreen.new" && chmod 755 "$R/usr/local/bin/mavergreen.new" \
    && mv -f "$R/usr/local/bin/mavergreen.new" "$R/usr/local/bin/mavergreen"
  cp "$S/paths" "$R/etc/paths.d/mavergreen"
  cp "$S/manpaths" "$R/etc/manpaths.d/mavergreen"
  printf '%s\n' "$V" > "$R/usr/local/mavergreen/.base/installed-version"
fi
rm -rf "$S"
exit 0
