#!/bin/sh
# platform: macOS-only -- PlistBuddy reads back and plutil lints the manifest it writes
#   usage: render-manifest.sh --stage ROOT --product P --name N --version V [--group G] [--line L]
#            [--exclude REL]... [--replaces ABS=REL]... [--generated REL]... [--has-updater]
#          Writes ROOT/usr/local/mavergreen/P/mavergreen.plist. Run it LAST: `outside` is read from
#          whatever is staged at that moment.
#          With --has-updater the manifest's appcast is the product's feed, from scripts/product-names; else empty.
# spec: tests/render-manifest-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
PB=/usr/libexec/PlistBuddy
ST=""; P=""; NAME=""; VER=""; G=""; L=""; AC=""; HASUPD=""; EXCL=""; REPL=""; GEN=""
nl='
'
dotty() { case "/$1/" in *"/./"*|*"/../"*) return 0 ;; esac; return 1; }
xesc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
xstring() { printf '  <key>%s</key>\n  <string>%s</string>\n' "$(xesc "$1")" "$(xesc "$2")"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) ST="${2%/}"; shift 2 ;;
    --product) P="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --group) G="$2"; shift 2 ;;
    --line) L="$2"; shift 2 ;;
    --appcast) echo "render-manifest: --appcast is derived from shipyard's scripts/product-names; stop passing it" >&2; exit 2 ;;
    --has-updater) HASUPD=1; shift ;;
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
        usr/local/mavergreen|usr/local/mavergreen/*) echo "render-manifest: --generated may not name anything under usr/local/mavergreen: $2" >&2; exit 2 ;;
      esac
      if dotty "$2"; then echo "render-manifest: --generated has a . or .. component: $2" >&2; exit 2; fi
      GEN="$GEN$2$nl"; shift 2 ;;
    *) echo "render-manifest: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$NAME" ] && [ -n "$VER" ] || { echo "render-manifest: need --stage --product --name --version" >&2; exit 2; }
registry_need render-manifest identifier "$P"; ID="$REG_V"
if [ -n "$HASUPD" ]; then
  registry_need render-manifest feed "$P"; AC="$REG_V"
fi
case "${G:-$P}" in *[!a-z0-9-]*|-*) echo "render-manifest: bad group ${G:-$P}" >&2; exit 2 ;; esac
case "$L" in *[!0-9a-z.-]*) echo "render-manifest: bad line $L" >&2; exit 2 ;; esac
T="$ST/usr/local/mavergreen/$P"; M="$T/mavergreen.plist"
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
  xstring group "${G:-$P}"
  xstring line "$L"
  xstring version "$VER"
  xstring appcast "$AC"
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
  ( cd "$ST" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | grep -v "^usr/local/mavergreen/$P/" \
    | awk '{ n = split($0, c, "/"); out = $0
             for (k = 1; k <= n; k++) if (c[k] ~ /\.(app|kext|prefPane|plugin|bundle|framework)$/) { out = c[1]; for (j = 2; j <= k; j++) out = out "/" c[j]; break }
             print out }' | sort -u \
    | while IFS= read -r o; do printf '    <string>%s</string>\n' "$(xesc "$o")"; done
  printf '  </array>\n</dict>\n</plist>\n'
} > "$M"
plutil -lint "$M" >/dev/null || { echo "render-manifest: $M failed plutil -lint after writing" >&2; exit 1; }
verify() {
  _got="$("$PB" -c "Print :$1" "$M" 2>/dev/null)" || { echo "render-manifest: could not read back :$1 after writing $M" >&2; exit 1; }
  [ "$_got" = "$2" ] || { echo "render-manifest: :$1 did not round-trip through $M" >&2; exit 1; }
}
verify identifier "$ID"
verify name "$NAME"
verify product "$P"
verify group "${G:-$P}"
verify line "$L"
verify version "$VER"
verify appcast "$AC"
