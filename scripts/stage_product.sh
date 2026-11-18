#!/bin/sh
# platform: host-agnostic -- stevedore reads the updater's identity; the generated preinstall's PlistBuddy text runs on the target
#   usage: stage_product.sh --stage ROOT --product P --version V --scripts-out DIR
#            [--exclude REL]... [--replaces ABS=REL]... [--generated REL]...
#            [--updater-app P-updater.app] [--preinstall-hook FILE] [--postinstall-hook FILE]
#          The one way a product pkg gets its install scripts and manifest. The caller has already
#          staged its files under ROOT/opt/mavergreen/P/, its apps under ROOT/Applications/Mavergreen/,
#          and anything else the OS dictates elsewhere; an app anywhere else in Applications/ is refused.
#          The updater's place, label and feed are P's, from scripts/updater-identity.sh: an updater
#          built for anything else is refused, and so are --appcast, --app-dir and --agent-label.
#          Group and requirements are read from .mavergreen/products/P/ (group, requires/<dep>/), so
#          --group and --requires are refused. Each requirement whose kind is not external makes the
#          generated preinstall refuse to run, before anything is removed, when <dep> is not installed
#          on the target volume, or is older than requires/<dep>/min, or cannot be compared; the
#          refusal names .mavergreen/ingredients/<dep>/REPO's releases. min must be orderable by
#          scripts/lib/vercmp.sh.
# spec: tests/stage-product-test.sh
set -eu
umask 022
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/vercmp.sh"
nl='
'
tab="$(printf '\t')"
shq() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
ST=""; P=""; SCR=""; APP=""; PREH=""; POSTH=""; GEN=""
set -- "$@" --end
while [ "$1" != --end ]; do
  case "$1" in
    --stage|--product|--scripts-out|--updater-app|--preinstall-hook|--postinstall-hook|--version|--exclude|--replaces|--generated)
      [ $# -ge 2 ] && [ "$2" != --end ] || { echo "stage_product: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --stage) ST="${2%/}"; set -- "$@" "$1" "$2"; shift 2 ;;
    --product) P="$2"; set -- "$@" "$1" "$2"; shift 2 ;;
    --scripts-out) SCR="$2"; shift 2 ;;
    --updater-app) APP="$2"; shift 2 ;;
    --preinstall-hook) PREH="$2"; shift 2 ;;
    --postinstall-hook) POSTH="$2"; shift 2 ;;
    --name) echo "stage_product: --name is derived from the product; write .mavergreen/products/<P>/noun" >&2; exit 2 ;;
    --line) echo "stage_product: --line is derived from the product; write .mavergreen/products/<P>/line" >&2; exit 2 ;;
    --group) echo "stage_product: --group is read from the product; write .mavergreen/products/<P>/group" >&2; exit 2 ;;
    --requires) echo "stage_product: --requires is read from the product; write .mavergreen/products/<P>/requires/<dep>/ (kind, and min when it has one)" >&2; exit 2 ;;
    --generated) GEN="$GEN$2$nl"; set -- "$@" "$1" "$2"; shift 2 ;;
    --version|--exclude|--replaces) set -- "$@" "$1" "$2"; shift 2 ;;
    --appcast|--app-dir|--agent-label) echo "stage_product: $1 is derived from --product; stop passing it" >&2; exit 2 ;;
    *) echo "stage_product: unknown option $1" >&2; exit 2 ;;
  esac
