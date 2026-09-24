#!/bin/sh
#   usage: mavergreen [--root VOLUME] <command> [args]
#            link <product>               export a product's commands and manpages
#            unlink <product>             remove them (never changes a selection)
#            select <group> [<product>]   show or change which member owns the bare names
#            list                         installed products, groups, lines, selections
# spec: docs/superpowers/specs/2026-09-24-install-layout-design.md
set -eu
MAVERGREEN_VERSION="@MAVERGREEN_VERSION@"
PB=/usr/libexec/PlistBuddy
ROOT=/
if [ "${1:-}" = --root ]; then ROOT="${2:?mavergreen: --root needs a volume}"; shift 2; fi
R="${ROOT%/}"
MG="$R/usr/local/mavergreen"
SEL="$MG/var/mavergreen/selections"
FARM="bin sbin share/man/man1 share/man/man2 share/man/man3 share/man/man4 share/man/man5 share/man/man6 share/man/man7 share/man/man8"

die() { echo "mavergreen: $1" >&2; exit "${2:-1}"; }
valid() { case "$1" in ''|-*|*[!a-z0-9-]*) return 1 ;; esac; }
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
unlink_product() {
  for _d in $FARM; do
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

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  link) [ $# -eq 1 ] || die "usage: mavergreen link <product>" 2; do_link "$1" ;;
  unlink) [ $# -eq 1 ] || die "usage: mavergreen unlink <product>" 2; do_unlink "$1" ;;
  select) [ $# -ge 1 ] || die "usage: mavergreen select <group> [<product>]" 2; do_select "$@" ;;
  list) do_list ;;
  *) die "usage: mavergreen [--root VOLUME] link|unlink|select|list ..." 2 ;;
esac
