#!/bin/sh
# platform: macOS-only -- PlistBuddy reads the updater's identity, and render-manifest.sh reads back and lints the manifest
#   usage: stage_product.sh --stage ROOT --product P --name N --version V --scripts-out DIR
#            [--group G] [--line L] [--exclude REL]... [--replaces ABS=REL]... [--generated REL]...
#            [--updater-app P-updater.app] [--preinstall-hook FILE] [--postinstall-hook FILE]
#          The one way a product pkg gets its install scripts and manifest. The caller has already
#          staged its files under ROOT/usr/local/mavergreen/P/ (and anything the OS dictates elsewhere).
#          The updater's place, label and feed are P's, from scripts/product-names: an updater built
#          for anything else is refused, and so are --appcast, --app-dir and --agent-label.
# spec: tests/stage-product-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
ST=""; P=""; SCR=""; APP=""; PREH=""; POSTH=""
set -- "$@" --end
while [ "$1" != --end ]; do
  case "$1" in
    --stage|--product|--scripts-out|--updater-app|--preinstall-hook|--postinstall-hook|--name|--version|--group|--line|--exclude|--replaces|--generated)
      [ $# -ge 2 ] && [ "$2" != --end ] || { echo "stage_product: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --stage) ST="${2%/}"; set -- "$@" "$1" "$2"; shift 2 ;;
    --product) P="$2"; set -- "$@" "$1" "$2"; shift 2 ;;
    --scripts-out) SCR="$2"; shift 2 ;;
    --updater-app) APP="$2"; shift 2 ;;
    --preinstall-hook) PREH="$2"; shift 2 ;;
    --postinstall-hook) POSTH="$2"; shift 2 ;;
    --name|--version|--group|--line|--exclude|--replaces|--generated) set -- "$@" "$1" "$2"; shift 2 ;;
    --appcast|--app-dir|--agent-label) echo "stage_product: $1 is derived from shipyard's scripts/product-names; stop passing it" >&2; exit 2 ;;
    *) echo "stage_product: unknown option $1" >&2; exit 2 ;;
  esac
done
shift
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$SCR" ] || { echo "stage_product: need --stage --product --scripts-out" >&2; exit 2; }
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_product: bad product name '$P'" >&2; exit 2 ;; esac
[ -n "$(find "$ST" \( -type f -o -type l \) 2>/dev/null | head -n 1)" ] || { echo "stage_product: nothing staged under $ST" >&2; exit 1; }
for h in "$PREH" "$POSTH"; do
  if [ -n "$h" ]; then
    sh -n "$h" || { echo "stage_product: hook $h is not valid sh; refusing to stage" >&2; exit 1; }
  fi
done
mkdir -p "$ST/usr/local/mavergreen/$P"
mkdir -p "$SCR"
snippet=""
if [ -n "$APP" ]; then
  registry_need stage_product updater-bundle-id "$P"; _want_id="$REG_V"
  registry_need stage_product feed "$P"; _want_feed="$REG_V"
  _got_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)" || _got_id=""
  _got_feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" 2>/dev/null)" || _got_feed=""
  [ "$_got_id" = "$_want_id" ] && [ "$_got_feed" = "$_want_feed" ] \
    || { echo "stage_product: $APP was not built for $P: it is '${_got_id:-none}' polling '${_got_feed:-none}', and the registry says $_want_id polling $_want_feed -- build it with mavericks_add_updater_app(PRODUCT $P)" >&2; exit 1; }
  snippet="$SCR/.agent-load"
  sh "$SELF/stage_updater.sh" --stage "$ST" --app "$APP" --product "$P" --snippet-out "$snippet"
  set -- "$@" --has-updater
fi
sh "$SELF/render-manifest.sh" "$@"
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: preinstall got no target volume; removing nothing" >&2; exit 0; }\n' "$P"
  printf 'ROOT="${3%%/}"\n'
  printf 'if [ -x "$ROOT/usr/local/bin/mavergreen" ]; then "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" unlink %s 2>/dev/null || true; fi\n' "$P"
  if [ -n "$PREH" ]; then
    printf '(\n:\n'; cat "$PREH"; printf '\n) || {\n'
    printf '  if [ ! -x "$ROOT/usr/local/bin/mavergreen" ] || "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" link %s >/dev/null 2>&1; then\n' "$P"
    printf '    echo "%s: preinstall hook failed; the installed version is left in place" >&2\n' "$P"
    printf '  else\n'
    printf '    echo "%s: preinstall hook failed" >&2\n' "$P"
    printf '    echo '"'"'%s: could not relink; run `mavergreen link %s`'"'"' >&2\n' "$P" "$P"
    printf '  fi\n'
    printf '  exit 1\n}\n'
  fi
  sed "s/@P@/$P/g" <<'CLEARBUNDLES'
_mf="$ROOT/usr/local/mavergreen/@P@/mavergreen.plist"
_rr=""
if [ -f "$_mf" ] && [ ! -L "$_mf" ]; then _rr="$(cd -P "$ROOT/" 2>/dev/null && pwd -P)" || _rr=""; fi
_i=0
while [ -n "$_rr" ] && _o="$(/usr/libexec/PlistBuddy -c "Print :outside:$_i" "$_mf" 2>/dev/null)"; do
  _i=$((_i + 1))
  case "$_o" in ''|/*|*/|*//*|usr/local/mavergreen|usr/local/mavergreen/*) continue ;; esac
  case "/$_o/" in *"/./"*|*"/../"*) continue ;; esac
  case "${_o##*/}" in *.app|*.kext|*.prefPane|*.plugin|*.bundle|*.framework) ;; *) continue ;; esac
  _b="$ROOT/$_o"
  if [ -L "$_b" ] || [ ! -d "$_b" ]; then continue; fi
  _pd="$(cd -P "$(dirname "$_b")" 2>/dev/null && pwd -P)" || continue
  case "$_pd/" in
    "${_rr%/}/"*) rm -rf "$_b" 2>/dev/null || echo "@P@: could not clear $_o; files dropped from it may linger" >&2 ;;
    *) echo "@P@: not clearing $_o -- its parent directory resolves outside $ROOT/" >&2 ;;
  esac
done
CLEARBUNDLES
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
  if [ -n "$POSTH" ]; then
    printf '(\n:\n'; cat "$POSTH"; printf '\n) || { echo "%s: postinstall hook failed" >&2; exit 1; }\n' "$P"
  fi
  printf 'exit 0\n'
} > "$SCR/postinstall"
rm -f "$SCR/.agent-load"
for g in "$SCR/preinstall" "$SCR/postinstall"; do
  sh -n "$g" || { echo "stage_product: generated $g is not valid sh (hooks: ${PREH:-none} ${POSTH:-none}); refusing to stage" >&2; exit 1; }
done
chmod +x "$SCR/preinstall" "$SCR/postinstall"