done
shift
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$SCR" ] || { echo "stage_product: need --stage --product --scripts-out" >&2; exit 2; }
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_product: bad product name '$P'" >&2; exit 2 ;; esac
NAME="$(mavergreen_name manifest-name "$P")" || exit $?
PFX="$(mavergreen_prefix "$P")" || exit $?
[ -n "$(find "$ST" \( -type f -o -type l \) 2>/dev/null | head -n 1)" ] || { echo "stage_product: nothing staged under $ST" >&2; exit 1; }
_stray="$( (cd "$ST" && find Applications ! -path Applications ! -path Applications/Mavergreen ! -path 'Applications/Mavergreen/*' 2>/dev/null) | sed -n 's|^\(Applications/[^/]*\).*|\1|p' | sed -n 1p)"
[ ! -L "$ST/Applications/Mavergreen" ] || _stray=Applications/Mavergreen
[ -z "$_stray" ] || { echo "stage_product: $_stray is outside Applications/Mavergreen/; stage apps under Applications/Mavergreen/" >&2; exit 1; }
APPS=""
if [ -d "$ST/Applications/Mavergreen" ]; then APPS=1; fi
case "$nl$GEN" in *"${nl}Applications/Mavergreen/"*) APPS=1 ;; esac
REQ=""; HASMIN=""
_deps="$(mg_list "products/$P/requires")"
set -f; _ifs="$IFS"; IFS="$nl"
for d in $_deps; do
  IFS="$_ifs"
  _rd="products/$P/requires/$d"
  _rk="$(mg_value "$_rd/kind" 2>/dev/null)" || _rk=
  if [ "$_rk" != external ]; then
    mavergreen_name_ok "$d" || { echo "stage_product: .mavergreen/$_rd: '$d' is not a product short name" >&2; exit 2; }
    [ "$d" != "$P" ] || { echo "stage_product: .mavergreen/$_rd: a product cannot require itself" >&2; exit 2; }
    _rr="$(mg_value "ingredients/$d/REPO" 2>/dev/null)" || _rr=
    case "$_rr" in ''|/*|*/|*/*/*|*[!A-Za-z0-9._/-]*) _rr= ;; */*) ;; *) _rr= ;; esac
    [ -n "$_rr" ] || { echo "stage_product: .mavergreen/$_rd: this repo has no .mavergreen/ingredients/$d/REPO naming owner/repo, whose releases its refusal points at; declare it (product, REPO)" >&2; exit 2; }
    _rm=""; _rh=""
    if mg_has "$_rd/min"; then
      _rh=1; HASMIN=1; _rm="$(mg_value "$_rd/min" 2>/dev/null)" || _rm=
      numeric "$(comparison_key "$_rm")" \
        || { echo "stage_product: .mavergreen/$_rd/min: '$_rm' is not an orderable version (see scripts/lib/vercmp.sh)" >&2; exit 2; }
    fi
    REQ="$REQ$d$tab$_rr$tab$_rh$tab$_rm$nl"
  fi
  IFS="$nl"
done
IFS="$_ifs"; set +f
for h in "$PREH" "$POSTH"; do
  if [ -n "$h" ]; then
    sh -n "$h" || { echo "stage_product: hook $h is not valid sh; refusing to stage" >&2; exit 1; }
  fi
done
mkdir -p "$ST$PFX"
mkdir -p "$SCR"
snippet=""
if [ -n "$APP" ]; then
  _want_id="$(sh "$SELF/updater-identity.sh" bundle-id "$P")" || exit $?
  _want_feed="$(sh "$SELF/updater-identity.sh" feed "$P")" || exit $?
  STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"; export STEVEDORE
  _got_id="$("$STEVEDORE" plist get "$APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" || _got_id=""
  _got_feed="$("$STEVEDORE" plist get "$APP/Contents/Info.plist" SUFeedURL 2>/dev/null)" || _got_feed=""
  [ "$_got_id" = "$_want_id" ] && [ "$_got_feed" = "$_want_feed" ] \
    || { echo "stage_product: $APP was not built for $P: it is '${_got_id:-none}' polling '${_got_feed:-none}', and $P's is $_want_id polling $_want_feed -- build it with mavericks_add_updater_app(PRODUCT $P)" >&2; exit 1; }
  snippet="$SCR/.agent-load"
  sh "$SELF/stage_updater.sh" --stage "$ST" --app "$APP" --product "$P" --snippet-out "$snippet"
