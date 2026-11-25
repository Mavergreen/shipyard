#!/bin/sh
# platform: host-agnostic -- stevedore reads the updater's identity; the generated preinstall's PlistBuddy text runs on the target
#   usage: stage_product.sh --stage ROOT --product P --name N --version V --scripts-out DIR
#            [--group G] [--line L] [--exclude REL]... [--replaces ABS=REL]... [--generated REL]...
#            [--requires SHORT[>=VERSION]]... [--requires-on-host ARCH:SHORT[>=VERSION]]... [--updater-app P-updater.app] [--preinstall-hook FILE]
#            [--postinstall-hook FILE] [--boot-kext BUNDLE_ID]...
#          The one way a product pkg gets its install scripts and manifest. The caller has already
#          staged its files under ROOT/usr/local/mavergreen/P/ (and anything the OS dictates elsewhere).
#          The updater's place, label and feed are P's, from scripts/product-names: an updater built
#          for anything else is refused, and so are --appcast, --app-dir and --agent-label.
#          --requires SHORT (repeatable) makes the generated preinstall refuse to run, before
#          anything is removed, when SHORT's product is not installed on the target volume. SHORT
#          must be a different, registered product; stage_product refuses otherwise. With
#          >=VERSION it also refuses when the installed SHORT is older than VERSION, or its version
#          cannot be compared; VERSION must be orderable by scripts/lib/vercmp.sh.
#          --requires-on-host ARCH:SHORT[>=VERSION] (repeatable; ARCH is x86_64 or arm64) is --requires
#          for one host arch: the preinstall enforces it on any target volume other than /, and on /
#          only when the host's hardware arch (sysctl hw.optional.arm64, inlined from
#          scripts/lib/host-arch.sh) is ARCH. SHORT may not also be a plain --requires.
#          --boot-kext BUNDLE_ID (repeatable) names an unsigned kext staged anywhere under ROOT that
#          10.9 must load: the postinstall lists BUNDLE_ID, at the installed kext's CFBundleVersion, in
#          the target volume's OSKextSigExceptionList and, on the boot volume, restarts kextd, before
#          the updater's agent and the postinstall hook; the tree's libexec/mavergreen/pre-uninstall
#          removes it. A pre-uninstall the caller staged runs first, as pre-uninstall.product.
# spec: tests/stage-product-test.sh
set -eu
umask 022
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
. "$SELF/lib/vercmp.sh"
nl='
'
shq() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
ST=""; P=""; SCR=""; APP=""; PREH=""; POSTH=""; NAME=""; REQ=""; REQH=""; KX=""
set -- "$@" --end
while [ "$1" != --end ]; do
  case "$1" in
    --stage|--product|--scripts-out|--updater-app|--preinstall-hook|--postinstall-hook|--name|--version|--group|--line|--exclude|--replaces|--generated|--requires|--requires-on-host|--boot-kext)
      [ $# -ge 2 ] && [ "$2" != --end ] || { echo "stage_product: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --stage) ST="${2%/}"; set -- "$@" "$1" "$2"; shift 2 ;;
    --product) P="$2"; set -- "$@" "$1" "$2"; shift 2 ;;
    --scripts-out) SCR="$2"; shift 2 ;;
    --updater-app) APP="$2"; shift 2 ;;
    --preinstall-hook) PREH="$2"; shift 2 ;;
    --postinstall-hook) POSTH="$2"; shift 2 ;;
    --name) NAME="$2"; set -- "$@" "$1" "$2"; shift 2 ;;
    --requires) REQ="$REQ$2$nl"; set -- "$@" "$1" "$2"; shift 2 ;;
    --requires-on-host) REQH="$REQH$2$nl"; set -- "$@" "$1" "$2"; shift 2 ;;
    --boot-kext)
      case "$2" in *[!A-Za-z0-9._-]*|.*|-*) echo "stage_product: --boot-kext: bad bundle id '$2'" >&2; exit 2 ;; esac
      case "$nl$KX" in *"$nl$2 "*) echo "stage_product: --boot-kext $2 is named twice" >&2; exit 2 ;; esac
      KX="$KX$2 $nl"; shift 2 ;;
    --version|--group|--line|--exclude|--replaces|--generated) set -- "$@" "$1" "$2"; shift 2 ;;
    --appcast|--app-dir|--agent-label) echo "stage_product: $1 is derived from shipyard's scripts/product-names; stop passing it" >&2; exit 2 ;;
    *) echo "stage_product: unknown option $1" >&2; exit 2 ;;
  esac
