#!/bin/sh
# platform: host-agnostic -- PlistBuddy reads each manifest where there is one, else stevedore (STEVEDORE, on
#   PATH, or fetch_stevedore.sh beside this script); launchctl runs only for the boot volume, pkgutil only where present
#   usage: mavergreen [--root VOLUME] <command> [args]
#            link <product>               export a product's commands and manpages
#            unlink <product>             remove them (never changes a selection)
#            select <group> [<product>]   show or change which member owns the bare names
#            list                         installed products, groups, lines, selections
#            check                        verify the farm's links and manifests; problems to stderr
#            uninstall <product>          remove it, its farm links, and what its manifest lists as outside or generated
#            system-replace <product>     swap the manifest's :replaces system paths for links into the tree (10.9 only)
#            system-restore <product>     put those system paths back
#            slim status|on|off           show or set thinning of installed products to this Mac's arches
#            slim apply <product>         thin one product now (every product's postinstall calls this)
#            version                      print the mavergreen helper's stamped version
# spec: tests/mavergreen-helper-test.sh
set -eu
# spec: tests/product-names-test.sh -- a name is lowercase ASCII; a UTF-8 locale can collate [a-z] to
#       admit uppercase in case patterns and awk ranges, so names are matched in the C locale.
LC_ALL=C; export LC_ALL
MAVERGREEN_VERSION="@MAVERGREEN_VERSION@"
PB="${MAVERGREEN_PLISTBUDDY:-/usr/libexec/PlistBuddy}"
SD=""
ROOT=/
if [ "${1:-}" = --root ]; then ROOT="${2:?mavergreen: --root needs a volume}"; shift 2; fi
R="${ROOT%/}"
MG="$R/usr/local/mavergreen"
SEL="$MG/var/mavergreen/selections"

