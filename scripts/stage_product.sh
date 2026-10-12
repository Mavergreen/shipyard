#!/bin/sh
# platform: macOS-only -- PlistBuddy reads the updater's identity, and render-manifest.sh reads back and lints the manifest
#   usage: stage_product.sh --stage ROOT --product P --name N --version V --scripts-out DIR
#            [--group G] [--line L] [--exclude REL]... [--replaces ABS=REL]... [--adopts ABS=REL:KIND]...
#            [--seed VARREL=TREEREL]...
#            [--generated REL]...
#            [--requires SHORT]... [--updater-app P-updater.app] [--preinstall-hook FILE]
#            [--postinstall-hook FILE] [--preflight HOOK] [--preflight-file PATH]...
#          The one way a product pkg gets its install scripts and manifest. The caller has already
#          staged its files under ROOT/usr/local/mavergreen/P/ (and anything the OS dictates elsewhere).
#          The updater's place, label and feed are P's, from scripts/product-names: an updater built
#          for anything else is refused, and so are --appcast, --app-dir and --agent-label.
#          --seed VARREL=TREEREL (repeatable) makes the generated postinstall copy the staged tree file
#          P/TREEREL to var/P/VARREL once, when nothing (not even a link) is there, and record its
#          sha256 in var/P/.mavergreen-seeded. Both sides are relative with no .. component,
#          VARREL is not .mavergreen-seeded itself (in any case), and TREEREL must be a staged
#          regular file; stage_product refuses otherwise, with exit 2.
#          After link and seeding, the generated postinstall of a product whose System Replace is
#          applied (var/system-replace/P/.replaced) runs `mavergreen system-replace P` again, so an
#          upgrade re-applies it; a failure there fails the install.
#          --requires SHORT (repeatable) makes the generated preinstall refuse to run, before
#          anything is removed, when SHORT's product is not installed on the target volume. SHORT
#          must be a different, registered product; stage_product refuses otherwise.
#          --preflight HOOK (at most once) makes the generated preinstall run HOOK's text first, before
#          --requires, unlink or anything else, in a subshell with ROOT and PREFLIGHT_DIR set.
#          PREFLIGHT_DIR is the preflight/ directory beside the preinstall in the pkg's Scripts; each
#          --preflight-file PATH (repeatable) is copied there with its mode. stage_product owns
#          DIR/preflight/ (DIR from --scripts-out): every run removes it, and only --preflight remakes
#          it. The hook checks the live config with the new binary. Its status is its subshell's exit
#          status. It inherits the preinstall's errexit, which is off as Installer runs it, so a hook
#          either checks each status or runs set -e itself. On non-zero the preinstall prints "P: the
#          new version cannot use this Mac's configuration; nothing was changed", then the hook's
#          stderr, and exits 1; on zero it passes the hook's stderr on and goes on. The hook's stdout
#          always passes through. stage_product refuses a HOOK that is not a file or that sh -n
#          rejects, a second --preflight, a --preflight-file without --preflight, one that is not a
#          file or whose path holds a newline, and two with the same basename.
#          --preinstall-hook and --postinstall-hook run in a subshell that inherits the script's
#          errexit, as the preflight does; a non-zero status fails the install.
#          Upgrades lay the payload over the installed tree, which is never removed whole (spec F).
#          stage_product writes P/.mavergreen-payload and DIR/.mavergreen-payload: one
#          "KIND<tab>PATH" line per path staged under P/, PATH relative to P/, KIND f (file), l (link),
#          d (directory) or b (bundle directory), sorted by PATH; the list never names itself. It
#          refuses, with exit 2, a staged name holding a tab or newline and a P/.mavergreen-payload
#          that is a directory; a failing find, awk or sort while listing exits 1 with no list.
#          The generated preinstall removes only each installed path whose kind the incoming list
#          changes, and every bundle directory in the tree. Before unlink it checks every one of those
#          removals and refuses, with exit 1 and nothing changed, when DIR/.mavergreen-payload is
#          missing or a removal would not stay inside the tree; after the hook and the `outside`
#          bundles it removes them, and if one fails it links the installed version again and exits
#          1. The generated postinstall first removes every file or link in the tree that its list
#          does not name (never mavergreen.plist or the list), then the unnamed directories left
#          empty, deepest first; it prunes nothing, and says so, unless the tree's list is non-empty
#          and identical to DIR's. Neither removes through a link inside the tree: a removal's
#          directory must resolve to the tree's own physical path, which may lie through links above
#          it, such as a usr/local linked to another volume.
# spec: tests/stage-product-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/registry-lookup.sh"
nl='
'
shq() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
SEEDS=""; ST=""; P=""; SCR=""; APP=""; PREH=""; POSTH=""; NAME=""; REQ=""; PFSET=""; PFH=""; PFF=""
set -- "$@" --end
while [ "$1" != --end ]; do
  case "$1" in
    --stage|--product|--scripts-out|--updater-app|--preinstall-hook|--postinstall-hook|--name|--version|--group|--line|--exclude|--replaces|--adopts|--generated|--requires|--seed|--preflight|--preflight-file)
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
    --seed) SEEDS="$SEEDS$2$nl"; shift 2 ;;
    --requires) REQ="$REQ$2$nl"; shift 2 ;;
    --preflight)
      [ -z "$PFSET" ] || { echo "stage_product: --preflight is given twice; a product has one preflight hook" >&2; exit 2; }
      PFSET=1; PFH="$2"; shift 2 ;;
    --preflight-file)
      case "$2" in *"$nl"*) echo "stage_product: --preflight-file '$2' contains a newline, which the file list cannot carry; rename the file" >&2; exit 2 ;; esac
      PFF="$PFF$2$nl"; shift 2 ;;
    --version|--group|--line|--exclude|--replaces|--adopts|--generated) set -- "$@" "$1" "$2"; shift 2 ;;
    --appcast|--app-dir|--agent-label) echo "stage_product: $1 is derived from shipyard's scripts/product-names; stop passing it" >&2; exit 2 ;;
    *) echo "stage_product: unknown option $1" >&2; exit 2 ;;
  esac
