#!/bin/sh
#   usage: mavergreen [--root VOLUME] <command> [args]
#            link <product>               export a product's commands and manpages
#            unlink <product>             remove them (never changes a selection)
#            select <group> [<product>]   show or change which member owns the bare names
#            list                         installed products, groups, lines, selections
#            check                        verify the farm's links and manifests; problems to stderr
#            uninstall <product>          remove it, its farm links, and what its manifest owns outside the tree
#            system-replace <product>     swap the manifest's :replaces system paths for links into the tree (10.9 only)
#            system-restore <product>     put those system paths back
#            version                      print the mavergreen helper's stamped version
# spec: tests/mavergreen-helper-test.sh
set -eu
MAVERGREEN_VERSION="@MAVERGREEN_VERSION@"
PB=/usr/libexec/PlistBuddy
ROOT=/
if [ "${1:-}" = --root ]; then ROOT="${2:?mavergreen: --root needs a volume}"; shift 2; fi
R="${ROOT%/}"
MG="$R/usr/local/mavergreen"
SEL="$MG/var/mavergreen/selections"

die() { echo "mavergreen: $1" >&2; exit "${2:-1}"; }
valid() { case "$1" in ''|-*|*[!a-z0-9-]*|var|bin|sbin|share|mavergreen|system-replace|base) return 1 ;; esac; }
manifest() { printf '%s/%s/mavergreen.plist' "$MG" "$1"; }
mf() { "$PB" -c "Print :$2" "$(manifest "$1")" 2>/dev/null || true; }
mf_array() {
  _i=0
  while _v="$("$PB" -c "Print :$2:$_i" "$(manifest "$1")" 2>/dev/null)"; do
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
    [ -f "$(manifest "$_o")" ] && [ "$(group_of "$_o")" = "$_g" ] && [ "$_link" = "$_rel" ] && continue
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
    if [ -f "$MG/var/system-replace/$_p/.replaced" ]; then _n=$((_n + $(replace_drift "$_p"))); fi
  done
  [ "$_n" -eq 0 ]
}
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
  _pv="$("$PB" -c 'Print :ProductVersion' "$R/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)"
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
  case "$1" in
    Library/LaunchDaemons/*.plist) launchctl unload -w "/$1" 2>/dev/null || true ;;
    Library/LaunchAgents/*.plist)
      _u="$(stat -f %Su /dev/console 2>/dev/null || echo root)"
      [ "$_u" = root ] || sudo -u "$_u" launchctl unload -w "/$1" 2>/dev/null || true ;;
  esac
}
outside_shape_ok() {
  case "$1" in ''|/*) return 1 ;; esac
  case "/$1/" in *"/./"*|*"/../"*) return 1 ;; esac
  case "$1" in usr/local/mavergreen|usr/local/mavergreen/*) return 1 ;; esac
  return 0
}
remove_outside() {
  _full="$R/$1"
  if [ -L "$_full" ] || [ -f "$_full" ]; then
    unload "$1"
    rm -f "$_full" || { echo "mavergreen: could not remove $1" >&2; return 1; }
    return 0
  fi
  if [ -d "$_full" ]; then
    case "$(basename "$_full")" in
      *.app|*.kext|*.prefPane|*.plugin|*.bundle|*.framework)
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
do_uninstall() {
  need_product "$1"
  if [ -f "$MG/var/system-replace/$1/.replaced" ]; then
    do_system_restore "$1" \
      || die "system-restore failed for $1; uninstall stopped before removing anything else -- fix it, then retry"
  fi
  _g="$(group_of "$1")"; _id="$(mf "$1" identifier)"
  _failed=0
  unlink_product "$1"
  _outside="$(mf_array "$1" outside)"
  while IFS= read -r _o; do
    [ -n "$_o" ] || continue
    if outside_shape_ok "$_o"; then
      remove_outside "$_o" || _failed=1
    else
      echo "mavergreen: refusing to remove unsafe outside path '$_o'" >&2
      _failed=1
    fi
  done <<EOF
$_outside
EOF
  rm -rf "$MG/$1" "$MG/var/$1" || { echo "mavergreen: could not remove $1's tree" >&2; _failed=1; }
  if [ "$(selection "$_g")" = "$1" ]; then
    _left="$(for _p in $(installed); do if [ "$(group_of "$_p")" = "$_g" ]; then echo "$_p"; fi; done)"
    if [ -n "$_left" ] && [ "$(printf '%s\n' "$_left" | wc -l | tr -d ' ')" -eq 1 ]; then
      set_selection "$_g" "$_left"; place "$_left" "$(plan_links "$_left" bare)"
    else
      rm -f "$SEL/$_g"
    fi
  fi
  [ -z "$_id" ] || pkgutil --volume "$ROOT" --forget "$_id" >/dev/null 2>&1 || true
  [ "$_failed" -eq 0 ]
}
do_version() { printf '%s\n' "$MAVERGREEN_VERSION"; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  link) [ $# -eq 1 ] || die "usage: mavergreen link <product>" 2; do_link "$1" ;;
  unlink) [ $# -eq 1 ] || die "usage: mavergreen unlink <product>" 2; do_unlink "$1" ;;
  select) [ $# -ge 1 ] || die "usage: mavergreen select <group> [<product>]" 2; do_select "$@" ;;
  list) do_list ;;
  check) do_check ;;
  uninstall) [ $# -eq 1 ] || die "usage: mavergreen uninstall <product>" 2; do_uninstall "$1" ;;
  system-replace) [ $# -eq 1 ] || die "usage: mavergreen system-replace <product>" 2; do_system_replace "$1" ;;
  system-restore) [ $# -eq 1 ] || die "usage: mavergreen system-restore <product>" 2; do_system_restore "$1" ;;
  version) do_version ;;
  *) die "usage: mavergreen [--root VOLUME] link|unlink|select|list|check|uninstall|system-replace|system-restore|version ..." 2 ;;
esac
