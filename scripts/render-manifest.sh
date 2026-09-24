#!/bin/sh
#   usage: render-manifest.sh --stage ROOT --product P --name N --version V [--group G] [--line L]
#            [--appcast URL] [--exclude REL]... [--replaces ABS=REL]...
#          Writes ROOT/usr/local/mavergreen/P/mavergreen.plist. Run it LAST: `outside` is read from
#          whatever is staged at that moment.
# spec: tests/render-manifest-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
PB=/usr/libexec/PlistBuddy
ST=""; P=""; NAME=""; VER=""; G=""; L=""; AC=""; EXCL=""; REPL=""
nl='
'
dotty() { case "/$1/" in *"/./"*|*"/../"*) return 0 ;; esac; return 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) ST="${2%/}"; shift 2 ;;
    --product) P="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --group) G="$2"; shift 2 ;;
    --line) L="$2"; shift 2 ;;
    --appcast) AC="$2"; shift 2 ;;
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
    *) echo "render-manifest: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$NAME" ] && [ -n "$VER" ] || { echo "render-manifest: need --stage --product --name --version" >&2; exit 2; }
ID="$(sh "$SELF/product-name.sh" identifier "$P")" || { echo "render-manifest: $P is not in shipyard's scripts/product-names" >&2; exit 1; }
case "${G:-$P}" in *[!a-z0-9-]*|-*) echo "render-manifest: bad group ${G:-$P}" >&2; exit 2 ;; esac
case "$L" in *[!0-9a-z.-]*) echo "render-manifest: bad line $L" >&2; exit 2 ;; esac
T="$ST/usr/local/mavergreen/$P"; M="$T/mavergreen.plist"
mkdir -p "$T"; rm -f "$M"
"$PB" -c "Add :identifier string $ID" -c "Add :name string $NAME" -c "Add :product string $P" \
      -c "Add :group string ${G:-$P}" -c "Add :line string $L" -c "Add :version string $VER" \
      -c "Add :appcast string $AC" -c "Add :exports-exclude array" -c "Add :replaces dict" \
      -c "Add :outside array" "$M" >/dev/null
i=0; printf '%s' "$EXCL" | while IFS= read -r e; do [ -n "$e" ] || continue; "$PB" -c "Add :exports-exclude:$i string $e" "$M"; i=$((i + 1)); done
printf '%s' "$REPL" | while IFS= read -r r; do [ -n "$r" ] || continue; "$PB" -c "Add :replaces:${r%%=*} string ${r#*=}" "$M"; done
i=0
( cd "$ST" && find . \( -type f -o -type l \) ) | sed 's|^\./||' | grep -v "^usr/local/mavergreen/$P/" \
  | awk '{ n = split($0, c, "/"); out = $0
           for (k = 1; k <= n; k++) if (c[k] ~ /\.(app|kext|prefPane|plugin|bundle|framework)$/) { out = c[1]; for (j = 2; j <= k; j++) out = out "/" c[j]; break }
           print out }' | sort -u \
  | while IFS= read -r o; do "$PB" -c "Add :outside:$i string $o" "$M"; i=$((i + 1)); done