done
shift
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$SCR" ] || { echo "stage_product: need --stage --product --scripts-out" >&2; exit 2; }
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_product: bad product name '$P'" >&2; exit 2 ;; esac
[ -n "$(find "$ST" \( -type f -o -type l \) 2>/dev/null | head -n 1)" ] || { echo "stage_product: nothing staged under $ST" >&2; exit 1; }
validate_require() {  # $1 = option, $2 = entry, $3 = its SPEC (SHORT[>=VERSION])
  _vr="$3"; _rs="${_vr%%>=*}"
  case "$_vr" in
    *'>='*)
      _rmin="${_vr#*>=}"
      numeric "$(comparison_key "$_rmin")" \
        || { echo "stage_product: $1 $2: '$_rmin' is not an orderable version (see scripts/lib/vercmp.sh)" >&2; exit 2; } ;;
  esac
  case "$_rs" in
    '') echo "stage_product: $1 $2 names no product" >&2; exit 2 ;;
    "$P") echo "stage_product: $1 $2: a product cannot require itself" >&2; exit 2 ;;
  esac
  _rlrc=0
  registry_lookup repo "$_rs" || _rlrc=$?
  case "$_rlrc" in
    0) : ;;
    1) echo "stage_product: $1 $2: $_rs is not in shipyard's scripts/product-names -- register it there first" >&2; exit 2 ;;
    *) printf 'stage_product: cannot look up %s in shipyard'"'"'s registry\n%s\n' "$_rs" "$REG_WHY" >&2; exit 2 ;;
  esac
}
_ifs="$IFS"; IFS="$nl"
for r in $REQ; do
  IFS="$_ifs"
  validate_require --requires "$r" "$r"
  IFS="$nl"
done
for r in $REQH; do
  IFS="$_ifs"
  case "$r" in
    x86_64:*|arm64:*) : ;;
    *) echo "stage_product: --requires-on-host $r names no arch x86_64 or arm64" >&2; exit 2 ;;
  esac
  validate_require --requires-on-host "$r" "${r#*:}"
  case "$nl$REQ" in
    *"$nl${r#*:}$nl"*|*"$nl${r#*:}>="*) echo "stage_product: --requires-on-host $r: ${_rs} is named by both --requires and --requires-on-host" >&2; exit 2 ;;
  esac
  IFS="$nl"
done
IFS="$_ifs"
for h in "$PREH" "$POSTH"; do
  if [ -n "$h" ]; then
    sh -n "$h" || { echo "stage_product: hook $h is not valid sh; refusing to stage" >&2; exit 1; }
  fi
