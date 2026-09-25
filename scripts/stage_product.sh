#!/bin/sh
# platform: macOS-only -- render-manifest.sh writes the manifest with PlistBuddy and plutil
#   usage: stage_product.sh --stage ROOT --product P --name N --version V --scripts-out DIR
#            [--group G] [--line L] [--appcast URL] [--exclude REL]... [--replaces ABS=REL]...
#            [--updater-app APP --app-dir DIR --agent-label LABEL]
#            [--preinstall-hook FILE] [--postinstall-hook FILE]
#          The one way a product pkg gets its install scripts and manifest. The caller has already
#          staged its files under ROOT/usr/local/mavergreen/P/ (and anything the OS dictates elsewhere).
# spec: tests/stage-product-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ST=""; P=""; SCR=""; APP=""; APPDIR=""; LABEL=""; PREH=""; POSTH=""
set -- "$@" --end
while [ "$1" != --end ]; do
  case "$1" in
    --stage|--product|--scripts-out|--updater-app|--app-dir|--agent-label|--preinstall-hook|--postinstall-hook|--name|--version|--group|--line|--appcast|--exclude|--replaces)
      [ $# -ge 2 ] && [ "$2" != --end ] || { echo "stage_product: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --stage) ST="${2%/}"; set -- "$@" "$1" "$2"; shift 2 ;;
    --product) P="$2"; set -- "$@" "$1" "$2"; shift 2 ;;
    --scripts-out) SCR="$2"; shift 2 ;;
    --updater-app) APP="$2"; shift 2 ;;
    --app-dir) APPDIR="$2"; shift 2 ;;
    --agent-label) LABEL="$2"; shift 2 ;;
    --preinstall-hook) PREH="$2"; shift 2 ;;
    --postinstall-hook) POSTH="$2"; shift 2 ;;
    --name|--version|--group|--line|--appcast|--exclude|--replaces) set -- "$@" "$1" "$2"; shift 2 ;;
    *) echo "stage_product: unknown option $1" >&2; exit 2 ;;
  esac
done
shift
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$SCR" ] || { echo "stage_product: need --stage --product --scripts-out" >&2; exit 2; }
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_product: bad product name '$P'" >&2; exit 2 ;; esac
[ -n "$(find "$ST" \( -type f -o -type l \) 2>/dev/null | head -n 1)" ] || { echo "stage_product: nothing staged under $ST" >&2; exit 1; }
mkdir -p "$ST/usr/local/mavergreen/$P"
mkdir -p "$SCR"
snippet=""
if [ -n "$APP" ]; then
  snippet="$SCR/.agent-load"
  sh "$SELF/stage_updater.sh" --stage "$ST" --app "$APP" --app-dir "$APPDIR" --agent-label "$LABEL" --snippet-out "$snippet"
fi
sh "$SELF/render-manifest.sh" "$@"
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: preinstall got no target volume; removing nothing" >&2; exit 0; }\n' "$P"
  printf 'ROOT="${3%%/}"\n'
  printf 'if [ -x "$ROOT/usr/local/bin/mavergreen" ]; then "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" unlink %s 2>/dev/null || true; fi\n' "$P"
  if [ -n "$PREH" ]; then cat "$PREH"; printf '\n'; fi
  printf 'rm -rf "$ROOT/usr/local/mavergreen/%s" 2>/dev/null || echo "%s: could not clear $ROOT/usr/local/mavergreen/%s; files dropped from this version may linger" >&2\n' "$P" "$P" "$P"
  printf 'exit 0\n'
} > "$SCR/preinstall"
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: postinstall got no target volume" >&2; exit 1; }\n' "$P"
  printf 'ROOT="${3%%/}"\n'
  printf 'MG="$ROOT/usr/local/bin/mavergreen"\n'
  cat <<'HELPERPICK'
if [ ! -x "$MG" ]; then
  _mg_newer() {
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
  MG=""; MGV=""
  for _mg_c in "$ROOT"/usr/local/mavergreen/.base/*/mavergreen; do
    [ -x "$_mg_c" ] || continue
    _mg_v="${_mg_c%/mavergreen}"; _mg_v="${_mg_v##*/}"
    case "$_mg_v" in ''|*[!0-9.]*|.*|*.|*..*) continue ;; esac
    if [ -z "$MG" ] || _mg_newer "$_mg_v" "$MGV"; then MG="$_mg_c"; MGV="$_mg_v"; fi
  done
fi
HELPERPICK
  printf '[ -n "$MG" ] && [ -x "$MG" ] || { echo "%s: no mavergreen helper on this volume" >&2; exit 1; }\n' "$P"
  printf '"$MG" --root "$ROOT/" link %s || exit 1\n' "$P"
  if [ -n "$snippet" ]; then cat "$snippet"; printf '\n'; fi
  if [ -n "$POSTH" ]; then cat "$POSTH"; printf '\n'; fi
  printf 'exit 0\n'
} > "$SCR/postinstall"
rm -f "$SCR/.agent-load"
chmod +x "$SCR/preinstall" "$SCR/postinstall"