done
shift
[ -n "$ST" ] && [ -n "$P" ] && [ -n "$SCR" ] || { echo "stage_product: need --stage --product --scripts-out" >&2; exit 2; }
case "$P" in ''|-*|*[!a-z0-9-]*) echo "stage_product: bad product name '$P'" >&2; exit 2 ;; esac
[ -n "$(find "$ST" \( -type f -o -type l \) 2>/dev/null | head -n 1)" ] || { echo "stage_product: nothing staged under $ST" >&2; exit 1; }
tab="$(printf '\t')"
TREE="$ST/usr/local/mavergreen/$P"
_badname="$(find "$TREE" \( -name "*$tab*" -o -name "*$nl*" \) -print 2>/dev/null | head -n 1)"
[ -z "$_badname" ] || { echo "stage_product: $_badname has a tab or newline in its name, which the payload list cannot carry; rename it" >&2; exit 2; }
if [ -d "$TREE/.mavergreen-payload" ] && [ ! -L "$TREE/.mavergreen-payload" ]; then
  echo "stage_product: $TREE/.mavergreen-payload is a directory; remove it, since stage_product writes the payload list there" >&2; exit 2
fi
_ifs="$IFS"; IFS="$nl"; set -f
for r in $REQ; do
  IFS="$_ifs"
  case "$r" in
    "$P") echo "stage_product: --requires $r: a product cannot require itself" >&2; exit 2 ;;
  esac
  _rlrc=0
  registry_lookup repo "$r" || _rlrc=$?
  case "$_rlrc" in
    0) : ;;
    1) echo "stage_product: --requires $r is not in shipyard's scripts/product-names -- register it there first" >&2; exit 2 ;;
    *) printf 'stage_product: cannot look up %s in shipyard'"'"'s registry\n%s\n' "$r" "$REG_WHY" >&2; exit 2 ;;
  esac
  IFS="$nl"