done
kvawk='f == 0 && (i = index($0, "<key>CFBundleVersion</key>")) { $0 = substr($0, i + 26); f = 1 } f && match($0, /<string>[^<]*<\/string>/) { print substr($0, RSTART + 8, RLENGTH - 17); exit }'
if [ -n "$KX" ]; then
  STEVEDORE="${STEVEDORE:-$(sh "$SELF/fetch_stevedore.sh")}"; export STEVEDORE
  _kxs="$( cd "$ST" && find . -type d -name '*.kext' | sed 's|^\./||' )"
  _kxn=""
  _ifs="$IFS"; IFS="$nl"
  for k in $KX; do
    IFS="$_ifs"; k="${k% }"; _rel=""
    IFS="$nl"
    for b in $_kxs; do
      IFS="$_ifs"
      [ -f "$ST/$b/Contents/Info.plist" ] || continue
      [ "$("$STEVEDORE" plist get "$ST/$b/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || :)" = "$k" ] || continue
      [ -z "$_rel" ] || { echo "stage_product: --boot-kext $k: both $_rel and $b are $k" >&2; exit 1; }
      _rel="$b"
    done
    IFS="$_ifs"
    [ -n "$_rel" ] || { echo "stage_product: --boot-kext $k: no kext staged under $ST has CFBundleIdentifier $k" >&2; exit 1; }
    case "$_rel" in *"'"*|*'"'*|*'$'*|*'`'*|*'\'*) echo "stage_product: --boot-kext $k: its path $_rel has a quote, \$, \` or \\ the postinstall cannot carry" >&2; exit 1 ;; esac
    _kip="$ST/$_rel/Contents/Info.plist"
    head -c 5 "$_kip" | grep -q '^<?xml' \
      || { echo "stage_product: --boot-kext $k: $_rel/Contents/Info.plist is not an XML plist, so the postinstall cannot read its CFBundleVersion" >&2; exit 1; }
    _kv="$(awk "$kvawk" "$_kip")"
    [ -n "$_kv" ] && [ "$_kv" = "$("$STEVEDORE" plist get "$_kip" CFBundleVersion 2>/dev/null || :)" ] \
      || { echo "stage_product: --boot-kext $k: $_rel has no top-level CFBundleVersion the postinstall can read (read '${_kv:-none}')" >&2; exit 1; }
    _kxn="$_kxn$k $_rel$nl"
    IFS="$nl"
  done
  IFS="$_ifs"
  _lx="$ST/usr/local/mavergreen/$P/libexec/mavergreen"
  mkdir -p "$_lx"
  _kxmark='# spec: shipyard scripts/stage_product.sh --boot-kext -- removes the ids it listed in OSKextSigExceptionList'
  if [ -L "$_lx/pre-uninstall" ]; then
    echo "stage_product: $_lx/pre-uninstall is a symlink; the helper refuses one" >&2; exit 1
  elif [ -e "$_lx/pre-uninstall" ] && ! grep -qxF "$_kxmark" "$_lx/pre-uninstall"; then
    [ ! -e "$_lx/pre-uninstall.product" ] && [ ! -L "$_lx/pre-uninstall.product" ] \
      || { echo "stage_product: both $_lx/pre-uninstall and pre-uninstall.product are staged; --boot-kext runs the product's own hook as pre-uninstall.product" >&2; exit 1; }
    mv "$_lx/pre-uninstall" "$_lx/pre-uninstall.product"
  fi
  cp "$SELF/kext_sig_exception.sh" "$_lx/kext-sig-exception"
  {
    printf '#!/bin/sh\n# platform: host-agnostic\n%s\n' "$_kxmark"
    printf 'set -u\n_d="$(cd "$(dirname "$0")" && pwd)"\n'
    printf 'if [ -e "$_d/pre-uninstall.product" ]; then\n  "$_d/pre-uninstall.product" || exit $?\nfi\n'
    printf '_xl="${MAVERGREEN_ROOT:-/}"; _xl="${_xl%%/}/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist"\n'
    printf '[ -f "$_xl" ] || exit 0\n'
    printf '%s' "$_kxn" | while read -r k _; do
      printf 'sh "$_d/kext-sig-exception" remove "$_xl" %s || echo "%s: could not remove %s from $_xl" >&2\n' "$k" "$P" "$k"
    done
    printf 'exit 0\n'
  } > "$_lx/pre-uninstall"
  chmod 755 "$_lx/pre-uninstall" "$_lx/kext-sig-exception"