fi
sh "$SELF/render-manifest.sh" "$@"
ANC="$( (cd "$ST" && find "Library/Application Support" ! -path "Library/Application Support" 2>/dev/null) \
  | awk -F/ '{ n = NF; for (k = 3; k <= NF; k++) if ($k ~ /\.(app|kext|prefPane|plugin|bundle|framework|jdk|fs)$/) { n = k; break }
               p = $1 "/" $2; for (k = 3; k <= n; k++) { p = p "/" $k; print p } }' | sort -u)"
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: preinstall got no target volume; removing nothing" >&2; exit 0; }\n' "$P"
  printf 'LC_ALL=C; export LC_ALL\n'
  cat "$SELF/lib/root-chain.sh"; printf '\n'
  if [ -n "$HASMIN" ]; then cat "$SELF/lib/vercmp.sh"; printf '\n'; fi
  printf 'ROOT="${3%%/}"\n'
  printf 'mavergreen_chain_ok "$3/opt/mavergreen" "$3" || exit 1\n'
  if [ -n "$APPS" ]; then printf 'mavergreen_root_dir "$ROOT/Applications/Mavergreen" || exit 1\n'; fi
  if [ -n "$ANC" ]; then
    printf '_mg_anc_bad=0\n'
    printf '%s\n' "$ANC" | while IFS= read -r a; do
      printf "mavergreen_owned_ok \"\$ROOT/\"'%s' || _mg_anc_bad=1\n" "$(shq "$a")"
    done
    printf '[ "$_mg_anc_bad" -eq 0 ] || exit 1\n'
  fi
  if [ -n "$REQ" ]; then
    printf '_reqs_missing=0\n'
    printf '%s' "$REQ" | while IFS="$tab" read -r _rs _reqrepo _rh _rmin; do
      _requrl="https://github.com/$_reqrepo/releases"
      _reqmsg="$NAME needs $_rs installed first: $_requrl -- install it, then run this installer again."
      printf 'if [ ! -f "$ROOT/opt/mavergreen/%s/mavergreen.plist" ]; then\n' "$_rs"
      printf "  echo '%s' >&2\n" "$(shq "$_reqmsg")"
      printf '  _reqs_missing=1\n'
      if [ -n "$_rh" ]; then
        printf 'else\n'
        printf '  _req_v="$(/usr/libexec/PlistBuddy -c '"'"'Print :version'"'"' "$ROOT/opt/mavergreen/%s/mavergreen.plist" 2>/dev/null | sed -n 1p)"\n' "$_rs"
        printf "  _req_rc=0; _req_c=\"\$(mavergreen_vercmp \"\$_req_v\" '%s')\" || _req_rc=\$?\n" "$(shq "$_rmin")"
        printf '  if [ "$_req_rc" -ne 0 ]; then\n'
        printf "    printf '%%s%%s%%s\\\\n' '%s' \"\${_req_v:-none}\" '%s' >&2\n" \
          "$(shq "$NAME needs $_rs $_rmin or newer, but its installed version (")" \
          "$(shq ") cannot be compared: $_requrl -- update it, then run this installer again.")"
        printf '    _reqs_missing=1\n'
        printf '  elif [ "$_req_c" = -1 ]; then\n'
        printf "    printf '%%s%%s%%s\\\\n' '%s' \"\$_req_v\" '%s' >&2\n" \
          "$(shq "$NAME needs $_rs $_rmin or newer (installed: ")" \
          "$(shq "): $_requrl -- update it, then run this installer again.")"
        printf '    _reqs_missing=1\n'
        printf '  fi\n'
      fi
      printf 'fi\n'
    done
    printf '[ "$_reqs_missing" -eq 0 ] || exit 1\n'
  fi
  printf 'if [ -x "$ROOT/opt/mavergreen/bin/mavergreen" ]; then\n'
  printf '  mavergreen_chain_ok "$3/opt/mavergreen/bin/mavergreen" "$3" || exit 1\n'
  printf '  "$ROOT/opt/mavergreen/bin/mavergreen" --root "$ROOT/" unlink %s 2>/dev/null || true\n' "$P"
  printf 'fi\n'
  if [ -n "$PREH" ]; then
    printf '(\n:\n'; cat "$PREH"; printf '\n) || {\n'
    printf '  if [ ! -x "$ROOT/opt/mavergreen/bin/mavergreen" ] || "$ROOT/opt/mavergreen/bin/mavergreen" --root "$ROOT/" link %s >/dev/null 2>&1; then\n' "$P"
    printf '    echo "%s: preinstall hook failed; the installed version is left in place" >&2\n' "$P"
    printf '  else\n'
    printf '    echo "%s: preinstall hook failed" >&2\n' "$P"
    printf '    echo '"'"'%s: could not relink; run `mavergreen link %s`'"'"' >&2\n' "$P" "$P"
    printf '  fi\n'
    printf '  exit 1\n}\n'
  fi
  sed "s/@P@/$P/g" <<'CLEARBUNDLES'