die() { echo "mavergreen: $1" >&2; exit "${2:-1}"; }
valid() { case "$1" in ''|-*|*[!a-z0-9-]*|var|bin|sbin|share|mavergreen|system-replace|base) return 1 ;; esac; }
manifest() { printf '%s/%s/mavergreen.plist' "$MG" "$1"; }
pl_get() {
  if [ -z "$SD" ]; then "$PB" -c "Print :$2" "$1" 2>/dev/null; else "$SD" plist get "$1" "$2" 2>/dev/null; fi
}
pick_reader() {
  [ ! -x "$PB" ] || return 0
  if [ -n "${STEVEDORE:-}" ]; then
    [ -x "$STEVEDORE" ] || die "STEVEDORE is $STEVEDORE, which is not executable"
    SD="$STEVEDORE"; return 0
  fi
  SD="$(command -v stevedore 2>/dev/null || :)"
  [ -z "$SD" ] || return 0
  _fs="$(dirname "$0")/fetch_stevedore.sh"
  if [ -f "$_fs" ]; then SD="$(sh "$_fs" 2>/dev/null || :)"; fi
  [ -n "$SD" ] || die "no $PB to read manifests with, and no stevedore: set STEVEDORE, or put stevedore on PATH"
}
mf() { pl_get "$(manifest "$1")" "$2" || true; }
mf_array() {
  _i=0
  while _v="$(pl_get "$(manifest "$1")" "$2:$_i")"; do
    printf '%s\n' "$_v"; _i=$((_i + 1))
  done
}
need_product() {
  valid "$1" || die "not a product name: '$1'" 2
  [ -f "$(manifest "$1")" ] || die "$1 is not installed (no $(manifest "$1"))"
}
group_of() { _g="$(mf "$1" group)"; printf '%s' "${_g:-$1}"; }
selection() { cat "$SEL/$1" 2>/dev/null || true; }
set_selection() { mkdir -p "$SEL"; printf '%s\n' "$2" > "$SEL/$1"; }
installed() { for _m in "$MG"/*/mavergreen.plist; do if [ -f "$_m" ]; then basename "$(dirname "$_m")"; fi; done; }

exports() {
  _ex="$(mf_array "$1" exports-exclude)"
  ( cd "$MG/$1" && for _f in bin/* sbin/* share/man/man*/*; do
      if [ -f "$_f" ] || [ -L "$_f" ]; then printf '%s\n' "$_f"; fi
    done ) | while IFS= read -r _f; do
    printf '%s\n' "$_ex" | grep -qxF -- "$_f" || printf '%s\n' "$_f"
  done
}
versioned() {
  _d="${1%/*}"; _b="${1##*/}"
  case "$_d" in
    share/man/*) _n="${_b%%.*}"; printf '%s/%s-%s%s' "$_d" "$_n" "$2" "${_b#"$_n"}" ;;
    *) printf '%s/%s-%s' "$_d" "$_b" "$2" ;;
  esac
}
up() { printf '%s' "${1%/*}" | awk -F/ '{ for (i = 1; i <= NF; i++) printf "../" }'; }
owner() {
  _t="$(readlink "$1")"
  while case "$_t" in ../*) true ;; *) false ;; esac; do _t="${_t#../}"; done
  printf '%s' "${_t%%/*}"
}

plan_links() {
  _line="$(mf "$1" line)"
  exports "$1" | while IFS= read -r _rel; do
    if [ -n "$_line" ]; then printf '%s\t%s\n' "$(versioned "$_rel" "$_line")" "$_rel"; fi
    if [ "$2" = bare ]; then printf '%s\t%s\n' "$_rel" "$_rel"; fi
  done
}
refusals() {
  _g="$(group_of "$1")"
  printf '%s\n' "$2" | while IFS="	" read -r _link _rel; do
    [ -n "$_link" ] || continue
    _full="$MG/$_link"
    [ -L "$_full" ] || { [ ! -e "$_full" ] || echo "$_link exists and is not a mavergreen link"; continue; }
    _o="$(owner "$_full")"
    [ "$_o" = "$1" ] && continue
    [ -f "$(manifest "$_o")" ] && [ "$(group_of "$_o")" = "$_g" ] && [ "$_link" = "$_rel" ] \
      && [ "$(readlink "$_full")" = "$(up "$_link")$_o/$_link" ] && continue
    echo "$_link is owned by $_o"
  done
}
place() {
  printf '%s\n' "$2" | while IFS="	" read -r _link _rel; do
    [ -n "$_link" ] || continue
    mkdir -p "$MG/${_link%/*}"
    rm -f "$MG/$_link"
    ln -s "$(up "$_link")$1/$_rel" "$MG/$_link"
  done
}
farm_dirs() {
  printf '%s\n' bin sbin
  for _d in "$MG"/share/man/man*; do
    if [ -d "$_d" ]; then printf 'share/man/%s\n' "$(basename "$_d")"; fi
  done
}
unlink_product() {
  farm_dirs | while IFS= read -r _d; do
    for _l in "$MG/$_d"/*; do
      if [ -L "$_l" ] && [ "$(owner "$_l")" = "$1" ]; then rm -f "$_l"; fi
    done
  done
}
unlink_bare_of_group() {
  for _o in $(installed); do
    [ "$(group_of "$_o")" = "$1" ] || continue
    exports "$_o" | while IFS= read -r _rel; do
      if [ -L "$MG/$_rel" ] && [ "$(owner "$MG/$_rel")" = "$_o" ]; then rm -f "$MG/$_rel"; fi
    done
  done
}

do_link() {
  need_product "$1"
  _g="$(group_of "$1")"; _s="$(selection "$_g")"
  if [ -z "$_s" ] || [ ! -f "$(manifest "$_s")" ]; then _s="$1"; fi
  _mode=versioned; [ "$_s" = "$1" ] && _mode=bare
  _plan="$(plan_links "$1" "$_mode")"
  _bad="$(refusals "$1" "$_plan")"
  [ -z "$_bad" ] || die "refusing to link $1: $(printf '%s' "$_bad" | tr '\n' ';')"
  if [ "$_s" = "$1" ]; then set_selection "$_g" "$1"; fi
  place "$1" "$_plan"
}
do_unlink() { need_product "$1"; unlink_product "$1"; }
do_select() {
  valid "$1" || die "not a group name: '$1'" 2
  if [ -z "${2:-}" ]; then selection "$1"; return 0; fi
  need_product "$2"
  [ "$(group_of "$2")" = "$1" ] || die "$2 is in group $(group_of "$2"), not $1"
  _plan="$(plan_links "$2" bare)"
  _bad="$(refusals "$2" "$_plan")"
  [ -z "$_bad" ] || die "refusing to select $2: $(printf '%s' "$_bad" | tr '\n' ';')"
  unlink_bare_of_group "$1"
  set_selection "$1" "$2"
  place "$2" "$_plan"
}
do_list() {
  installed | while IFS= read -r _p; do
    _g="$(group_of "$_p")"; _l="$(mf "$_p" line)"
    _mark=""; [ "$(selection "$_g")" = "$_p" ] && _mark=selected
    printf '%s %s %s %s %s\n' "$_p" "$_g" "${_l:--}" "$(mf "$_p" version)" "$_mark" | sed 's/ *$//'
  done
}

do_check() {
  _n=0
  for _d in $(farm_dirs); do
    for _l in "$MG/$_d"/*; do
      [ -L "$_l" ] || continue
      if [ ! -e "$_l" ]; then echo "mavergreen: dangling link ${_l#"$MG/"}" >&2; _n=$((_n + 1)); continue; fi
      _o="$(owner "$_l")"
      [ -f "$(manifest "$_o")" ] || { echo "mavergreen: ${_l#"$MG/"} points into $_o, which has no manifest" >&2; _n=$((_n + 1)); }
    done
  done
  for _p in $(installed); do
    [ "$(mf "$_p" product)" = "$_p" ] || { echo "mavergreen: $_p's manifest names product '$(mf "$_p" product)'" >&2; _n=$((_n + 1)); }
    _mode=versioned; [ "$(selection "$(group_of "$_p")")" = "$_p" ] && _mode=bare
    _missing="$(plan_links "$_p" "$_mode" | while IFS="	" read -r _link _rel; do
      [ -L "$MG/$_link" ] && [ "$(owner "$MG/$_link")" = "$_p" ] || echo "$_link"; done)"
    [ -z "$_missing" ] || { echo "mavergreen: $_p is missing links: $(printf '%s' "$_missing" | tr '\n' ' ')" >&2; _n=$((_n + 1)); }
    if [ -f "$MG/var/system-replace/$_p/.replaced" ]; then need_pb check; _n=$((_n + $(replace_drift "$_p"))); fi
  done
  [ "$_n" -eq 0 ]
}
need_pb() { [ -z "$SD" ] || die "$1 reads the manifest's :replaces dict, which needs $PB; stevedore reads only scalars"; }
replaces() {
  "$PB" -c "Print :replaces" "$(manifest "$1")" 2>/dev/null \
    | sed -n 's/^[[:space:]]*\(\/[^ =]*\) = \(.*\)$/\1	\2/p'
}
replace_shape_ok() {
  case "$1" in /*) : ;; *) return 1 ;; esac
  case "/$1/" in *"/./"*|*"/../"*) return 1 ;; esac
  case "$2" in ''|/*) return 1 ;; esac
  case "/$2/" in *"/./"*|*"/../"*) return 1 ;; esac
  return 0
}
owns_replace_link() {
  if [ -L "$1" ]; then
    case "$(readlink "$1")" in
      "$2"*) return 0 ;;
    esac
  fi
  return 1
}
is_real_dir() {
  [ -d "$1" ] || return 1
  [ ! -L "$1" ]
}
do_system_replace() {
  need_product "$1"
  need_pb system-replace
  _pv="$(pl_get "$R/System/Library/CoreServices/SystemVersion.plist" ProductVersion || true)"
  case "$_pv" in
    10.9|10.9.*) : ;;
    *) die "system-replace is 10.9-only; this volume is macOS ${_pv:-unknown}, where /usr/bin belongs to the sealed system volume" ;;
  esac
  _b="$MG/var/system-replace/$1"
  _entries="$(replaces "$1")"
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    replace_shape_ok "$_abs" "$_rel" || die "$1 declares an unsafe replaces entry: '$_abs' -> '$_rel'"
    [ -e "$MG/$1/$_rel" ] || die "$1 declares $_abs -> $_rel, but $_rel is not in its tree"
    is_real_dir "$MG/$1/$_rel" \
      && die "$1 declares $_abs -> $_rel, but $_rel is a directory; system-replace swaps files and symlinks only"
    _want="/usr/local/mavergreen/$1/$_rel"; _cur="$R$_abs"
    is_real_dir "$_cur" \
      && die "$1 declares $_abs -> $_rel, but $_abs is a directory; system-replace swaps files and symlinks only"
    if [ -L "$_cur" ] && [ "$(readlink "$_cur")" = "$_want" ]; then continue; fi
    if [ -e "$_b$_abs" ] || [ -L "$_b$_abs" ]; then
      die "$_abs was already saved once and has since changed; run system-restore $1 first"
    fi
  done <<EOF
$_entries
EOF
  mkdir -p "$_b"; : > "$_b/.replaced"
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    _want="/usr/local/mavergreen/$1/$_rel"; _cur="$R$_abs"
    if [ -L "$_cur" ] && [ "$(readlink "$_cur")" = "$_want" ]; then continue; fi
    if [ -e "$_cur" ] || [ -L "$_cur" ]; then
      mkdir -p "$(dirname "$_b$_abs")"; mv "$_cur" "$_b$_abs"
    fi
    mkdir -p "$(dirname "$_cur")"; ln -s "$_want" "$_cur"
  done <<EOF
$_entries
EOF
}
do_system_restore() {
  need_product "$1"
  need_pb system-restore
  _b="$MG/var/system-replace/$1"
  _entries="$(replaces "$1")"
  _want_prefix="/usr/local/mavergreen/$1/"
  _rfail=0
  _saved=""
  if [ -d "$_b" ]; then
    _saved="$(cd "$_b" && find . -mindepth 1 \( -type f -o -type l \) ! -name .replaced | sed 's|^\./||')"
  fi
  while IFS= read -r _relpath; do
    [ -n "$_relpath" ] || continue
    _abs="/$_relpath"; _cur="$R$_abs"
    if owns_replace_link "$_cur" "$_want_prefix"; then rm -f "$_cur" 2>/dev/null || true; fi
    if [ -e "$_cur" ] || [ -L "$_cur" ]; then
      echo "mavergreen: $_abs still exists after removing $1's link; keeping the saved original" >&2
      _rfail=1
      continue
    fi
    mkdir -p "$(dirname "$_cur")"
    mv "$_b$_abs" "$_cur" || { echo "mavergreen: could not restore $_abs" >&2; _rfail=1; }
  done <<EOF
$_saved
EOF
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    if [ -e "$_b$_abs" ] || [ -L "$_b$_abs" ]; then continue; fi
    if ! replace_shape_ok "$_abs" "$_rel"; then
      echo "mavergreen: $1's replaces entry '$_abs' -> '$_rel' is unsafe; not touching it" >&2
      _rfail=1
      continue
    fi
    _cur="$R$_abs"
    if owns_replace_link "$_cur" "$_want_prefix"; then
      rm -f "$_cur" || { echo "mavergreen: could not remove $_abs" >&2; _rfail=1; }
    fi
  done <<EOF
$_entries
EOF
  if [ "$_rfail" -eq 0 ]; then rm -rf "$_b"; fi
  [ "$_rfail" -eq 0 ]
}
replace_drift() {
  _msgs="$(replaces "$1" | while IFS="	" read -r _abs _rel; do
    if [ -L "$R$_abs" ] && [ "$(readlink "$R$_abs")" = "/usr/local/mavergreen/$1/$_rel" ]; then :; else
      echo "mavergreen: $_abs is no longer $1's replacement"; fi
  done)"
  if [ -z "$_msgs" ]; then echo 0; return 0; fi
  printf '%s\n' "$_msgs" >&2
  printf '%s\n' "$_msgs" | wc -l | tr -d ' '
}
unload() {
  [ -z "$R" ] || return 0
  command -v launchctl >/dev/null 2>&1 || return 0
  case "$1" in
    # platform: guarded macOS-only call -- unload returns first unless the root is / and launchctl exists
    Library/LaunchDaemons/*.plist) launchctl unload -w "/$1" 2>/dev/null || true ;;
    Library/LaunchAgents/*.plist)
      _u="$(stat -f %Su /dev/console 2>/dev/null || echo root)"
      # platform: guarded macOS-only call -- unload returns first unless the root is / and launchctl exists
      [ "$_u" = root ] || sudo -u "$_u" launchctl unload -w "/$1" 2>/dev/null || true ;;
  esac
}
outside_shape_ok() {
  case "$1" in ''|/*|*/|*//*) return 1 ;; esac
  case "/$1/" in *"/./"*|*"/../"*) return 1 ;; esac
  case "$1" in usr/local/mavergreen|usr/local/mavergreen/*) return 1 ;; esac
  return 0
}
parent_in_root() {
  _pr_dir="$(dirname "$1")"
  [ -d "$_pr_dir" ] || return 2
  _pr_real="$(cd -P "$_pr_dir" 2>/dev/null && pwd -P)" || return 1
  _pr_root="$(cd -P "$R/" 2>/dev/null && pwd -P)" || return 1
  case "$_pr_real/" in "${_pr_root%/}/"*) return 0 ;; esac
  return 1
}
remove_outside() {
  _full="$R/$1"
  _pi=0; parent_in_root "$_full" || _pi=$?
  [ "$_pi" -ne 2 ] || return 0
  [ "$_pi" -eq 0 ] || { echo "mavergreen: refusing to remove $1 -- its parent directory resolves outside $ROOT" >&2; return 1; }
  if [ -L "$_full" ] || [ -f "$_full" ]; then
    unload "$1"
    rm -f "$_full" || { echo "mavergreen: could not remove $1" >&2; return 1; }
    return 0
  fi
  if [ -d "$_full" ]; then
    case "$(basename "$_full")" in
      *.app|*.kext|*.prefPane|*.plugin|*.bundle|*.framework|*.jdk)
        unload "$1"
        rm -rf "$_full" || { echo "mavergreen: could not remove $1" >&2; return 1; }
        return 0 ;;
      *)
        echo "mavergreen: refusing to remove $1 -- not an app/plugin bundle" >&2
        return 1 ;;
    esac
  fi
  return 0
}
remove_listed() {
  _rl_rc=0
  _rl_entries="$(mf_array "$1" "$2")"
  while IFS= read -r _o; do
    [ -n "$_o" ] || continue
    if outside_shape_ok "$_o"; then
      remove_outside "$_o" || _rl_rc=1
    else
      echo "mavergreen: refusing to remove unsafe $2 path '$_o'" >&2
      _rl_rc=1
    fi
  done <<EOF
$_rl_entries
EOF
  return "$_rl_rc"
}
run_pre_uninstall_hook() {
  _puh="$MG/$1/libexec/mavergreen/pre-uninstall"
  _puh_pi=0; parent_in_root "$_puh" || _puh_pi=$?
  case "$_puh_pi" in
    2) return 0 ;;
    0) ;;
    *) die "refusing to run $1's pre-uninstall hook ($_puh) -- its parent directory resolves outside $ROOT" ;;
  esac
  if [ -L "$_puh" ]; then
    die "refusing to run $1's pre-uninstall hook ($_puh) -- it is a symlink, and a hook is never a link into the payload"
  fi
  [ -e "$_puh" ] || return 0
  [ -x "$_puh" ] \
    || die "$1's pre-uninstall hook ($_puh) exists but is not executable; uninstall stopped, nothing removed"
  _puh_rc=0
  trap : INT
  MAVERGREEN_ROOT="$ROOT" MAVERGREEN_PRODUCT="$1" "$_puh" || _puh_rc=$?
  trap - INT
  [ "$_puh_rc" -eq 0 ] || {
    if [ "$_puh_rc" -gt 128 ]; then
      die "$1's pre-uninstall hook ($_puh) was cancelled (status $_puh_rc); uninstall stopped, nothing removed" "$_puh_rc"
    else
      die "$1's pre-uninstall hook ($_puh) failed (status $_puh_rc); uninstall stopped, nothing removed" "$_puh_rc"
    fi
  }
}
phys_path() {
  _pp="$1"; _ps=""
  while [ "${_pp%/}" != "$_pp" ]; do _pp="${_pp%/}"; done
  while [ -n "$_pp" ] && [ ! -d "$_pp" ]; do
    _ps="/${_pp##*/}$_ps"; _pp="${_pp%/*}"
  done
  [ -n "$_pp" ] || _pp=/
  _pd="$(cd -P "$_pp" 2>/dev/null && pwd -P)" || return 1
  printf '%s%s' "${_pd%/}" "$_ps"
}
links_into() {
  _li_links="$(find "$MG/$1" -type l 2>/dev/null)"
  [ -n "$_li_links" ] || return 1
  while IFS= read -r _l; do
    _t="$(readlink "$_l")" || continue
    case "$_t" in /*) ;; *) _t="$(dirname "$_l")/$_t" ;; esac
    _t="$(phys_path "$_t")" || continue
    case "$_t/" in "$2/"*) return 0 ;; esac
  done <<EOL
$_li_links
EOL
  return 1
}
refuse_if_depended_on() {
  _real="$(phys_path "$MG/$1")" || return 0
  _deps=""
  for _q in $(installed); do
    [ "$_q" != "$1" ] || continue
    if links_into "$_q" "$_real"; then _deps="$_deps $_q"; fi
  done
  [ -z "$_deps" ] && return 0
  {
    echo "mavergreen: not uninstalling $1 -- other products link into it, and would be left dangling. Uninstall them first:"
    for _q in $_deps; do echo "sudo mavergreen uninstall $_q"; done
  } >&2
  exit 1
}
do_uninstall() {
  need_product "$1"
  if [ -f "$MG/var/system-replace/$1/.replaced" ]; then need_pb "uninstalling a system-replaced product"; fi
  refuse_if_depended_on "$1"
  run_pre_uninstall_hook "$1"
  if [ -f "$MG/var/system-replace/$1/.replaced" ]; then
    do_system_restore "$1" \
      || die "system-restore failed for $1; uninstall stopped before removing anything else -- fix it, then retry"
  fi
  _g="$(group_of "$1")"; _id="$(mf "$1" identifier)"
  _failed=0
  unlink_product "$1"
  remove_listed "$1" outside || _failed=1
  remove_listed "$1" generated || _failed=1
  rm -f "$MG/var/mavergreen/slimmed/$1"
  for _d in "$MG/$1" "$MG/var/$1"; do
    _pi=0; parent_in_root "$_d" || _pi=$?
    case "$_pi" in
      0) rm -rf "$_d" || { echo "mavergreen: could not remove $_d" >&2; _failed=1; } ;;
      2) ;;
      *) echo "mavergreen: refusing to remove $_d -- its parent directory resolves outside $ROOT" >&2; _failed=1 ;;
    esac
  done
  if [ "$(selection "$_g")" = "$1" ]; then
    _left="$(for _p in $(installed); do if [ "$(group_of "$_p")" = "$_g" ]; then echo "$_p"; fi; done)"
    if [ -n "$_left" ] && [ "$(printf '%s\n' "$_left" | wc -l | tr -d ' ')" -eq 1 ]; then
      set_selection "$_g" "$_left"; place "$_left" "$(plan_links "$_left" bare)"
    else
      rm -f "$SEL/$_g"
    fi
  fi
  if [ -n "$_id" ] && command -v pkgutil >/dev/null 2>&1; then
    # platform: guarded macOS-only call -- only where command -v finds pkgutil
    pkgutil --volume "$ROOT" --forget "$_id" >/dev/null 2>&1 || true
  fi
  [ "$_failed" -eq 0 ]
}
slim_host_arch() {
. "$(dirname "$0")/lib/host-arch.sh"
mavergreen_host_arch
}
slim_dir() { printf '%s/var/mavergreen' "$MG"; }
slim_setting() {  # $1 host arch: prints "on|off" then why, tab-separated
  _s="$(cat "$(slim_dir)/slim" 2>/dev/null || true)"
  case "$_s" in
    on|off) printf '%s\tset with mavergreen slim %s\n' "$_s" "$_s" ;;
    *) if [ "$1" = arm64 ]; then printf 'off\tthe default on an arm64 Mac\n'; else printf 'on\tthe default on an x86_64 Mac\n'; fi ;;
  esac
}
slim_hex() {  # $1 file  $2 offset  $3 count: that many bytes as lowercase hex, no spaces
  od -An -tx1 -j "$2" -N "$3" "$1" 2>/dev/null | tr -d ' \n'
}
slim_kept_by_manifest() {  # $1 relative path; $_keep holds the globs, one per line
  [ -n "$_keep" ] || return 1
  printf '%s\n' "$_keep" | { while IFS= read -r _g; do
    case "$1" in $_g) exit 0 ;; esac
  done; exit 1; }
}
slim_file() {  # $1 file  $2 host arch: prints thin, rm or nothing; thins or removes it
  _m="$(slim_hex "$1" 0 4)"
  case "$_m" in
    cafebabe)
      _n=$((0x$(slim_hex "$1" 4 4)))
      [ "$_n" -ge 1 ] && [ "$_n" -le 30 ] || return 0
      _hdr="$(slim_hex "$1" 8 $((20 * _n)))"
      _i=0; _has_x86=""; _has_i386=""; _has_arm=""; _other=0
      while [ "$_i" -lt "$_n" ]; do
        _c="$(printf '%s' "$_hdr" | cut -c$((_i * 40 + 1))-$((_i * 40 + 8)))"
        _o=$((0x$(printf '%s' "$_hdr" | cut -c$((_i * 40 + 17))-$((_i * 40 + 24)))))
        [ "$(slim_hex "$1" "$_o" 4)" != 213c6172 ] || return 0
        case "$_c" in
          01000007) _has_x86=1 ;;
          00000007) _has_i386=1 ;;
          0100000c) _has_arm=1 ;;
          *) _other=$((_other + 1)) ;;
        esac
        _i=$((_i + 1))
      done
      _keepargs=""; _nk=0
      if [ "$2" = arm64 ]; then
        if [ -n "$_has_arm" ]; then _keepargs="--arch arm64"; _nk=1; fi
      else
        if [ -n "$_has_x86" ]; then _keepargs="--arch x86_64"; _nk=$((_nk + 1)); fi
        if [ -n "$_has_i386" ]; then _keepargs="$_keepargs --arch i386"; _nk=$((_nk + 1)); fi
      fi
      if [ "$_nk" -eq 0 ]; then
        [ "$2" = x86_64 ] || return 0
        rm -f "$1" || die "could not remove $1"
        echo rm; return 0
      fi
      [ "$_nk" -lt "$_n" ] || return 0
      # shellcheck disable=SC2086
      "${MAVERGREEN_DITTO:-/usr/bin/ditto}" $_keepargs "$1" "$1.mavergreen-slim" \
        && mv -f "$1.mavergreen-slim" "$1" \
        || { rm -f "$1.mavergreen-slim"; die "could not thin $1"; }
      echo thin ;;
    cffaedfe|cefaedfe)
      [ "$2" = x86_64 ] || return 0
      [ "$(slim_hex "$1" 4 4)" = 0c000001 ] || return 0
      rm -f "$1" || die "could not remove $1"
      echo rm ;;
  esac
}
slim_tree() {  # $1 product  $2 host arch: thins $MG/$1, prints the count of files changed
  _keep="$(mf_array "$1" slim-keep)"
  _lst="$(mktemp "${TMPDIR:-/tmp}/mavergreen-slim.XXXXXX")"
  find "$MG/$1" -type f > "$_lst"
  _cnt=0
  while IFS= read -r _f; do
    _rel="${_f#"$MG/$1/"}"
    if slim_kept_by_manifest "$_rel"; then continue; fi
    _r="$(slim_file "$_f" "$2")" || { rm -f "$_lst"; exit 1; }
    if [ -n "$_r" ]; then _cnt=$((_cnt + 1)); fi
  done < "$_lst"
  rm -f "$_lst"
  printf '%s\n' "$_cnt"
}
slim_apply() {  # $1 product  $2 host arch
  need_product "$1"
  _eff="$(slim_setting "$2")"; _eff="${_eff%%	*}"
  if [ "$_eff" = off ]; then rm -f "$(slim_dir)/slimmed/$1"; return 0; fi
  _n="$(slim_tree "$1" "$2")" || exit $?
  if [ "$_n" -gt 0 ]; then
    mkdir -p "$(slim_dir)/slimmed"; printf '%s\n' "$2" > "$(slim_dir)/slimmed/$1"
  fi
  echo "mavergreen: slimmed $_n files in $1 to $2"
}
do_slim() {
  [ $# -ge 1 ] || die "usage: mavergreen slim status|on|off|apply <product>" 2
  if [ -z "${MAVERGREEN_HOST_ARCH:-}" ] && [ "$(uname -s)" != Darwin ]; then die "slimming is for a Mac"; fi
  _ha="$(slim_host_arch)" || exit 2
  _sub="$1"; shift
  case "$_sub" in
    status)
      _st="$(slim_setting "$_ha")"
      printf 'slim: %s, %s\n' "${_st%%	*}" "${_st#*	}" ;;
    on)
      mkdir -p "$(slim_dir)"; printf 'on\n' > "$(slim_dir)/slim"
      pick_reader
      for _p in $(installed); do slim_apply "$_p" "$_ha"; done ;;
    off)
      mkdir -p "$(slim_dir)"; printf 'off\n' > "$(slim_dir)/slim"
      _done="$(ls "$(slim_dir)/slimmed" 2>/dev/null | tr '\n' ' ')"; _done="${_done% }"
      if [ -n "$_done" ]; then echo "mavergreen: slimming is off; reinstall these to restore their other slices: $_done"
      else echo "mavergreen: slimming is off; nothing installed was slimmed"; fi ;;
    apply)
      [ $# -eq 1 ] || die "usage: mavergreen slim apply <product>" 2
      pick_reader
      slim_apply "$1" "$_ha" ;;
    *) die "usage: mavergreen slim status|on|off|apply <product>" 2 ;;
  esac
}
do_version() { printf '%s\n' "$MAVERGREEN_VERSION"; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in link|unlink|select|list|check|uninstall|system-replace|system-restore) pick_reader ;; esac
case "$cmd" in
  link) [ $# -eq 1 ] || die "usage: mavergreen link <product>" 2; do_link "$1" ;;
  unlink) [ $# -eq 1 ] || die "usage: mavergreen unlink <product>" 2; do_unlink "$1" ;;
  select) [ $# -ge 1 ] || die "usage: mavergreen select <group> [<product>]" 2; do_select "$@" ;;
  list) do_list ;;
  check) do_check ;;
  uninstall) [ $# -eq 1 ] || die "usage: mavergreen uninstall <product>" 2; do_uninstall "$1" ;;
  system-replace) [ $# -eq 1 ] || die "usage: mavergreen system-replace <product>" 2; do_system_replace "$1" ;;
  system-restore) [ $# -eq 1 ] || die "usage: mavergreen system-restore <product>" 2; do_system_restore "$1" ;;
  slim) do_slim "$@" ;;
  version) do_version ;;
  *) die "usage: mavergreen [--root VOLUME] link|unlink|select|list|check|uninstall|system-replace|system-restore|slim|version ..." 2 ;;
esac
