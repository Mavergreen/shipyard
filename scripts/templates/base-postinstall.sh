#!/bin/sh
[ -n "${3:-}" ] || { echo "mavergreen-base: no target volume; installing nothing" >&2; exit 1; }
LC_ALL=C; export LC_ALL
. "$SELF/lib/root-chain.sh"
. "$SELF/lib/vercmp.sh"
R="${3%/}"
V="@MAVERGREEN_VERSION@"
M="$R/opt/mavergreen"
B="$M/.base"
S="$B/$V"
H="$M/mavergreen"
U="${MAVERGREEN_CHAIN_UID:-0}"
own() { if [ "$U" = 0 ]; then chown -h 0:0 "$1"; else chown -h "$U" "$1"; fi 2>/dev/null || true; }
put() {
  rm -f "$2.new" && cp "$1" "$2.new" && chmod 755 "$2.new" && own "$2.new" && mv -f "$2.new" "$2"
}
mavergreen_chain_ok "$3/opt/mavergreen" "$3" || exit 1
cur="$(cat "$B/installed-version" 2>/dev/null || true)"
case "$cur" in ''|*[!0-9.]*|.*|*.|*..*) cur="" ;; esac
if [ ! -x "$H/bin/mavergreen" ] || [ ! -x "$H/libexec/mavergreen-vercmp" ] || [ -z "$cur" ] \
  || [ "$(mavergreen_vercmp "$V" "$cur")" = 1 ]; then
  [ -f "$S/mavergreen" ] && [ -f "$S/mavergreen-vercmp" ] || { echo "mavergreen-base: no staged helper at $S" >&2; exit 1; }
  mavergreen_root_dir "$H" && mavergreen_root_dir "$H/bin" && mavergreen_root_dir "$H/libexec" \
    && mavergreen_root_dir "$M/bin" || exit 1
  put "$S/mavergreen" "$H/bin/mavergreen" && put "$S/mavergreen-vercmp" "$H/libexec/mavergreen-vercmp" || exit 1
  rm -f "$M/bin/mavergreen.new" && ln -s ../mavergreen/bin/mavergreen "$M/bin/mavergreen.new" \
    && own "$M/bin/mavergreen.new" && mv -f "$M/bin/mavergreen.new" "$M/bin/mavergreen" || exit 1
  mavergreen_chain_ok "$3/opt/mavergreen/bin/mavergreen" "$3" \
    && mavergreen_chain_ok "$3/opt/mavergreen/mavergreen/libexec/mavergreen-vercmp" "$3" || exit 1
  mkdir -p "$R/etc/paths.d" "$R/etc/manpaths.d"
  cp "$S/paths" "$R/etc/paths.d/mavergreen"
  cp "$S/manpaths" "$R/etc/manpaths.d/mavergreen"
  printf '%s\n' "$V" > "$B/installed-version"
fi
rm -rf "$S"
exit 0