_mf="$ROOT/opt/mavergreen/@P@/mavergreen.plist"
_rr=""
if [ -f "$_mf" ] && [ ! -L "$_mf" ]; then _rr="$(cd -P "$ROOT/" 2>/dev/null && pwd -P)" || _rr=""; fi
_i=0
while [ -n "$_rr" ] && _o="$(/usr/libexec/PlistBuddy -c "Print :outside:$_i" "$_mf" 2>/dev/null)"; do
  _i=$((_i + 1))
  case "$_o" in ''|/*|*/|*//*|opt/mavergreen|opt/mavergreen/*) continue ;; esac
  case "/$_o/" in *"/./"*|*"/../"*) continue ;; esac
  case "${_o##*/}" in *.app|*.kext|*.prefPane|*.plugin|*.bundle|*.framework|*.jdk|*.fs) ;; *) continue ;; esac
  _b="$ROOT/$_o"
  if [ -L "$_b" ] || [ ! -d "$_b" ]; then continue; fi
  _pd="$(cd -P "$(dirname "$_b")" 2>/dev/null && pwd -P)" || continue
  case "$_pd/" in
    "${_rr%/}/"*) rm -rf "$_b" 2>/dev/null || echo "@P@: could not clear $_o; files dropped from it may linger" >&2 ;;
    *) echo "@P@: not clearing $_o -- its parent directory resolves outside $ROOT/" >&2 ;;
  esac
done
CLEARBUNDLES
  printf 'rm -rf "$ROOT/opt/mavergreen/%s" 2>/dev/null || echo "%s: could not clear $ROOT/opt/mavergreen/%s; files dropped from this version may linger" >&2\n' "$P" "$P" "$P"
  printf 'exit 0\n'
} > "$SCR/preinstall"
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: postinstall got no target volume" >&2; exit 1; }\n' "$P"
  printf 'LC_ALL=C; export LC_ALL\n'
  cat "$SELF/lib/root-chain.sh"; printf '\n'
  cat "$SELF/lib/vercmp.sh"; printf '\n'
  printf 'ROOT="${3%%/}"\n'
  cat <<'HELPERPICK'
_mg_at="$3/opt/mavergreen/bin/mavergreen"
MG="$ROOT/opt/mavergreen/bin/mavergreen"
if [ ! -x "$MG" ]; then
  MG=""; MGV=""
  for _mg_c in "$ROOT"/opt/mavergreen/.base/*/mavergreen; do
    [ -x "$_mg_c" ] || continue
    _mg_v="${_mg_c%/mavergreen}"; _mg_v="${_mg_v##*/}"
    case "$_mg_v" in ''|*[!0-9.]*|.*|*.|*..*) continue ;; esac
    if [ -z "$MG" ] || [ "$(mavergreen_vercmp "$_mg_v" "$MGV")" = 1 ]; then MG="$_mg_c"; MGV="$_mg_v"; fi
  done
  _mg_at="$3/opt/mavergreen/.base/$MGV/mavergreen"
fi
HELPERPICK
  printf '[ -n "$MG" ] && [ -x "$MG" ] || { echo "%s: no mavergreen helper on this volume" >&2; exit 1; }\n' "$P"
  printf 'mavergreen_chain_ok "$_mg_at" "$3" || exit 1\n'
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
