#!/bin/sh
# platform: host-agnostic -- stevedore lints and reads back the manifest it writes
#   usage: render-manifest.sh --stage ROOT --product P --version V
#            [--exclude REL]... [--replaces ABS=REL]... [--generated REL]...
#          Writes ROOT/opt/mavergreen/P/mavergreen.plist. Run it LAST: `outside` is read from
#          whatever is staged at that moment.
#          Everything else is read from .mavergreen/products/P/: group, line, requires/, restart-to-update.
#          Its feed is scripts/updater-identity.sh feed P, empty only when P is built-on-install.
# spec: tests/render-manifest-test.sh
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
ST=""; P=""; NAME=""; VER=""; G=""; L=""; AC=""; EXCL=""; REPL=""; GEN=""
nl='
'
dotty() { case "/$1/" in *"/./"*|*"/../"*) return 0 ;; esac; return 1; }
xesc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
xstring() { printf '  <key>%s</key>\n  <string>%s</string>\n' "$(xesc "$1")" "$(xesc "$2")"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) ST="${2%/}"; shift 2 ;;
    --product) P="$2"; shift 2 ;;
    --name) echo "render-manifest: --name is derived from the product; write .mavergreen/products/<P>/noun" >&2; exit 2 ;;
    --version) VER="$2"; shift 2 ;;
    --group) echo "render-manifest: --group is read from the product; write .mavergreen/products/<P>/group" >&2; exit 2 ;;
    --line) echo "render-manifest: --line is derived from the product; write .mavergreen/products/<P>/line" >&2; exit 2 ;;
    --appcast) echo "render-manifest: --appcast is derived from --product; stop passing it" >&2; exit 2 ;;
    --has-updater) echo "render-manifest: --has-updater is gone: every product has a feed unless .mavergreen/products/<P>/built-on-install exists" >&2; exit 2 ;;
    --exclude) EXCL="$EXCL$2$nl"; shift 2 ;;
    --replaces)
      case "$2" in
        /*=?*) : ;;
        *) echo "render-manifest: --replaces wants /abs/path=tree/path, got $2" >&2; exit 2 ;;
      esac
      _abs="${2%%=*}"; _rel="${2#*=}"
      if dotty "$_abs"; then echo "render-manifest: --replaces key has a . or .. component: $2" >&2; exit 2; fi
      case "$_rel" in /*) echo "render-manifest: --replaces value must not be absolute: $2" >&2; exit 2 ;; esac
      if dotty "$_rel"; then echo "render-manifest: --replaces value has a . or .. component: $2" >&2; exit 2; fi
      REPL="$REPL$2$nl"; shift 2 ;;
    --generated)
      case "$2" in
        ''|/*) echo "render-manifest: --generated wants a /-relative path, got '$2'" >&2; exit 2 ;;
        *"$nl"*) echo "render-manifest: --generated may not contain a newline: $2" >&2; exit 2 ;;
        */|*//*) echo "render-manifest: --generated may not end in / or have an empty segment: $2" >&2; exit 2 ;;
        opt/mavergreen|opt/mavergreen/*) echo "render-manifest: --generated may not name anything under opt/mavergreen: $2" >&2; exit 2 ;;
        Applications/Mavergreen/*) : ;;
        *.app|*.app/*) echo "render-manifest: --generated names an app outside Applications/Mavergreen/: $2" >&2; exit 2 ;;
      esac
      if dotty "$2"; then echo "render-manifest: --generated has a . or .. component: $2" >&2; exit 2; fi
      GEN="$GEN$2$nl"; shift 2 ;;
    *) echo "render-manifest: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$VER" ] || { echo "render-manifest: need --stage --product --version" >&2; exit 2; }
ID="$(mavergreen_name identifier "$P")" || exit $?
NAME="$(mavergreen_name manifest-name "$P")" || exit $?
L="$(mg_value "products/$P/line" 2>/dev/null)" || L=
G="$(mg_value "products/$P/group" 2>/dev/null)" || G=
G="${G:-$P}"
if mg_has "products/$P/built-on-install"; then
  AC=
else
  AC="$(sh "$SELF/updater-identity.sh" feed "$P")" || exit $?
fi
if mg_has "products/$P/restart-to-update"; then RESTART=true; else RESTART=false; fi
case "$G" in *[!a-z0-9-]*|-*) echo "render-manifest: bad group $G" >&2; exit 2 ;; esac
case "$L" in *[!0-9a-z.-]*) echo "render-manifest: bad line $L" >&2; exit 2 ;; esac
PFX="$(mavergreen_prefix "$P")" || exit $?
T="$ST$PFX"; M="$T/mavergreen.plist"
mkdir -p "$T"; rm -f "$M"
{
  cat <<'PLIST_HEADER'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
PLIST_HEADER
  xstring identifier "$ID"
  xstring name "$NAME"
  xstring product "$P"
  xstring group "$G"
  xstring line "$L"
  xstring version "$VER"
  xstring feed "$AC"
  printf '  <key>requires</key>\n  <dict>\n'
  mg_list "products/$P/requires" | while IFS= read -r d; do
    [ -n "$d" ] || continue
    k="$(mg_value "products/$P/requires/$d/kind")" || k=
    printf '    <key>%s</key>\n    <dict>\n' "$(xesc "$d")"
    printf '      <key>kind</key>\n      <string>%s</string>\n' "$(xesc "$k")"
    if m="$(mg_value "products/$P/requires/$d/min")"; then
      printf '      <key>min</key>\n      <string>%s</string>\n' "$(xesc "$m")"
    fi
    printf '    </dict>\n'
  done
  printf '  </dict>\n'
  printf '  <key>restart-to-update</key>\n  <%s/>\n' "$RESTART"
  printf '  <key>exports-exclude</key>\n  <array>\n'
  printf '%s' "$EXCL" | while IFS= read -r e; do [ -n "$e" ] || continue; printf '    <string>%s</string>\n' "$(xesc "$e")"; done
  printf '  </array>\n'
  printf '  <key>replaces</key>\n  <dict>\n'
  printf '%s' "$REPL" | while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '    <key>%s</key>\n    <string>%s</string>\n' "$(xesc "${r%%=*}")" "$(xesc "${r#*=}")"
  done
  printf '  </dict>\n'
  printf '  <key>generated</key>\n  <array>\n'
  printf '%s' "$GEN" | while IFS= read -r g; do [ -n "$g" ] || continue; printf '    <string>%s</string>\n' "$(xesc "$g")"; done
  printf '  </array>\n'
  printf '  <key>outside</key>\n  <array>\n'
  ( cd "$ST" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | grep -v "^${PFX#/}/" \
    | awk '{ n = split($0, c, "/"); out = $0
             for (k = 1; k <= n; k++) if (c[k] ~ /\.(app|kext|prefPane|plugin|bundle|framework|jdk)$/) { out = c[1]; for (j = 2; j <= k; j++) out = out "/" c[j]; break }
             print out }' | sort -u \
    | while IFS= read -r o; do printf '    <string>%s</string>\n' "$(xesc "$o")"; done
  printf '  </array>\n</dict>\n</plist>\n'
} > "$M"
STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"
"$STEVEDORE" plist xml1 "$M" >/dev/null || { echo "render-manifest: $M is not a valid plist after writing" >&2; exit 1; }
verify() {
  _got="$("$STEVEDORE" plist get "$M" "$1" 2>/dev/null)" || { echo "render-manifest: could not read back :$1 after writing $M" >&2; exit 1; }
  [ "$_got" = "$2" ] || { echo "render-manifest: :$1 did not round-trip through $M" >&2; exit 1; }
}
verify identifier "$ID"
verify name "$NAME"
verify product "$P"
verify group "$G"
verify line "$L"
verify version "$VER"
verify feed "$AC"
verify restart-to-update "$RESTART"
mg_list "products/$P/requires" | while IFS= read -r d; do
  [ -n "$d" ] || continue
  verify "requires:$d:kind" "$(mg_value "products/$P/requires/$d/kind")"
  if m="$(mg_value "products/$P/requires/$d/min")"; then verify "requires:$d:min" "$m"; fi
done