done
IFS="$_ifs"; set +f
seed_rel_ok() {
  case "$1" in ''|/*|*/|*//*|*"$nl"*) return 1 ;; esac
  case "/$1/" in *"/./"*|*"/../"*) return 1 ;; esac
  return 0
}
_ifs="$IFS"; IFS="$nl"; set -f
for sd in $SEEDS; do
  IFS="$_ifs"
  case "$sd" in
    *=*) _sv="${sd%%=*}"; _stree="${sd#*=}" ;;
    *) echo "stage_product: --seed '$sd' is not VARREL=TREEREL" >&2; exit 2 ;;
  esac
  seed_rel_ok "$_sv" || { echo "stage_product: --seed '$sd': '$_sv' must be a relative path under var/$P with no .. component" >&2; exit 2; }
  case "$(printf '%s' "$_sv" | tr 'A-Z' 'a-z')" in
    .mavergreen-seeded) echo "stage_product: --seed '$sd': var/$P/.mavergreen-seeded is where the seeds are recorded, so nothing can be seeded there" >&2; exit 2 ;;
  esac
  seed_rel_ok "$_stree" || { echo "stage_product: --seed '$sd': '$_stree' must be a relative path under the product tree with no .. component" >&2; exit 2; }
  [ -f "$ST/usr/local/mavergreen/$P/$_stree" ] && [ ! -L "$ST/usr/local/mavergreen/$P/$_stree" ] \
    || { echo "stage_product: --seed '$sd': $_stree is not a regular file staged under $ST/usr/local/mavergreen/$P/" >&2; exit 2; }
  IFS="$nl"
done
IFS="$_ifs"; set +f
for h in "$PREH" "$POSTH"; do
  if [ -n "$h" ]; then
    sh -n "$h" || { echo "stage_product: hook $h is not valid sh; refusing to stage" >&2; exit 1; }
  fi
done
if [ -n "$PFF" ] && [ -z "$PFSET" ]; then
  echo "stage_product: --preflight-file needs --preflight, the hook that runs it" >&2; exit 2
fi
if [ -n "$PFSET" ]; then
  [ -f "$PFH" ] || { echo "stage_product: preflight hook $PFH is not a file; refusing to stage" >&2; exit 2; }
  sh -n "$PFH" || { echo "stage_product: preflight hook $PFH is not valid sh; refusing to stage" >&2; exit 1; }
fi
_pfnames="$nl"
_ifs="$IFS"; IFS="$nl"; set -f
for f in $PFF; do
  IFS="$_ifs"
  [ -f "$f" ] || { echo "stage_product: --preflight-file $f is not a file; refusing to stage" >&2; exit 2; }
  case "$_pfnames" in
    *"$nl${f##*/}$nl"*) echo "stage_product: --preflight-file $f: another preflight file is also named ${f##*/}, and both would be preflight/${f##*/}" >&2; exit 2 ;;
  esac
  _pfnames="$_pfnames${f##*/}$nl"
  IFS="$nl"
done
IFS="$_ifs"; set +f
mkdir -p "$ST/usr/local/mavergreen/$P"
mkdir -p "$SCR"
rm -rf "$SCR/preflight"
if [ -n "$PFSET" ]; then
  mkdir "$SCR/preflight"
  _ifs="$IFS"; IFS="$nl"; set -f
  for f in $PFF; do
    IFS="$_ifs"
    cp -p -- "$f" "$SCR/preflight/"
    IFS="$nl"
  done
  IFS="$_ifs"; set +f
fi
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
_plw="$(mktemp -d "${TMPDIR:-/tmp}/stage_product.XXXXXX")" || { echo "stage_product: cannot make a temporary directory for the payload list" >&2; exit 1; }
pl_fail() { rm -rf "$_plw"; echo "stage_product: could not list the payload under $TREE ($1 failed); refusing to stage" >&2; exit 1; }
: > "$_plw/all" || pl_fail write
for k in f l d; do
  find "$TREE" -mindepth 1 -type "$k" -print > "$_plw/found" || pl_fail find
  PL_TREE="$TREE" awk -v k="$k" '
    BEGIN { n = length(ENVIRON["PL_TREE"]) + 2 }
    { r = substr($0, n); if (r == ".mavergreen-payload") next
      t = k; if (t == "d" && r ~ /\.(app|kext|prefPane|plugin|bundle|framework)$/) t = "b"
      print t "\t" r }' "$_plw/found" >> "$_plw/all" || pl_fail awk