fi
mkdir -p "$ST/usr/local/mavergreen/$P"
mkdir -p "$SCR"
snippet=""
if [ -n "$APP" ]; then
  registry_need stage_product updater-bundle-id "$P"; _want_id="$REG_V"
  registry_need stage_product feed "$P"; _want_feed="$REG_V"
  STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")"; export STEVEDORE
  _got_id="$("$STEVEDORE" plist get "$APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" || _got_id=""
  _got_feed="$("$STEVEDORE" plist get "$APP/Contents/Info.plist" SUFeedURL 2>/dev/null)" || _got_feed=""
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
  if [ -n "$REQ$REQH" ]; then
    printf '_reqs_missing=0\n'
    # platform: inline the comparator: a product's preinstall runs before the base component's postinstall.
    case "$REQ$REQH" in *'>='*) cat "$SELF/lib/vercmp.sh"; printf '\n' ;; esac
    if [ -n "$REQH" ]; then cat "$SELF/lib/host-arch.sh"; printf '\n'; fi
    emit_require() {  # $1 = SHORT[>=VERSION]
      _rs="${1%%>=*}"
      registry_need stage_product repo "$_rs"; _reqrepo="$REG_V"
      _requrl="https://github.com/Mavergreen/$_reqrepo/releases/latest"
      _reqmsg="$NAME needs $_rs installed first: $_requrl -- install it, then run this installer again."
      printf 'if [ ! -f "$ROOT/usr/local/mavergreen/%s/mavergreen.plist" ]; then\n' "$_rs"
      printf "  echo '%s' >&2\n" "$(shq "$_reqmsg")"
      printf '  _reqs_missing=1\n'
      case "$1" in
        *'>='*)
          _rmin="${1#*>=}"
          printf 'else\n'
          printf '  _req_v="$(/usr/libexec/PlistBuddy -c '"'"'Print :version'"'"' "$ROOT/usr/local/mavergreen/%s/mavergreen.plist" 2>/dev/null | sed -n 1p)"\n' "$_rs"
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
          ;;
      esac
      printf 'fi\n'
    }
    _ifs="$IFS"; IFS="$nl"
    for r in $REQ; do
      IFS="$_ifs"
      emit_require "$r"
      IFS="$nl"
    done
    for r in $REQH; do
      IFS="$_ifs"
      printf 'if [ -n "$ROOT" ] || [ "$(mavergreen_host_arch)" = %s ]; then\n' "${r%%:*}"
      emit_require "${r#*:}"
      printf 'fi\n'
      IFS="$nl"
    done
    IFS="$_ifs"
    printf '[ "$_reqs_missing" -eq 0 ] || exit 1\n'
  fi
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
  case "${_o##*/}" in *.app|*.kext|*.prefPane|*.plugin|*.bundle|*.framework|*.jdk) ;; *) continue ;; esac
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
  if [ -n "$KX" ]; then
    printf '_kx="$ROOT/usr/local/mavergreen/%s/libexec/mavergreen/kext-sig-exception"\n' "$P"
    printf '_kl="$ROOT/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist"\n'
    printf '_kx_added=0\n'
    printf 'if [ -f "$_kl" ]; then\n'
    printf '%s' "$_kxn" | while read -r k rel; do
      printf "  _kv=\"\$(awk '%s' \"\$ROOT/%s/Contents/Info.plist\" 2>/dev/null || :)\"\n" "$kvawk" "$rel"
      printf '  if [ -n "$_kv" ] && sh "$_kx" add "$_kl" %s "$_kv"; then _kx_added=1; else echo "%s: could not list %s in $_kl; 10.9 loads it only with kext-dev-mode=1" >&2; fi\n' "$k" "$P" "$k"
    done
    printf 'fi\n'
    printf 'if [ "$_kx_added" = 1 ] && [ -z "$ROOT" ]; then /bin/launchctl stop com.apple.kextd 2>/dev/null || echo "%s: could not restart kextd; its kexts load from the next boot" >&2; fi\n' "$P"
    printf 'unset _kx _kl _kv _kx_added\n'
  fi
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