done
LC_ALL=C sort -t "$tab" -k2,2 "$_plw/all" > "$_plw/sorted" || pl_fail sort
mv -f "$_plw/sorted" "$SCR/.mavergreen-payload" || pl_fail mv
rm -f "$TREE/.mavergreen-payload" && cp "$SCR/.mavergreen-payload" "$TREE/.mavergreen-payload" || pl_fail cp
rm -rf "$_plw"
hook_open() { printf '_hk_e=""; case "$-" in *e*) _hk_e=1; set +e ;; esac\n(\n[ -z "$_hk_e" ] || set -e\n:\n'; }
hook_close() { printf '\n)\n_hk_rc=$?\n[ -z "$_hk_e" ] || set -e\n'; }
tree_guard() {
  sed "s/@P@/$P/g" <<'TREEGUARD'
_pl_t="$ROOT/usr/local/mavergreen/@P@"
_pl_tp=""
if [ ! -L "$_pl_t" ]; then _pl_tp="$(cd -P "$_pl_t" 2>/dev/null && pwd -P)" || _pl_tp=""; fi
_pl_ok() {
  case "$1" in ''|/*|*/) return 1 ;; esac
  case "/$1/" in *"/./"*|*"/../"*|*//*) return 1 ;; esac
  case "$1" in */*) _pl_d="/${1%/*}" ;; *) _pl_d="" ;; esac
  [ -n "$_pl_tp" ] && [ "$(cd -P "$_pl_t$_pl_d" 2>/dev/null && pwd -P)" = "$_pl_tp$_pl_d" ]
}
TREEGUARD
}
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: preinstall got no target volume; removing nothing" >&2; exit 0; }\n' "$P"
  printf 'ROOT="${3%%/}"\n'
  if [ -n "$PFSET" ]; then
    sed "s/@P@/$P/g" <<'PREFLIGHT'
PREFLIGHT_DIR="$(cd "$(dirname "$0")" && pwd)/preflight" || { echo "@P@: cannot find the preflight directory beside $0; nothing was changed" >&2; exit 1; }
_pf_err="$(mktemp "${TMPDIR:-/tmp}/@P@-preflight.XXXXXX")" || { echo "@P@: cannot make a temporary file for the preflight; nothing was changed" >&2; exit 1; }
_pf_e=""; case "$-" in *e*) _pf_e=1; set +e ;; esac
(
[ -z "$_pf_e" ] || set -e
:
PREFLIGHT
    cat "$PFH"
    sed "s/@P@/$P/g" <<'PREFLIGHT'

) 2>"$_pf_err"
_pf_rc=$?
[ -z "$_pf_e" ] || set -e
if [ "$_pf_rc" -ne 0 ]; then
  echo "@P@: the new version cannot use this Mac's configuration; nothing was changed" >&2
  cat "$_pf_err" >&2
  rm -f "$_pf_err"
  exit 1
fi
cat "$_pf_err" >&2
rm -f "$_pf_err"
PREFLIGHT
  fi
  if [ -n "$REQ" ]; then
    printf '_reqs_missing=0\n'
    _ifs="$IFS"; IFS="$nl"; set -f
    for r in $REQ; do
      IFS="$_ifs"
      registry_need stage_product repo "$r"; _reqrepo="$REG_V"
      _reqmsg="$NAME needs $r installed first: https://github.com/Mavergreen/$_reqrepo/releases/latest -- install it, then run this installer again."
      printf 'if [ ! -f "$ROOT/usr/local/mavergreen/%s/mavergreen.plist" ]; then\n' "$r"
      printf "  echo '%s' >&2\n" "$(shq "$_reqmsg")"
      printf '  _reqs_missing=1\n'
      printf 'fi\n'
      IFS="$nl"
    done
    IFS="$_ifs"; set +f
    printf '[ "$_reqs_missing" -eq 0 ] || exit 1\n'
  fi
  sed "s/@P@/$P/g" <<'PAYLOADLIST'
_pl_in="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.mavergreen-payload" || _pl_in=""
[ -f "$_pl_in" ] || { echo "@P@: the payload list is missing beside $0; nothing was changed" >&2; exit 1; }
PAYLOADLIST
  tree_guard
  sed "s/@P@/$P/g" <<'LAYPLAN'
_pl_tab="$(printf '\t')"
_pl_nl='
'
_pl_under() {
  _pl_r="$1"
  while :; do
    case "$_pl_r" in */*) _pl_r="${_pl_r%/*}" ;; *) return 1 ;; esac
    case "$_pl_done" in *"$_pl_nl$_pl_r$_pl_nl"*) return 0 ;; esac
  done
}
_pl_plan() {
  [ -r "$_pl_in" ] || return 1
  _pl_done="$_pl_nl"
  while IFS="$_pl_tab" read -r _pl_ty _pl_rel; do
    case "$_pl_ty" in f|l|d) ;; b) _pl_ty=d ;; *) continue ;; esac
    _pl_p="$_pl_t/$_pl_rel"
    if [ -L "$_pl_p" ]; then _pl_is=l
    elif [ -d "$_pl_p" ]; then _pl_is=d
    elif [ -f "$_pl_p" ]; then _pl_is=f
    elif [ -e "$_pl_p" ]; then _pl_is=o
    else continue
    fi
    if [ "$_pl_is" = "$_pl_ty" ] || _pl_under "$_pl_rel"; then continue; fi
    _pl_done="$_pl_done$_pl_rel$_pl_nl"
    printf '/%s\n' "$_pl_rel"
  done < "$_pl_in"
  find "$_pl_t" -mindepth 1 -type d \( -name '*.app' -o -name '*.kext' -o -name '*.prefPane' -o -name '*.plugin' -o -name '*.bundle' -o -name '*.framework' \) -prune -print 2>/dev/null \
    | while IFS= read -r _pl_p; do
    _pl_rel="${_pl_p#"$_pl_t"/}"
    if [ "$_pl_rel" = "$_pl_p" ] || [ -L "$_pl_p" ] || [ ! -d "$_pl_p" ] || _pl_under "$_pl_rel"; then continue; fi
    case "${_pl_rel##*/}" in *.app|*.kext|*.prefPane|*.plugin|*.bundle|*.framework) printf '/%s\n' "$_pl_rel" ;; esac
  done
  return 0
}
_pl_todo="$(_pl_plan)" || { echo "@P@: cannot read the payload list $_pl_in; nothing was changed" >&2; exit 1; }
_pl_bad=0
while IFS= read -r _pl_x; do
  case "$_pl_x" in /*) _pl_rel="${_pl_x#/}" ;; *) continue ;; esac
  if ! _pl_ok "$_pl_rel"; then
    echo "@P@: not removing $_pl_rel -- it does not resolve inside $_pl_t" >&2
    _pl_bad=1
  fi
done <<PLTODO
$_pl_todo
PLTODO
if [ "$_pl_bad" -ne 0 ]; then echo "@P@: the new version cannot be laid over $_pl_t; nothing was changed" >&2; exit 1; fi
LAYPLAN
  printf 'if [ -x "$ROOT/usr/local/bin/mavergreen" ]; then "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" unlink %s 2>/dev/null || true; fi\n' "$P"
  if [ -n "$PREH" ]; then
    hook_open; cat "$PREH"; hook_close
    printf 'if [ "$_hk_rc" -ne 0 ]; then\n'
    printf '  if [ ! -x "$ROOT/usr/local/bin/mavergreen" ] || "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" link %s >/dev/null 2>&1; then\n' "$P"
    printf '    echo "%s: preinstall hook failed; the installed version is left in place" >&2\n' "$P"
    printf '  else\n'
    printf '    echo "%s: preinstall hook failed" >&2\n' "$P"
    printf '    echo '"'"'%s: could not relink; run `mavergreen link %s`'"'"' >&2\n' "$P" "$P"
    printf '  fi\n'
    printf '  exit 1\nfi\n'
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
  sed "s/@P@/$P/g" <<'LAYOVER'
_pl_fail=""
if ! _pl_todo="$(_pl_plan)"; then _pl_fail="cannot read the payload list $_pl_in"; fi
while IFS= read -r _pl_x; do
  [ -z "$_pl_fail" ] || break
  case "$_pl_x" in /*) _pl_rel="${_pl_x#/}" ;; *) continue ;; esac
  _pl_p="$_pl_t/$_pl_rel"
  if [ ! -e "$_pl_p" ] && [ ! -L "$_pl_p" ]; then continue; fi
  if ! _pl_ok "$_pl_rel"; then
    _pl_fail="not removing $_pl_rel -- it does not resolve inside $_pl_t"
  elif ! rm -rf "$_pl_p" 2>/dev/null; then
    _pl_fail="could not remove $_pl_rel, which the payload cannot be laid over"
  fi
done <<PLTODO
$_pl_todo
PLTODO
if [ -n "$_pl_fail" ]; then
  echo "@P@: $_pl_fail" >&2
  if [ ! -x "$ROOT/usr/local/bin/mavergreen" ] || "$ROOT/usr/local/bin/mavergreen" --root "$ROOT/" link @P@ >/dev/null 2>&1; then
    echo "@P@: the upgrade stopped before its payload; the installed version is linked again" >&2
  else
    echo '@P@: could not relink; run `mavergreen link @P@`' >&2
  fi
  exit 1
fi
LAYOVER
  printf 'exit 0\n'
} > "$SCR/preinstall"
{
  printf '#!/bin/sh\n'
  printf '[ -n "${3:-}" ] || { echo "%s: postinstall got no target volume" >&2; exit 1; }\n' "$P"
  printf 'ROOT="${3%%/}"\n'
  tree_guard
  sed "s/@P@/$P/g" <<'PRUNE'
_pl_in="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.mavergreen-payload" || _pl_in=""
_pl_l="$_pl_t/.mavergreen-payload"
if [ ! -s "$_pl_l" ] || [ -L "$_pl_l" ] || [ ! -f "$_pl_in" ] || ! cmp -s "$_pl_l" "$_pl_in"; then
  echo "@P@: the installed tree's payload list is missing, empty or not this package's; nothing was pruned, so files dropped from this version may linger" >&2
else
  _pl_strays() {
    PL_TREE="$_pl_t" awk 'BEGIN { FS = "\t"; n = length(ENVIRON["PL_TREE"]) + 2 }
      FILENAME == ARGV[1] { keep[$2] = 1; next }
      substr($0, 1, n - 1) != (ENVIRON["PL_TREE"] "/") { next }
      { r = substr($0, n) }
      r != "mavergreen.plist" && r != ".mavergreen-payload" && !(r in keep) { print r }' "$_pl_l" -
  }
  find "$_pl_t" -mindepth 1 \( -type f -o -type l \) -print 2>/dev/null | _pl_strays | while IFS= read -r _pl_rel; do
    if [ ! -f "$_pl_t/$_pl_rel" ] && [ ! -L "$_pl_t/$_pl_rel" ]; then continue; fi
    if ! _pl_ok "$_pl_rel"; then
      echo "@P@: not removing $_pl_rel -- it does not resolve inside $_pl_t" >&2
    elif ! rm -f "$_pl_t/$_pl_rel" 2>/dev/null; then
      echo "@P@: could not remove $_pl_rel, which this version no longer carries" >&2
    fi
  done
  find "$_pl_t" -mindepth 1 -depth -type d -print 2>/dev/null | _pl_strays | while IFS= read -r _pl_rel; do
    if [ -L "$_pl_t/$_pl_rel" ] || [ ! -d "$_pl_t/$_pl_rel" ]; then continue; fi
    if _pl_ok "$_pl_rel"; then rmdir "$_pl_t/$_pl_rel" 2>/dev/null || :; fi
  done
fi
PRUNE
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
  if [ -n "$SEEDS" ]; then
    sed "s/@P@/$P/g" <<'SEEDFN'
_seed_rr="$(cd -P "$ROOT/" 2>/dev/null && pwd -P)" || _seed_rr=""
_seed_one() {
  _sv="$ROOT/usr/local/mavergreen/var/@P@/$1"; _stree="$ROOT/usr/local/mavergreen/@P@/$2"
  if [ -e "$_sv" ] || [ -L "$_sv" ]; then return 0; fi
  [ -f "$_stree" ] || { echo "@P@: cannot seed $1: $2 is not in the installed tree" >&2; return 1; }
  [ -n "$_seed_rr" ] || { echo "@P@: not seeding $1 -- $ROOT/ does not resolve to a directory" >&2; return 1; }
  _sa="${_sv%/*}"
  while [ ! -d "$_sa" ]; do _sa="${_sa%/*}"; done
  _spd="$(cd -P "$_sa" 2>/dev/null && pwd -P)" || _spd=""
  case "$_spd/" in
    "${_seed_rr%/}/"?*) ;;
    *) echo "@P@: not seeding $1 -- its directory resolves outside $ROOT/" >&2; return 1 ;;
  esac
  mkdir -p "${_sv%/*}" && cp -p "$_stree" "$_sv" || { echo "@P@: could not seed $1" >&2; return 1; }
  _sh="$(shasum -a 256 < "$_sv")" && _sh="${_sh%% *}" || { echo "@P@: could not checksum $1" >&2; return 1; }
  _srec="$ROOT/usr/local/mavergreen/var/@P@/.mavergreen-seeded"
  _snew="$_srec.new.$$"
  { if [ -f "$_srec" ]; then SEED_PATH="$1" awk 'substr($0, 67) != ENVIRON["SEED_PATH"]' "$_srec"; fi; printf '%s  %s\n' "$_sh" "$1"; } > "$_snew" \
    && mv -f "$_snew" "$_srec" || { rm -f "$_snew"; echo "@P@: could not record the seed of $1" >&2; return 1; }
}
SEEDFN
    _ifs="$IFS"; IFS="$nl"; set -f
    for sd in $SEEDS; do
      IFS="$_ifs"
      printf "_seed_one '%s' '%s' || exit 1\n" "$(shq "${sd%%=*}")" "$(shq "${sd#*=}")"
      IFS="$nl"
    done
    IFS="$_ifs"; set +f
  fi
  sed "s/@P@/$P/g" <<'REREPLACE'
if [ -f "$ROOT/usr/local/mavergreen/var/system-replace/@P@/.replaced" ]; then
  _rr_pv="$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' "$ROOT/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)"
  case "$_rr_pv" in
    10.9|10.9.*) "$MG" --root "$ROOT/" system-replace @P@ || exit 1 ;;
    *) echo "@P@: this volume is no longer Mac OS X 10.9; the System Replace was not re-applied" >&2 ;;
  esac
fi
REREPLACE
  if [ -n "$snippet" ]; then cat "$snippet"; printf '\n'; fi
  if [ -n "$POSTH" ]; then
    hook_open; cat "$POSTH"; hook_close
    printf 'if [ "$_hk_rc" -ne 0 ]; then echo "%s: postinstall hook failed" >&2; exit 1; fi\n' "$P"
  fi
  printf 'exit 0\n'
} > "$SCR/postinstall"
rm -f "$SCR/.agent-load"
for g in "$SCR/preinstall" "$SCR/postinstall"; do
  sh -n "$g" || { echo "stage_product: generated $g is not valid sh (made from preflight hook ${PFH:-none}, preinstall hook ${PREH:-none}, postinstall hook ${POSTH:-none}); refusing to stage" >&2; exit 1; }
done
chmod +x "$SCR/preinstall" "$SCR/postinstall"
