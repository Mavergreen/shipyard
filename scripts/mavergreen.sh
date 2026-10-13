#!/bin/sh
# platform: macOS-only -- PlistBuddy reads each manifest and directory-service record, and uninstall runs launchctl and pkgutil
#   usage: mavergreen [--root VOLUME] <command> [args]
#            link <product>               export a product's commands and manpages
#            unlink <product>             remove them (never changes a selection)
#            select <group> [<product>]   show or change which member owns the bare names
#            list                         installed products, groups, lines, selections
#            check                        verify the farm's links and manifests; problems to stderr
#            uninstall <product>          remove it, its farm links, and what its manifest lists as outside or generated;
#                                         a replaced product's changed config, or one restored by hand with system-restore,
#                                         is kept beside the original as <path>.mavergreen-save; it refuses before its
#                                         pre-uninstall hook when its restore would refuse any entry
#            system-replace <product>     swap the manifest's :replaces system paths for copies of the tree's programs
#                                         and links to its man pages, and move its :adopts config and state to their
#                                         system paths with var linking to them, recording it all in applied.plist (10.9 only);
#                                         the tree's libexec/mavergreen/pre-system-replace hook may edit or veto the staged config;
#                                         run again (as an upgrade's postinstall does), it applies new entries, refreshes copies whose
#                                         tree file changed and restores entries the manifest no longer declares;
#                                         a product an older mavergreen replaced (.replaced, no applied.plist) has its
#                                         save area made root-only first, then is replaced again in place, its links
#                                         counted as its own and its saved originals kept as the originals, saying so on stderr
#            system-restore <product>     put back what applied.plist records (or, with none, what the manifest lists),
#                                         printing the settings each restored config lacks, then run post-system-restore;
#                                         all or nothing: an entry it would refuse, or a saved file applied.plist does
#                                         not name, stops it before any change. A path Apple
#                                         owns again (stock by receipt, or any path once the volume is past 10.9, where
#                                         restore writes no system path) is left as it is, said on stdout; its saved
#                                         original is discarded if an Apple receipt lists it, else moved, set-id bits
#                                         cleared, to the root-only usr/local/mavergreen/kept/<product>/<path> (the first
#                                         free <path>.N if taken), which nothing removes. A volume version it cannot
#                                         read refuses, as does a post-system-restore hook that is not root-only
#            version                      print the mavergreen helper's stamped version
#          MAVERGREEN_TRUSTED_UID  test only, honoured only with a --root other than /: the uid that counts as root when system-replace and check judge ownership (default 0)
# spec: tests/mavergreen-helper-test.sh
set -eu
# spec: tests/product-names-test.sh -- a name is lowercase ASCII; a UTF-8 locale can collate [a-z] to
#       admit uppercase in case patterns and awk ranges, so names are matched in the C locale.
LC_ALL=C; export LC_ALL
MAVERGREEN_VERSION="@MAVERGREEN_VERSION@"
PB=/usr/libexec/PlistBuddy
ROOT=/
if [ "${1:-}" = --root ]; then ROOT="${2:?mavergreen: --root needs a volume}"; shift 2; fi
R="${ROOT%/}"
MG="$R/usr/local/mavergreen"
SEL="$MG/var/mavergreen/selections"

die() { echo "mavergreen: $1" >&2; exit "${2:-1}"; }
_stock_idx=""; _undo_staging=""; _undo_save=""; _undo_files=""; _sr_keep=""; _rd_dry=""; _ra_owns=""; _ra_newer=""; _ra_vbad=""; _mig=""
on_exit() {
  if [ -n "$_mig" ]; then
    echo "mavergreen: $_mig stays as the older mavergreen replaced it, with its save area now root-only; once what is named above is fixed by hand, mavergreen system-replace $_mig migrates it" >&2
  fi
  if [ -n "$_stock_idx" ]; then rm -f "$_stock_idx"; fi
  if [ -n "$_undo_staging" ]; then rm -rf "$_undo_staging"; fi
  if [ -n "$_undo_files" ]; then
    printf '%s\n' "$_undo_files" | while IFS= read -r _uf; do if [ -n "$_uf" ]; then rm -f "$_uf"; fi; done
  fi
  if [ -n "$_undo_save" ]; then rmdir "$_undo_save" 2>/dev/null || true; fi
}
trap on_exit EXIT
valid() { case "$1" in ''|-*|*[!a-z0-9-]*|var|bin|sbin|share|mavergreen|system-replace|base|kept) return 1 ;; esac; }
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
    if [ -f "$MG/var/system-replace/$_p/.replaced" ]; then _n=$((_n + $(replace_drift "$_p") + $(replace_ownership "$_p")))
    elif [ -f "$MG/var/system-replace/$_p/applied.plist" ]; then
      echo "mavergreen: $_p: a System Replace did not finish; run mavergreen system-replace $_p or mavergreen system-restore $_p" >&2
      _n=$((_n + 1))
    fi
  done
  [ "$_n" -eq 0 ]
}
plist_dict() {
  plutil -convert xml1 -o - "$1" 2>/dev/null | awk -v want="$2" '
    function unesc(s) {
      gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "\047", s)
      gsub(/&amp;/, "\\&", s); return s
    }
    function bad(s) { return s ~ /[\t\n]|&#/ }
    BEGIN { RS = "<"; depth = 0; take = 0; nest = 0 }
    {
      i = index($0, ">"); if (i == 0) next
      tag = substr($0, 1, i - 1); text = substr($0, i + 1)
      if (tag == "key") { key = unesc(text); next }
      if (tag == "/dict" || tag == "/array") {
        depth--
        if (nest && depth == 2) {
          if (bad(outer) || bad(np) || bad(nk)) { gsub(/[\t\n]/, " ", outer); np = ""; nk = "" }
          print outer "\t" np "\t" nk; nest = 0
        }
        if (depth < 2) take = 0; next
      }
      if (tag ~ /^[\/?!]/ || tag ~ /^plist/) next
      if (depth == 1 && key == want && tag == "dict") take = 1
      else if (depth == 2 && take && tag == "dict") { nest = 1; outer = key; np = ""; nk = "" }
      else if (depth == 3 && nest) {
        v = (tag == "string") ? unesc(text) : ""
        if (key == "path") np = v; else if (key == "kind") nk = v
      }
      else if (depth == 2 && take) {
        v = (tag == "string") ? unesc(text) : ""
        if (key ~ /[\t\n]|&#/ || v ~ /[\t\n]|&#/) { gsub(/[\t\n]/, " ", key); v = "" }
        print key "\t" v
      }
      if (tag == "dict" || tag == "array") depth++
    }'
}
replaces() { plist_dict "$(manifest "$1")" replaces; }
adopts() { plist_dict "$(manifest "$1")" adopts; }
tab_get() { printf '%s\n' "$1" | K="$2" awk 'BEGIN { FS = "\t" } $1 "" == ENVIRON["K"] "" { sub(/^[^\t]*\t/, ""); print; exit }'; }
tab_has() { printf '%s\n' "$1" | K="$2" awk 'BEGIN { FS = "\t" } $1 "" == ENVIRON["K"] "" { f = 1 } END { exit !f }'; }
tab_drop() { printf '%s\n' "$1" | K="$2" awk 'BEGIN { FS = "\t" } NF && $1 "" != ENVIRON["K"] ""'; }
xesc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
xdict() {
  printf '  <key>%s</key>\n  <dict>\n' "$1"
  printf '%s\n' "$2" | while IFS="	" read -r _xd_k _xd_v; do
    [ -n "$_xd_k" ] || continue
    printf '    <key>%s</key>\n    <string>%s</string>\n' "$(xesc "$_xd_k")" "$(xesc "$_xd_v")"
  done
  printf '  </dict>\n'
}
xadopts() {
  printf '  <key>adopts</key>\n  <dict>\n'
  printf '%s\n' "$1" | while IFS="	" read -r _xa_k _xa_p _xa_t; do
    [ -n "$_xa_k" ] || continue
    printf '    <key>%s</key>\n    <dict>\n      <key>path</key>\n      <string>%s</string>\n' "$(xesc "$_xa_k")" "$(xesc "$_xa_p")"
    printf '      <key>kind</key>\n      <string>%s</string>\n    </dict>\n' "$(xesc "$_xa_t")"
  done
  printf '  </dict>\n'
}
applied_write() {
  [ "$#" -eq 6 ] || { echo "mavergreen: applied_write wants P, replaces, originals, copies, adopts and refreshing" >&2; return 1; }
  _aw="$MG/var/system-replace/$1/applied.plist"
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n<dict>\n'
    xdict replaces "$2"
    xadopts "$5"
    xdict originals "$3"
    xdict copies "$4"
    xdict refreshing "$6"
    printf '</dict>\n</plist>\n'
  } > "$_aw.tmp" && mv -f "$_aw.tmp" "$_aw"
}
is_copy_kind() { case "$1" in share/man/*) return 1 ;; esac; }
sha256_of() { shasum -a 256 < "$1" | awk '{ print $1 }'; }
present() { [ -e "$1" ] || [ -L "$1" ]; }
same_file() {
  if [ -L "$1" ] && [ -L "$2" ]; then [ "$(readlink "$1")" = "$(readlink "$2")" ]; return; fi
  [ ! -L "$1" ] && [ ! -L "$2" ] && [ -e "$1" ] && [ -e "$2" ] || return 1
  [ "$(stat -f '%d %i' "$1")" = "$(stat -f '%d %i' "$2")" ]
}
fingerprint() {
  if [ -L "$1" ]; then printf 'link:%s' "$(readlink "$1")"
  elif [ -f "$1" ]; then sha256_of "$1"
  elif [ -e "$1" ]; then printf '%s' '?'
  else printf '%s' -
  fi
}
expected_of() {
  if is_copy_kind "$2"; then sha256_of "$MG/$1/$2" 2>/dev/null; else printf 'link:/usr/local/mavergreen/%s/%s' "$1" "$2"; fi
}
device_of() {
  _dv="$1"; _dv_top=.; case "$1" in /*) _dv_top=/ ;; esac
  while [ -n "$_dv" ] && ! present "$_dv"; do
    case "$_dv" in */*) _dv="${_dv%/*}" ;; *) _dv="" ;; esac
  done
  stat -f %d "${_dv:-$_dv_top}"
}
staging_path() { printf '%s/.%s.mavergreen-tmp' "$(dirname "$1")" "$(basename "$1")"; }
staging_blocked() {
  _sb="$(staging_path "$1")"
  if [ -L "$_sb" ]; then [ "$2" != "symlink:$(readlink "$_sb")" ]; return; fi
  [ -e "$_sb" ] && [ ! -f "$_sb" ]
}
swap_in() {
  _si_t="$(staging_path "$2")"
  if staging_blocked "$2" "$1"; then echo "mavergreen: $_si_t exists and is not a regular file; remove it, then retry" >&2; return 1; fi
  if [ -d "$2" ]; then echo "mavergreen: $2 is a directory or a link to one; system-replace swaps files and symlinks only" >&2; return 1; fi
  mkdir -p "$(dirname "$2")"
  case "$1" in
    symlink:*) rm -f "$_si_t" && ln -s "${1#symlink:}" "$_si_t" ;;
    *) rm -f "$_si_t" && cp -p "$1" "$_si_t" ;;
  esac || { rm -f "$_si_t"; echo "mavergreen: could not stage $1 beside $2" >&2; return 1; }
  if [ -n "$3" ] && present "$2" && ! same_file "$3" "$2"; then
    if present "$3"; then rm -f "$_si_t"; echo "mavergreen: $3 already holds a saved original; not saving $2 over it" >&2; return 1; fi
    mkdir -p "$(dirname "$3")"
    if [ -L "$2" ]; then ln -s "$(readlink "$2")" "$3"; else ln "$2" "$3"; fi \
      || { rm -f "$_si_t"; echo "mavergreen: could not save the original $2 as $3" >&2; return 1; }
  fi
  mv -f "$_si_t" "$2" || { rm -f "$_si_t"; echo "mavergreen: could not move the staged copy over $2" >&2; return 1; }
}
replace_shape_ok() {
  case "$1" in /*) : ;; *) return 1 ;; esac
  case "/$1/" in *"/./"*|*"/../"*) return 1 ;; esac
  _rs_1="${1#/}"
  case "$(printf '%s' "${_rs_1%%/*}" | tr 'A-Z' 'a-z')" in
    staging|applied.plist|applied.plist.tmp|adopted.sha256|adopted.sha256.tmp|restored.sha256|restored.sha256.tmp|.replaced) return 1 ;;
  esac
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
words_ok() {
  while IFS= read -r _wo_w; do
    [ -n "$_wo_w" ] || continue
    case "$1:$_wo_w" in
      GroupMembership:root|GroupMembers:FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000) : ;;
      *) return 1 ;;
    esac
  done <<EOT
$(printf '%s\n' "$2" | tr -s ' 	' '\n')
EOT
}
dscl_words() {
  _dw_o="$(dscl . -read "/Groups/$1" "$2" 2>&1)" || return 1
  case "$_dw_o" in
    "No such key: "*) return 0 ;;
    "$2:"*) printf '%s\n' "${_dw_o#"$2:"}" ;;
    *) return 1 ;;
  esac
}
plist_words() {
  _pw_i=0
  while _pw_v="$("$PB" -c "Print :$2:$_pw_i" "$1" 2>/dev/null)"; do
    printf '%s\n' "$_pw_v"; _pw_i=$((_pw_i + 1))
  done
}
record_ok() {
  "$PB" -c 'Print :gid:0' "$1" >/dev/null 2>&1 || "$PB" -c 'Print :name:0' "$1" >/dev/null 2>&1
}
list_or_absent() {
  _la_v="$("$PB" -c "Print :$2" "$1" 2>/dev/null)" || return 0
  case "$_la_v" in "Array {"*) return 0 ;; esac
  return 1
}
group_root_only() {
  if [ -z "$R" ]; then
    _gr_out="$(dscl . -search /Groups PrimaryGroupID "$1" 2>/dev/null)" || return 1
    _gr_names="$(printf '%s\n' "$_gr_out" | awk '/^[^ 	)]/ { print $1 }')"
    [ -n "$_gr_names" ] || return 1
    while IFS= read -r _gr_n; do
      [ -n "$_gr_n" ] || continue
      for _gr_k in GroupMembership GroupMembers; do
        _gr_w="$(dscl_words "$_gr_n" "$_gr_k")" || return 1
        words_ok "$_gr_k" "$_gr_w" || return 1
      done
      _gr_w="$(dscl_words "$_gr_n" NestedGroups)" || return 1
      [ -z "$_gr_w" ] || return 1
    done <<EOT
$_gr_names
EOT
    _gr_prim="$(dscl . -list /Users PrimaryGroupID 2>/dev/null)" || return 1
    printf '%s\n' "$_gr_prim" | awk -v g="$1" '$1 == "root" { r = 1 } $1 != "root" && $2 == g { found = 1 } END { exit found || !r }'
    return
  fi
  _gr_dir="$R/var/db/dslocal/nodes/Default"
  _gr_found=0
  for _gr_f in "$_gr_dir"/groups/*.plist; do
    [ -f "$_gr_f" ] || continue
    record_ok "$_gr_f" || return 1
    list_or_absent "$_gr_f" gid || return 1
    [ "$("$PB" -c 'Print :gid:0' "$_gr_f" 2>/dev/null || true)" = "$1" ] || continue
    _gr_found=1
    for _gr_k in users groupmembers nestedgroups; do list_or_absent "$_gr_f" "$_gr_k" || return 1; done
    words_ok GroupMembership "$(plist_words "$_gr_f" users)" || return 1
    words_ok GroupMembers "$(plist_words "$_gr_f" groupmembers)" || return 1
    [ -z "$(plist_words "$_gr_f" nestedgroups)" ] || return 1
  done
  [ "$_gr_found" -eq 1 ] || return 1
  _gr_root=0
  for _gr_f in "$_gr_dir"/users/*.plist; do
    [ -f "$_gr_f" ] || continue
    record_ok "$_gr_f" || return 1
    list_or_absent "$_gr_f" gid || return 1
    if [ "$(basename "$_gr_f" .plist)" = root ]; then _gr_root=1; continue; fi
    if [ "$("$PB" -c 'Print :gid:0' "$_gr_f" 2>/dev/null || true)" = "$1" ]; then return 1; fi
  done
  [ "$_gr_root" -eq 1 ]
}
judge_node() {
  _jn_st="$(stat -f '%u	%g	%Lp	%Su	%Sg' "$1")" || { printf '%s ? ?\n' "$1"; return 1; }
  IFS="	" read -r _jn_u _jn_g _jn_mode _jn_owner _jn_grp <<EOT
$_jn_st
EOT
  _jn_trust=0
  if [ -n "$R" ]; then _jn_trust="${MAVERGREEN_TRUSTED_UID:-0}"; fi
  _jn_bad=""
  [ "$_jn_u" = "$_jn_trust" ] || _jn_bad=1
  if [ "$2" != link ]; then
    _jn_gb="${_jn_mode%?}"; _jn_gb="${_jn_gb#"${_jn_gb%?}"}"; _jn_ob="${_jn_mode#"${_jn_mode%?}"}"
    case "$_jn_ob" in 2|3|6|7) _jn_bad=1 ;; esac
    case "$_jn_gb" in 2|3|6|7) group_root_only "$_jn_g" || _jn_bad=1 ;; esac
    if [ -z "$_jn_bad" ] && ls -lde "$1" 2>/dev/null | sed 1d | grep -q '^ *[0-9]*: .* allow '; then
      printf '%s %s %s acl\n' "$1" "$_jn_owner" "$_jn_mode"; return 1
    fi
  fi
  if [ -n "$_jn_bad" ]; then printf '%s %s %s\n' "$1" "$_jn_owner" "$_jn_mode"; return 1; fi
  return 0
}
root_only_chain() {
  _rc_rest="${1#"$R"}"
  case "$_rc_rest" in /*) : ;; *) printf '%s ? ?\n' "$1"; return 1 ;; esac
  _rc_cur="$R"; _rc_hops=0
  judge_node "${_rc_cur:-/}" dir || return 1
  while :; do
    while [ "${_rc_rest#/}" != "$_rc_rest" ]; do _rc_rest="${_rc_rest#/}"; done
    [ -n "$_rc_rest" ] || return 0
    _rc_c="${_rc_rest%%/*}"
    case "$_rc_rest" in */*) _rc_rest="/${_rc_rest#*/}" ;; *) _rc_rest="" ;; esac
    case "$_rc_c" in
      .) continue ;;
      ..) [ "$_rc_cur" = "$R" ] || _rc_cur="${_rc_cur%/*}"; continue ;;
    esac
    _rc_n="$_rc_cur/$_rc_c"
    if [ -L "$_rc_n" ]; then
      judge_node "$_rc_n" link || return 1
      _rc_hops=$((_rc_hops + 1))
      if [ "$_rc_hops" -gt 16 ]; then printf '%s %s %s loop\n' "$_rc_n" "$_jn_owner" "$_jn_mode"; return 1; fi
      _rc_t="$(readlink "$_rc_n")"
      case "$_rc_t" in
        /*) _rc_cur="$R"; _rc_rest="$_rc_t$_rc_rest" ;;
        *) _rc_rest="/$_rc_t$_rc_rest" ;;
      esac
    elif [ -d "$_rc_n" ]; then
      judge_node "$_rc_n" dir || return 1
      _rc_cur="$_rc_n"
    elif [ -e "$_rc_n" ]; then
      if [ -z "${_rc_rest#/}" ] && [ -n "${2:-}" ]; then judge_node "$_rc_n" file || return 1; fi
      return 0
    else
      return 0
    fi
  done
}
offender_text() {
  _ot_l="$1"; _ot_t=""
  case "$_ot_l" in *" acl"|*" loop") _ot_t="${_ot_l##* }"; _ot_l="${_ot_l% *}" ;; esac
  _ot_m="${_ot_l##* }"; _ot_l="${_ot_l% *}"; _ot_o="${_ot_l##* }"; _ot_d="${_ot_l% *}"
  case "$_ot_t" in
    acl) printf '%s carries an ACL allow entry (owner %s, mode %s); a non-root user could change what root runs' "$_ot_d" "$_ot_o" "$_ot_m" ;;
    loop) printf '%s is part of a link loop; it never resolves to a root-only path' "$_ot_d" ;;
    *) printf '%s is not root-only (owner %s, mode %s); a non-root user could change what root runs' "$_ot_d" "$_ot_o" "$_ot_m" ;;
  esac
}
replace_offender() {
  _ro_o="$(root_only_chain "$R$2")" || { printf '%s\n' "$_ro_o"; return 1; }
  _ro_o="$(root_only_chain "$MG/$1/$3" leaf)" || { printf '%s\n' "$_ro_o"; return 1; }
  return 0
}
replace_record() {
  _rr="$MG/var/system-replace/$1/applied.plist"
  if [ -f "$_rr" ]; then plist_dict "$_rr" "$2"; elif [ "$2" = replaces ]; then replaces "$1"; fi
}
save_area_offender() {
  _so_o="$(root_only_chain "$1")" || { offender_text "$_so_o"; return 1; }
  [ -e "$1" ] || return 0
  _so_m="$(stat -f %Lp "$1")" || { printf 'its mode cannot be read'; return 1; }
  case "$_so_m" in ?00) return 0 ;; esac
  printf 'its mode is %s, so users other than root can reach them, setuid ones included' "$_so_m"
  return 1
}
replace_ownership() {
  _rw_n=0
  _rw_o="$(save_area_offender "$MG/var/system-replace/$1")" || {
    echo "mavergreen: $MG/var/system-replace/$1 holds $1's saved originals, but $_rw_o" >&2
    _rw_n=$((_rw_n + 1)); }
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    _rw_o="$(replace_offender "$1" "$_abs" "$_rel")" || {
      echo "mavergreen: $_abs is replaced by $1, but $(offender_text "$_rw_o")" >&2
      _rw_n=$((_rw_n + 1)); }
  done <<EOT
$(replace_record "$1" replaces)
EOT
  while IFS="	" read -r _abs _rel _kind; do
    [ -n "$_abs" ] || continue
    _rw_o="$(adopt_offender "$1" "$_abs" "$_rel")" || {
      echo "mavergreen: $_abs is adopted by $1, but $(offender_text "$_rw_o")" >&2
      _rw_n=$((_rw_n + 1)); }
  done <<EOT
$(replace_record "$1" adopts)
EOT
  echo "$_rw_n"
}
adopt_shape_ok() {
  replace_shape_ok "$1" "$2" || return 1
  case "$1" in */|*//*|/usr/local/mavergreen|/usr/local/mavergreen/*) return 1 ;; esac
  case "$2" in */|*//*) return 1 ;; esac
  case "$3" in config|identity) return 0 ;; esac
  return 1
}
var_abs() { printf '/usr/local/mavergreen/var/%s/%s' "$1" "$2"; }
adopt_offender() {
  _ao_o="$(root_only_chain "$R$2" leaf)" || { printf '%s\n' "$_ao_o"; return 1; }
  _ao_o="$(root_only_chain "$MG/var/$1/$3" leaf)" || { printf '%s\n' "$_ao_o"; return 1; }
  return 0
}
stock_index() {
  _stock_idx="$(mktemp "${TMPDIR:-/tmp}/mavergreen-stock.XXXXXX")" || die "could not create a temporary file for the receipt index"
  for _si_b in "$R"/var/db/receipts/com.apple.pkg.*.bom; do
    [ -f "$_si_b" ] || continue
    { lsbom -p fcs "$_si_b" 2>/dev/null || true; } | W="$1" awk -F '\t' '
      BEGIN { n = split(ENVIRON["W"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") { w["." a[i]] = 1; w["./private" a[i]] = 1 } }
      $1 in w' >> "$_stock_idx" || die "could not write the receipt index $_stock_idx"
  done
}
apple_stock() { apple_stock_file "$1" "$R$1"; }
apple_stock_file() {
  [ -n "$_stock_idx" ] && [ -f "$2" ] && [ ! -L "$2" ] || return 1
  _ak_ck="$(cksum 2>/dev/null < "$2")" || return 1
  _ak_c="${_ak_ck%% *}"; _ak_z="${_ak_ck#* }"; _ak_z="${_ak_z%% *}"
  K="$1" C="$_ak_c" Z="$_ak_z" awk -F '\t' '
    ($1 == "." ENVIRON["K"] || $1 == "./private" ENVIRON["K"]) && $2 "" == ENVIRON["C"] "" && $3 "" == ENVIRON["Z"] "" { f = 1 }
    END { exit !f }' "$_stock_idx"
}
restore_rec() {
  _rr_f="$MG/var/system-replace/$1/restored.sha256"
  if [ -f "$_rr_f" ]; then
    K="$2 $3" awk 'substr($0, 66) == ENVIRON["K"] { v = substr($0, 1, 64) } END { print v }' "$_rr_f" || return 1
  fi
}
baseline_system() {
  _bs_v="$(restore_rec "$1" system "$2")" || return 1
  printf '%s\n' "${_bs_v:-stock}"
}
seed_rec() {
  _sd_f="$MG/var/$1/.mavergreen-seeded"
  if [ -f "$_sd_f" ]; then
    K="$2" awk 'substr($0, 67) == ENVIRON["K"] { v = substr($0, 1, 64) } END { print v }' "$_sd_f" || return 1
  fi
}
baseline_var() {
  _bv_v="$(restore_rec "$1" var "$3")" || return 1
  if [ -z "$_bv_v" ]; then _bv_v="$(seed_rec "$1" "$2")" || return 1; fi
  printf '%s\n' "$_bv_v"
}
adopt_decision() {
  _ad_s="$R$2"; _ad_v="$MG/var/$1/$3"
  if [ "$4" = identity ]; then
    if present "$_ad_s"; then echo system; elif present "$_ad_v"; then echo var; else echo skip; fi
    return 0
  fi
  if ! present "$_ad_s"; then
    if present "$_ad_v"; then echo var; else echo skip; fi
    return 0
  fi
  _ad_ss="$(sha256_of "$_ad_s")"
  [ -n "$_ad_ss" ] || { echo "could not checksum $2; nothing was replaced"; return 1; }
  _ad_sb="$(baseline_system "$1" "$2")" || { echo "could not read $2's restore record"; return 1; }
  if [ "$_ad_sb" = stock ]; then
    if apple_stock "$2"; then _ad_sys=base; else _ad_sys=custom; fi
  elif [ "$_ad_ss" = "$_ad_sb" ]; then _ad_sys=base
  else _ad_sys=custom
  fi
  _ad_var=absent; _ad_vs=""
  if present "$_ad_v"; then
    _ad_vs="$(sha256_of "$_ad_v")"
    [ -n "$_ad_vs" ] || { echo "could not checksum $(var_abs "$1" "$3"); nothing was replaced"; return 1; }
    _ad_vb="$(baseline_var "$1" "$3" "$2")" || { echo "could not read the seed or restore record of $(var_abs "$1" "$3")"; return 1; }
    if [ -n "$_ad_vb" ] && [ "$_ad_vs" = "$_ad_vb" ]; then _ad_var=default; else _ad_var=custom; fi
  fi
  case "$_ad_sys:$_ad_var" in
    base:absent|custom:absent|custom:default) echo system ;;
    base:*) echo var ;;
    *)
      if [ "$_ad_ss" = "$_ad_vs" ]; then echo system; return 0; fi
      echo "refusing $2: $2 and $(var_abs "$1" "$3") have both been customized and they differ; make one match the other, then retry"
      return 1 ;;
  esac
}
adopted_set() {
  _ah_f="$MG/var/system-replace/$1/adopted.sha256"
  printf '' > "$_ah_f.tmp" || return 1
  if [ -f "$_ah_f" ]; then K="$2" awk 'substr($0, 67) != ENVIRON["K"]' "$_ah_f" > "$_ah_f.tmp" || return 1; fi
  printf '%s  %s\n' "$3" "$2" >> "$_ah_f.tmp" && mv -f "$_ah_f.tmp" "$_ah_f"
}
restored_set() {
  _rs_f="$MG/var/system-replace/$1/restored.sha256"
  printf '' > "$_rs_f.tmp" || return 1
  if [ -f "$_rs_f" ]; then
    K="$2" awk '{ r = substr($0, 66); sub(/^(system|var) /, "", r) } r != ENVIRON["K"]' "$_rs_f" > "$_rs_f.tmp" || return 1
  fi
  if [ -n "$3" ]; then printf '%s system %s\n' "$3" "$2" >> "$_rs_f.tmp" || return 1; fi
  if [ -n "$4" ]; then printf '%s var %s\n' "$4" "$2" >> "$_rs_f.tmp" || return 1; fi
  mv -f "$_rs_f.tmp" "$_rs_f"
}
hook_ok() {
  _rh="$MG/$1/libexec/mavergreen/$2"; _rh_msg=""; _rh_rc=1
  _rh_pi=0; parent_in_root "$_rh" || _rh_pi=$?
  case "$_rh_pi" in
    2) _rh=""; return 0 ;;
    0) ;;
    *) _rh_msg="refusing to run $1's $2 hook ($_rh) -- its parent directory resolves outside $ROOT"; return 1 ;;
  esac
  if [ -L "$_rh" ]; then
    _rh_msg="refusing to run $1's $2 hook ($_rh) -- it is a symlink, and a hook is never a link into the payload"; return 1
  fi
  if [ ! -e "$_rh" ]; then _rh=""; return 0; fi
  [ -x "$_rh" ] || { _rh_msg="$1's $2 hook ($_rh) exists but is not executable"; return 1; }
  [ "$2" != pre-uninstall ] || return 0
  _rh_o="$(root_only_chain "$_rh" leaf)" || { _rh_msg="refusing to run $1's $2 hook ($_rh) -- $(offender_text "$_rh_o")"; return 1; }
}
run_hook() {
  _rh_p="$1"; _rh_n="$2"; shift 2
  hook_ok "$_rh_p" "$_rh_n" || return 1
  [ -n "$_rh" ] || return 0
  _rh_rc=0
  trap : INT
  set +e
  ( unset MAVERGREEN_STAGING || exit 126
    MAVERGREEN_ROOT="$ROOT"; MAVERGREEN_PRODUCT="$_rh_p"
    export MAVERGREEN_ROOT MAVERGREEN_PRODUCT || exit 126
    for _rh_a in "$@"; do export "$_rh_a" || exit 126; done
    exec "$_rh" )
  _rh_rc=$?
  set -e
  trap - INT
  [ "$_rh_rc" -ne 0 ] || return 0
  if [ "$_rh_rc" -gt 128 ]; then _rh_msg="$_rh_p's $_rh_n hook ($_rh) was cancelled (status $_rh_rc)"
  else _rh_msg="$_rh_p's $_rh_n hook ($_rh) failed (status $_rh_rc)"
  fi
  return 1
}
stage_perms() {
  _sp_src="$R$2"; present "$_sp_src" || _sp_src="$MG/var/$1/$3"
  _sp_st="$MG/var/system-replace/$1/staging/$3"
  chown "$(stat -f %u:%g "$_sp_src")" "$_sp_st" && chmod "$(stat -f %Mp%Lp "$_sp_src")" "$_sp_st"
}
adopt_plan() {
  _aplan=""; _ap_rels=""
  while IFS="	" read -r _abs _rel _kind; do
    [ -n "$_abs" ] || continue
    adopt_shape_ok "$_abs" "$_rel" "$_kind" || die "$1 declares an unsafe adopts entry: '$_abs' -> '$_rel' ($_kind)"
    if tab_has "$_entries" "$_abs"; then die "$1 declares $_abs in both replaces and adopts"; fi
    if printf '%s\n' "$_ap_rels" | grep -qixF -- "$_rel"; then die "$1 declares two adopts entries at the var path $_rel, which HFS+ compares case-insensitively"; fi
    _ap_rels="$_ap_rels
$_rel"
    if tab_has "$_old" "$_abs"; then
      die "$_abs moves between adopts and replaces in this version of $1; run mavergreen system-restore $1, then mavergreen system-replace $1"
    fi
    _ap_was="$(tab_get "$_olda" "$_abs")"; _ap_was="${_ap_was%%	*}"
    if [ -n "$_ap_was" ] && [ "$_ap_was" != "$_rel" ] && tab_has "$_copies0" "$_abs"; then
      die "$1 now adopts $_abs at $(var_abs "$1" "$_rel"), but it was adopted at $(var_abs "$1" "$_ap_was"); run mavergreen system-restore $1, then mavergreen system-replace $1"
    fi
    _o="$(adopt_offender "$1" "$_abs" "$_rel")" || die "refusing $_abs: $(offender_text "$_o")"
    _cur="$R$_abs"; _var="$MG/var/$1/$_rel"; _vabs="$(var_abs "$1" "$_rel")"; _save="$_b$_abs"
    _now="$(fingerprint "$_cur")"; _vnow="$(fingerprint "$_var")"
    [ -n "$_now" ] || die "could not checksum $_abs; nothing was replaced"
    [ -n "$_vnow" ] || die "could not checksum $_vabs; nothing was replaced"
    _was="$(tab_get "$_orig" "$_abs")"; _cp="$(tab_get "$_copies" "$_abs")"
    if [ "$_vnow" = "link:$_abs" ]; then
      tab_has "$_copies" "$_abs" \
        || die "$_vabs already links to $_abs, but $_b/applied.plist does not record adopting it; remove the link, then retry"
      continue
    fi
    _act=swap
    if tab_has "$_copies" "$_abs"; then
      [ "$_cp" != - ] || continue
      if present "$_save" && same_file "$_save" "$_cur"; then :
      elif present "$_save" || { [ "$_was" = - ] && present "$_cur" && { [ "$_now" = "$_cp" ] || [ "$_now" = "$_vnow" ]; }; }; then
        [ -f "$_cur" ] && [ ! -L "$_cur" ] \
          || die "refusing $_abs: $1 adopted it, but it is missing or no longer a real file; run system-restore $1 first"
        _ap_seed="$(seed_rec "$1" "$_rel")" || _ap_seed=""
        if [ "$_vnow" = "$_now" ] || { [ "$_now" = "$_cp" ] && [ "$_vnow" = "$(tab_get "$_orig" "$_vabs")" ]; } \
          || { [ -n "$_ap_seed" ] && [ "$_vnow" = "$_ap_seed" ]; }; then _act=link
        else die "refusing $_abs: $_vabs is no longer $1's link to it, and the two files differ; make one match the other, then retry"
        fi
      elif [ "$_was" = - ]; then
        if present "$_cur"; then
          die "$_abs was absent when mavergreen recorded it, and what is there now is not what mavergreen staged; move it aside, then retry"
        fi
      elif [ "$_now" != "$_was" ]; then die "$_abs has changed since mavergreen recorded it; run system-restore $1 first"
      fi
    fi
    if [ "$_act" = link ]; then
      if staging_blocked "$_var" "symlink:$_abs"; then die "$(staging_path "$_var") exists and is not a regular file; remove it, then retry"; fi
      _st="$_b/staging/$_rel"
      if [ -L "$_st" ] || { [ -e "$_st" ] && [ ! -f "$_st" ]; }; then die "$_st is in the way of setting $_vabs aside; remove it, then retry"; fi
      _aplan="${_aplan}link	$_abs	$_rel
"
      continue
    fi
    if [ -L "$_cur" ]; then
      die "refusing $_abs: it is a symlink mavergreen did not make; system-replace adopts only a real file there, so put the file it points to in its place (or remove it), then retry"
    fi
    if present "$_cur" && [ ! -f "$_cur" ]; then die "refusing $_abs: it is not a regular file; system-replace adopts files only"; fi
    if [ -L "$_var" ]; then die "refusing $_abs: $_vabs is a symlink that is not $1's link to it; system-replace adopts only a real file there"; fi
    if present "$_var" && [ ! -f "$_var" ]; then die "refusing $_abs: $_vabs is not a regular file; system-replace adopts files only"; fi
    if present "$_save" && ! same_file "$_save" "$_cur"; then die "$_abs was already saved once and has since changed; run system-restore $1 first"; fi
    _d="$(adopt_decision "$1" "$_abs" "$_rel" "$_kind")" || die "$_d"
    if [ "$_d" != skip ]; then
      _st="$_b/staging/$_rel"
      if staging_blocked "$_cur" "$_st"; then die "$(staging_path "$_cur") exists and is not a regular file; remove it, then retry"; fi
      if staging_blocked "$_var" "symlink:$_abs"; then die "$(staging_path "$_var") exists and is not a regular file; remove it, then retry"; fi
      if [ -L "$_st" ] || { [ -e "$_st" ] && [ ! -f "$_st" ]; }; then die "$_st is in the way of staging $_rel; remove it, then retry"; fi
      if present "$_cur" && ! same_file "$_save" "$_cur" && [ "$(device_of "$(dirname "$_cur")")" != "$_savedev" ]; then
        die "refusing $_abs: it is on another volume than $1's save area ($_b), and originals are saved there by hard link"
      fi
    fi
    tab_has "$_orig" "$_abs" || _orig="$_orig
$_abs	$_now"
    _orig="$(tab_drop "$_orig" "$_vabs")
$_vabs	$_vnow"
    _aplan="${_aplan}swap:$_d	$_abs	$_rel
"
  done <<EOF
$_adopts
EOF
}
adopt_stage() {
  while IFS="	" read -r _ag_act _ag_abs _ag_rel; do
    case "$_ag_act" in swap:var|swap:system) : ;; *) continue ;; esac
    _ag_st="$_b/staging/$_ag_rel"; _ag_cur="$R$_ag_abs"; _ag_src="$MG/var/$1/$_ag_rel"
    if [ "$_ag_act" = swap:system ]; then _ag_src="$_ag_cur"; fi
    _undo_files="$_undo_files
$_ag_st"
    { mkdir -p "$(dirname "$_ag_st")" && rm -f "$_ag_st" && cp -p "$_ag_src" "$_ag_st"; } || return 1
    stage_perms "$1" "$_ag_abs" "$_ag_rel" || return 1
  done <<EOF
$_aplan
EOF
}
adopt_link() {
  _al_v="$MG/var/$1/$3"; _al_t="$(staging_path "$MG/var/$1/$3")"; _al_a="$MG/var/system-replace/$1/staging/$3"
  mkdir -p "$(dirname "$_al_v")" || return 1
  { rm -f "$_al_t" && ln -s "$2" "$_al_t"; } \
    || { rm -f "$_al_t"; echo "mavergreen: could not stage a link to $2 beside $(var_abs "$1" "$3")" >&2; return 1; }
  if [ -f "$_al_v" ] && [ ! -L "$_al_v" ]; then
    { mkdir -p "$(dirname "$_al_a")" && rm -f "$_al_a" && { ln "$_al_v" "$_al_a" 2>/dev/null || cp -p "$_al_v" "$_al_a"; }; } \
      || { rm -f "$_al_t"; echo "mavergreen: could not set $(var_abs "$1" "$3") aside in $1's save area" >&2; return 1; }
  fi
  mv -f "$_al_t" "$_al_v" || { rm -f "$_al_t"; echo "mavergreen: could not link $(var_abs "$1" "$3") to $2" >&2; return 1; }
}
same_as_save() { [ -f "$1" ] && [ ! -L "$1" ] && [ -f "$2" ] && [ ! -L "$2" ] && cmp -s "$2" "$1"; }
original_again() { same_as_save "$R$1" "$2" && apple_stock "$1"; }
same_meta() { [ "$(stat -L -f '%Mp%Lp %u %g' "$1" 2>/dev/null)" = "$(stat -L -f '%Mp%Lp %u %g' "$2" 2>/dev/null)" ]; }
do_system_replace() {
  need_product "$1"
  _pv="$("$PB" -c 'Print :ProductVersion' "$R/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null || true)"
  case "$_pv" in
    10.9|10.9.*) : ;;
    *) die "system-replace is 10.9-only; this volume is macOS ${_pv:-unknown}, where /usr/bin belongs to the sealed system volume" ;;
  esac
  _b="$MG/var/system-replace/$1"
  _o="$(root_only_chain "$_b")" || die "refusing to keep $1's saved originals in $_b: $(offender_text "$_o")"
  if [ -f "$_b/.replaced" ] && [ ! -f "$_b/applied.plist" ]; then
    save_area_root_only || die "could not make $_b, which holds $1's saved originals, root-only; nothing was changed"
    echo "mavergreen: $1 was replaced by an older mavergreen; replacing it again in place, keeping the originals it saved (a one-time migration, not an error)" >&2
    _mig="$1"
  fi
  _entries="$(replaces "$1")"; _adopts="$(adopts "$1")"
  _dup="$(printf '%s\n%s\n' "$_entries" "$_adopts" \
    | awk -F '\t' 'NF { k = $1; if (k ~ /^\/private\/(etc|var|tmp)(\/|$)/) k = substr(k, 9); if (k in s) { print k; exit } s[k] = 1 }')"
  [ -z "$_dup" ] || die "$1 declares $_dup more than once, counting /private/etc, /private/var and /private/tmp as /etc, /var and /tmp; nothing was replaced"
  _old=""; _olda=""; _orig=""; _copies=""; _refr=""
  if [ -f "$_b/applied.plist" ]; then
    _old="$(plist_dict "$_b/applied.plist" replaces)"; _olda="$(plist_dict "$_b/applied.plist" adopts)"
    _orig="$(plist_dict "$_b/applied.plist" originals)"; _copies="$(plist_dict "$_b/applied.plist" copies)"
    _refr="$(plist_dict "$_b/applied.plist" refreshing)"
  elif [ -n "$_mig" ]; then
    legacy_record "$1"
  fi
  _copies0="$_copies"; _orig0="$_orig"
  _stock_all="$(printf '%s\n%s\n%s\n' "$_entries" "$_adopts" "$_old" | cut -f 1)"
  _savedev="$(device_of "$_b")"
  _plan=""
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    replace_shape_ok "$_abs" "$_rel" || die "$1 declares an unsafe replaces entry: '$_abs' -> '$_rel'"
    if tab_has "$_olda" "$_abs"; then
      die "$_abs moves between adopts and replaces in this version of $1; run mavergreen system-restore $1, then mavergreen system-replace $1"
    fi
    [ -e "$MG/$1/$_rel" ] || die "$1 declares $_abs -> $_rel, but $_rel is not in its tree"
    is_real_dir "$MG/$1/$_rel" \
      && die "$1 declares $_abs -> $_rel, but $_rel is a directory; system-replace swaps files and symlinks only"
    _cur="$R$_abs"; _save="$_b$_abs"
    is_real_dir "$_cur" \
      && die "$1 declares $_abs -> $_rel, but $_abs is a directory; system-replace swaps files and symlinks only"
    _o="$(replace_offender "$1" "$_abs" "$_rel")" || die "refusing $_abs: $(offender_text "$_o")"
    [ -d "$_cur" ] && die "$1 declares $_abs -> $_rel, but $_abs is a link to a directory; system-replace swaps files and symlinks only"
    _fresh="$(expected_of "$1" "$_rel")"
    [ -n "$_fresh" ] || die "cannot read $_rel in $1's tree; nothing was replaced"
    _rfr="$(tab_get "$_refr" "$_abs")"
    _exp="$(tab_get "$_copies" "$_abs")"; _exp="${_exp:-$_fresh}"
    _now="$(fingerprint "$_cur")"
    [ -n "$_now" ] || die "could not checksum $_abs; nothing was replaced"
    _was="$(tab_get "$_orig" "$_abs")"
    if [ -z "$_was" ]; then
      _was="$_now"; _orig="$_orig
$_abs	$_was"
    fi
    _act=first
    if [ "$_now" = "$_exp" ] || { [ -n "$_rfr" ] && [ "$_now" = "$_rfr" ]; }; then
      if present "$_save" && same_file "$_save" "$_cur"; then :
      elif [ "$_was" = - ] || present "$_save"; then
        if [ "$_now" != "$_fresh" ] || { is_copy_kind "$_rel" && ! same_meta "$_cur" "$MG/$1/$_rel"; }; then _act=refresh
        else
          _copies="$(tab_drop "$_copies" "$_abs")
$_abs	$_now"
          _refr="$(tab_drop "$_refr" "$_abs")"
          continue
        fi
      elif [ "$_was" = "$_exp" ]; then :
      else die "$_abs is $1's, but the original saved for it is missing from $_b; mavergreen will not go on without it"
      fi
    elif present "$_save"; then
      if same_file "$_save" "$_cur"; then :
      elif same_as_save "$_cur" "$_save" && { [ -n "$_stock_idx" ] || stock_index "$_stock_all"; } \
        && original_again "$_abs" "$_save"; then _act=again
      elif [ -n "$_mig" ]; then
        die "$_abs is no longer the link the older mavergreen put there, and the original it saved is $_save; move what is at $_abs aside and put that original back there by hand, then retry; nothing was replaced"
      else die "$_abs was already saved once and has since changed; run system-restore $1 first"
      fi
    elif [ "$_now" != "$_was" ]; then
      die "$_abs has changed since mavergreen recorded it; run system-restore $1 first"
    fi
    _copies="$(tab_drop "$_copies" "$_abs")
$_abs	$_fresh"
    _refr="$(tab_drop "$_refr" "$_abs")"
    if [ "$_act" = refresh ]; then _refr="$_refr
$_abs	$_now"; fi
    _staged="$MG/$1/$_rel"; is_copy_kind "$_rel" || _staged="symlink:/usr/local/mavergreen/$1/$_rel"
    if staging_blocked "$_cur" "$_staged"; then die "$(staging_path "$_cur") exists and is not a regular file; remove it, then retry"; fi
    if [ "$_act" = first ] && present "$_cur" && ! same_file "$_save" "$_cur" && [ "$(device_of "$(dirname "$_cur")")" != "$_savedev" ]; then
      die "refusing $_abs: it is on another volume than $1's save area ($_b), and originals are saved there by hard link"
    fi
    _plan="$_plan$_act	$_abs	$_rel
"
  done <<EOF
$_entries
EOF
  _drop=""
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    if tab_has "$_entries" "$_abs"; then continue; fi
    replace_shape_ok "$_abs" "$_rel" || die "$1's applied entry '$_abs' -> '$_rel' is unsafe; nothing was replaced"
    if same_as_save "$R$_abs" "$_b$_abs"; then [ -n "$_stock_idx" ] || stock_index "$_stock_all"; fi
    restore_entry_plan "$1" "$_abs" "$(tab_get "$_orig" "$_abs")" "$(tab_get "$_copies" "$_abs")" "$(tab_get "$_refr" "$_abs")" >/dev/null \
      || die "system-replace $1 cannot restore $_abs, which this version no longer declares; nothing was replaced"
    _drop="$_drop$_abs	$_rel
"
  done <<EOF
$_old
EOF
  _aplan=""
  if [ -n "$_adopts" ]; then
    [ -n "$_stock_idx" ] || stock_index "$_stock_all"
    adopt_plan "$1"
  fi
  _adrop=""; _ra_orig="$_orig0"; _ra_copies="$_copies0"
  while IFS="	" read -r _abs _rel _kind; do
    [ -n "$_abs" ] || continue
    if tab_has "$_adopts" "$_abs"; then continue; fi
    if tab_has "$_entries" "$_abs"; then
      die "$_abs is recorded as adopted and is now declared in replaces, so its records collide; run mavergreen system-restore $1, then mavergreen system-replace $1"
    fi
    adopt_shape_ok "$_abs" "$_rel" "$_kind" || die "$1's applied adopts entry '$_abs' -> '$_rel' is unsafe; nothing was replaced"
    _rd_dry=1
    restore_adopted "$1" "$_abs" "$_rel" "$_kind" \
      || die "system-replace $1 cannot restore $_abs, which this version no longer adopts; nothing was replaced"
    _rd_dry=""
    _adrop="$_adrop$_abs	$_rel	$_kind
"
  done <<EOF
$_olda
EOF
  hook_ok "$1" post-system-replace || die "$_rh_msg; nothing was replaced"
  if ! present "$_b/staging"; then _undo_staging="$_b/staging"; fi
  if ! present "$_b"; then _undo_save="$_b"; fi
  save_area_root_only || die "could not make $_b, which holds $1's saved originals, root-only; nothing was replaced"
  mkdir -p "$_b/staging"
  adopt_stage "$1" || die "could not stage $1's adopted files in $_b/staging; nothing was replaced"
  run_hook "$1" pre-system-replace "MAVERGREEN_STAGING=$_b/staging" || die "$_rh_msg; nothing was replaced" "$_rh_rc"
  while IFS="	" read -r _act _abs _rel; do
    case "$_act" in
      swap:skip) _c=- ;;
      swap:*)
        _st="$_b/staging/$_rel"
        [ -f "$_st" ] && [ ! -L "$_st" ] \
          || die "$1's pre-system-replace hook left $_st missing or not a regular file; nothing was replaced"
        stage_perms "$1" "$_abs" "$_rel" || die "could not give the staged $_rel the owner and mode of $_abs; nothing was replaced"
        _c="$(sha256_of "$_st")"; [ -n "$_c" ] || die "could not checksum the staged $_rel; nothing was replaced" ;;
      *) continue ;;
    esac
    _copies="$(tab_drop "$_copies" "$_abs")
$_abs	$_c"
  done <<EOF
$_aplan
EOF
  _decl="$_entries"
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    tab_has "$_entries" "$_abs" || _decl="$_decl
$_abs	$_rel"
  done <<EOF
$_old
EOF
  _adecl="$_adopts"
  while IFS="	" read -r _abs _rel _kind; do
    [ -n "$_abs" ] || continue
    tab_has "$_adopts" "$_abs" || _adecl="$_adecl
$_abs	$_rel	$_kind"
  done <<EOF
$_olda
EOF
  applied_write "$1" "$_decl" "$_orig" "$_copies" "$_adecl" "$_refr" || die "could not write $_b/applied.plist; nothing was replaced"
  _undo_staging=""; _undo_save=""; _undo_files=""; _mig=""
  while IFS="	" read -r _act _abs _rel; do
    [ -n "$_abs" ] || continue
    _ok=0; _sv=""
    if [ "$_act" = first ]; then _sv="$_b$_abs"; fi
    _staged="$MG/$1/$_rel"; is_copy_kind "$_rel" || _staged="symlink:/usr/local/mavergreen/$1/$_rel"
    swap_in "$_staged" "$R$_abs" "$_sv" || _ok=1
    if [ "$_ok" -eq 0 ] && [ "$_act" = refresh ]; then
      _refr="$(tab_drop "$_refr" "$_abs")"
      applied_write "$1" "$_decl" "$_orig" "$_copies" "$_adecl" "$_refr" || _ok=1
    fi
    [ "$_ok" -eq 0 ] || die "system-replace $1 stopped at $_abs; what it replaced before is recorded, and system-restore $1 puts it back"
  done <<EOF
$_plan
EOF
  while IFS="	" read -r _act _abs _rel; do
    case "$_act" in swap:var|swap:system|link) : ;; *) continue ;; esac
    _ok=0
    if [ "$_act" != link ]; then swap_in "$_b/staging/$_rel" "$R$_abs" "$_b$_abs" || _ok=1; fi
    if [ "$_ok" -eq 0 ]; then adopted_set "$1" "$_abs" "$(tab_get "$_copies" "$_abs")" || _ok=1; fi
    if [ "$_ok" -eq 0 ]; then adopt_link "$1" "$_abs" "$_rel" || _ok=1; fi
    [ "$_ok" -eq 0 ] || die "system-replace $1 stopped at $_abs; what it replaced before is recorded, and system-restore $1 puts it back"
  done <<EOF
$_aplan
EOF
  _ra_orig="$_orig0"; _ra_copies="$_copies0"; _ra_refr="$_refr"
  while IFS="	" read -r _abs _rel _kind; do
    [ -n "$_abs" ] || continue
    restore_adopted "$1" "$_abs" "$_rel" "$_kind" \
      || die "system-replace $1 stopped restoring $_abs, which this version no longer adopts; what is left is recorded, and system-restore $1 puts it back"
    _adecl="$(tab_drop "$_adecl" "$_abs")"; _copies="$(tab_drop "$_copies" "$_abs")"
    _orig="$(tab_drop "$(tab_drop "$_orig" "$_abs")" "$(var_abs "$1" "$_rel")")"
    applied_write "$1" "$_decl" "$_orig" "$_copies" "$_adecl" "$_refr" || die "could not drop $_abs from $_b/applied.plist"
  done <<EOF
$_adrop
EOF
  while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    restore_replaced "$1" "$_abs" \
      || die "system-replace $1 stopped restoring $_abs, which this version no longer declares; what is left is recorded, and system-restore $1 puts it back"
    _decl="$(tab_drop "$_decl" "$_abs")"; _orig="$(tab_drop "$_orig" "$_abs")"
    _copies="$(tab_drop "$_copies" "$_abs")"; _refr="$(tab_drop "$_refr" "$_abs")"
    applied_write "$1" "$_decl" "$_orig" "$_copies" "$_adecl" "$_refr" || die "could not drop $_abs from $_b/applied.plist"
  done <<EOF
$_drop
EOF
  : > "$_b/.replaced"
  run_hook "$1" post-system-replace || echo "mavergreen: $_rh_msg; $1 stays replaced" >&2
}
save_area_root_only() { { [ -d "$_b" ] || mkdir -p -m 700 "$_b"; } && chmod 700 "$_b"; }
legacy_record() {
  _lr_pre="/usr/local/mavergreen/$1/"
  _lr_saved="$(cd "$_b" && find . -mindepth 1 -path ./staging -prune -o \( -type f -o -type l \) -print)" \
    || die "could not list $_b, which holds the originals the older mavergreen saved for $1; nothing was replaced"
  _lr_saved="$(printf '%s\n' "$_lr_saved" | sed 's|^\./||' | grep -vxE '\.replaced|applied\.plist(\.tmp)?|(adopted|restored)\.sha256(\.tmp)?' || true)"
  while IFS="	" read -r _lr_abs _lr_rel; do
    [ -n "$_lr_abs" ] || continue
    _lr_c="$R$_lr_abs"; _lr_t="link:$_lr_pre$_lr_rel"
    if owns_replace_link "$_lr_c" "$_lr_pre"; then _lr_t="link:$(readlink "$_lr_c")"
    elif ! present "$_b$_lr_abs"; then continue
    fi
    legacy_entry "$1" "$_lr_abs" "$_lr_rel" "$_lr_t"
  done <<EOF
$_entries
EOF
  while IFS= read -r _lr_p; do
    [ -n "$_lr_p" ] || continue
    _lr_abs="/$_lr_p"; _lr_c="$R$_lr_abs"
    if tab_has "$_entries" "$_lr_abs"; then continue; fi
    owns_replace_link "$_lr_c" "$_lr_pre" \
      || die "$_b$_lr_abs holds the original the older mavergreen saved for $_lr_abs, which this version of $1 no longer declares, and $_lr_abs is no longer $1's link; move anything at $_lr_abs aside and put that original back there by hand, then retry; nothing was replaced"
    _lr_t="$(readlink "$_lr_c")"
    legacy_entry "$1" "$_lr_abs" "${_lr_t#"$_lr_pre"}" "link:$_lr_t"
  done <<EOF
$_lr_saved
EOF
}
legacy_entry() {
  _le_o=-
  if present "$_b$2"; then
    _le_o="$(fingerprint "$_b$2")"
    [ -n "$_le_o" ] || die "could not checksum the original the older mavergreen saved for $2; nothing was replaced"
  fi
  _old="$_old
$2	$3"
  _orig="$_orig
$2	$_le_o"
  _copies="$_copies
$2	$4"
}
resolves_to_dir() {
  [ -d "$1" ] && return 0
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in /*) [ -d "$R$(readlink "$1")" ] ;; *) return 1 ;; esac
}
save_is_stock() { apple_stock_file "$2" "$MG/var/system-replace/$1$2"; }
kept_name() {
  _kn="$MG/kept/$1$2"; _kn_p="$_kn"; _kn_i=0
  while present "$_kn_p"; do _kn_i=$((_kn_i + 1)); _kn_p="$_kn.$_kn_i"; done
  printf '%s' "$_kn_p"
}
keep_save() {
  _ks_s="$MG/var/system-replace/$1$2"; _ks_d="$(kept_name "$1" "$2")"
  { { [ -d "$MG/kept" ] || mkdir -p -m 700 "$MG/kept"; } && chmod 700 "$MG/kept" \
    && { [ -d "$MG/kept/$1" ] || mkdir -m 700 "$MG/kept/$1"; } && chmod 700 "$MG/kept/$1" \
    && mkdir -p "$(dirname "$_ks_d")"; } \
    || { echo "mavergreen: could not make $MG/kept/$1 to keep the original saved for $2; it stays in $MG/var/system-replace/$1" >&2; return 1; }
  if [ ! -L "$_ks_s" ] && [ "$(stat -f %l "$_ks_s")" -gt 1 ]; then
    _ks_c="$MG/var/system-replace/$1/staging/.mavergreen-kept"
    { mkdir -p "$(dirname "$_ks_c")" && rm -f "$_ks_c" && cp -p "$_ks_s" "$_ks_c" && chmod a-s "$_ks_c" && mv "$_ks_c" "$_ks_d"; } \
      || { rm -f "$_ks_c"; echo "mavergreen: could not move a copy of the original saved for $2 to ${_ks_d#"$R"}; it stays in $MG/var/system-replace/$1" >&2; return 1; }
    rm -f "$_ks_s" || { echo "mavergreen: could not remove $_ks_s, already kept as ${_ks_d#"$R"}" >&2; return 1; }
  else
    { { [ -L "$_ks_s" ] || chmod a-s "$_ks_s"; } && mv "$_ks_s" "$_ks_d"; } \
      || { echo "mavergreen: could not move the original saved for $2 to ${_ks_d#"$R"}; it stays in $MG/var/system-replace/$1" >&2; return 1; }
  fi
  echo "mavergreen: the original saved for $2 is not Apple's, so it is kept as ${_ks_d#"$R"}, any setuid or setgid bit cleared"
}
left_save() {
  present "$MG/var/system-replace/$1$2" || return 0
  if save_is_stock "$1" "$2"; then
    rm -f "$MG/var/system-replace/$1$2" || { echo "mavergreen: could not remove the original saved for $2" >&2; return 1; }
    return 0
  fi
  keep_save "$1" "$2"
}
left_report() {
  _lr_s=""
  if present "$MG/var/system-replace/$1$2"; then
    if save_is_stock "$1" "$2"; then _lr_s=" and discards the original saved for it, which an Apple receipt lists"
    fi
  fi
  case "$3" in
    stock) echo "mavergreen: $2 is Apple's own file again (an Apple receipt lists it), so restore leaves it$_lr_s" ;;
    newer) echo "mavergreen: $2 is Apple's again (this volume is no longer Mac OS X 10.9), so restore leaves it$_lr_s" ;;
    *) echo "mavergreen: $2 still holds $1's copy; this volume is no longer Mac OS X 10.9, so restore leaves it$_lr_s" ;;
  esac
}
restore_entry() {
  _re_act="$(restore_entry_plan "$@")" || return 1
  case "$_re_act" in
    rmsave) rm -f "$MG/var/system-replace/$1$2" || { echo "mavergreen: could not remove $MG/var/system-replace/$1$2, a second link to $2" >&2; return 1; } ;;
    mvsave) mv -f "$MG/var/system-replace/$1$2" "$R$2" || { echo "mavergreen: could not restore $2" >&2; return 1; } ;;
    rmcur) rm -f "$R$2" || { echo "mavergreen: could not remove $2" >&2; return 1; } ;;
    left:*)
      left_report "$1" "$2" "${_re_act#left:}"
      left_save "$1" "$2" || return 1 ;;
  esac
}
restore_entry_plan() {
  _re_cur="$R$2"; _re_save="$MG/var/system-replace/$1$2"; _re_now="$(fingerprint "$_re_cur")"; _re_ours=""
  if { [ -n "$4" ] && [ "$_re_now" = "$4" ]; } || { [ -n "${5:-}" ] && [ "$_re_now" = "$5" ]; }; then _re_ours=1; fi
  if present "$_re_save" && same_file "$_re_save" "$_re_cur"; then echo rmsave; return 0; fi
  if [ -n "$_ra_newer" ]; then
    if [ -n "$_re_ours" ]; then echo left:ours; else echo left:newer; fi
    return 0
  fi
  if present "$_re_save"; then
    if [ -z "$_re_ours" ]; then
      if original_again "$2" "$_re_save"; then echo mvsave; return 0; fi
      if [ -n "$_ra_owns" ] && apple_stock "$2"; then echo left:stock; return 0; fi
      echo "mavergreen: $2 was changed after mavergreen installed it; keeping the saved original" >&2; return 1
    fi
    if resolves_to_dir "$_re_cur"; then
      echo "mavergreen: $2 now resolves to a directory; keeping the saved original rather than moving it inside" >&2; return 1
    fi
    echo mvsave; return 0
  fi
  if [ -n "$3" ] && [ "$_re_now" = "$3" ]; then echo none; return 0; fi
  if [ "$3" = - ] && [ -n "$_re_ours" ]; then echo rmcur; return 0; fi
  if [ -z "$_re_ours" ] && [ -n "$_ra_owns" ] && apple_stock "$2"; then echo left:stock; return 0; fi
  if [ "$3" = - ]; then
    echo "mavergreen: $2 was changed after mavergreen installed it, and it had no original to put back; leaving it" >&2
  else
    echo "mavergreen: $2 matches neither its recorded original nor mavergreen's copy, and no saved original is left; leaving it" >&2
  fi
  return 1
}
restore_adopted() {
  _rd_cur="$R$2"; _rd_var="$MG/var/$1/$3"; _rd_save="$MG/var/system-replace/$1$2"
  _rd_was="$(tab_get "$_ra_orig" "$2")"; _rd_cp="$(tab_get "$_ra_copies" "$2")"
  _rd_t="$(staging_path "$_rd_cur")"
  if [ -z "$_rd_dry" ] && [ -z "$_ra_newer" ] && [ -f "$_rd_t" ] && [ ! -L "$_rd_t" ]; then
    rm -f "$_rd_t" || { echo "mavergreen: could not remove the leftover staging file $_rd_t" >&2; return 1; }
  fi
  _rd_t="$(staging_path "$_rd_var")"
  if [ -z "$_rd_dry" ] && { { [ -f "$_rd_t" ] && [ ! -L "$_rd_t" ]; } || { [ -L "$_rd_t" ] && [ "$(readlink "$_rd_t")" = "$2" ]; }; }; then
    rm -f "$_rd_t" || { echo "mavergreen: could not remove the leftover staging file $_rd_t" >&2; return 1; }
  fi
  if ! tab_has "$_ra_copies" "$2" || [ "$_rd_cp" = - ]; then return 0; fi
  _rd_now="$(fingerprint "$_rd_cur")"; _rd_vnow="$(fingerprint "$_rd_var")"
  if [ -z "$_rd_now" ] || [ -z "$_rd_vnow" ]; then
    echo "mavergreen: could not checksum $2 or $(var_abs "$1" "$3"); leaving both" >&2; return 1
  fi
  _rd_why=""
  if [ -n "$_ra_owns" ] && ! { present "$_rd_save" && same_file "$_rd_save" "$_rd_cur"; } \
    && ! { ! present "$_rd_save" && [ "$_rd_now" = "$_rd_was" ]; }; then
    if [ -n "$_ra_newer" ]; then
      _rd_why=newer; [ "$_rd_now" != "$_rd_cp" ] || _rd_why=ours
    elif [ "$_rd_now" != "$_rd_cp" ] && apple_stock "$2"; then _rd_why=stock
    fi
  fi
  if [ -n "$_rd_why" ]; then
    [ -z "$_rd_dry" ] || return 0
    left_report "$1" "$2" "$_rd_why"
    if [ "$_rd_vnow" = "link:$2" ]; then
      if [ -f "$_rd_cur" ] && [ ! -L "$_rd_cur" ]; then
        { rm -f "$_rd_t" && cp -p "$_rd_cur" "$_rd_t" && mv -f "$_rd_t" "$_rd_var"; } \
          || { rm -f "$_rd_t"; echo "mavergreen: could not copy $2 to $(var_abs "$1" "$3"), which links to it" >&2; return 1; }
      else
        rm -f "$_rd_var" || { echo "mavergreen: could not remove $(var_abs "$1" "$3"), a link to $2, which is not a file" >&2; return 1; }
      fi
    fi
    _rd_sys=""; if [ -f "$_rd_cur" ] && [ ! -L "$_rd_cur" ]; then _rd_sys="$_rd_now"; fi
    _rd_vs=""; if [ -f "$_rd_var" ] && [ ! -L "$_rd_var" ]; then _rd_vs="$(sha256_of "$_rd_var")"; fi
    restored_set "$1" "$2" "$_rd_sys" "$_rd_vs" \
      || { echo "mavergreen: could not record what restoring $2 leaves in place" >&2; return 1; }
    left_save "$1" "$2" || return 1
    return 0
  fi
  if [ "$_rd_vnow" = "link:$2" ]; then
    if [ -L "$_rd_cur" ] || [ ! -f "$_rd_cur" ]; then
      echo "mavergreen: $2 is adopted by $1, but it is missing or no longer a real file, so there is nothing to move back to $(var_abs "$1" "$3"); leaving both" >&2
      return 1
    fi
    if ! present "$_rd_save" && [ "$_rd_was" != - ]; then
      echo "mavergreen: the original saved for $2 is missing from $MG/var/system-replace/$1; leaving $2 and $(var_abs "$1" "$3") as they are" >&2
      return 1
    fi
    _rd_sys=""
    if present "$_rd_save"; then
      _rd_sys="$(sha256_of "$_rd_save")"
      [ -n "$_rd_sys" ] || { echo "mavergreen: could not checksum the original saved for $2; leaving it" >&2; return 1; }
    fi
    if [ -z "$_rd_dry" ]; then
      if [ "${4:-}" = config ]; then restore_report "$1" "$2" "$_rd_now"; fi
      restored_set "$1" "$2" "$_rd_sys" "$_rd_now" \
        || { echo "mavergreen: could not record what restoring $2 puts back; leaving it" >&2; return 1; }
      { rm -f "$_rd_t" && cp -p "$_rd_cur" "$_rd_t" && mv -f "$_rd_t" "$_rd_var"; } \
        || { rm -f "$_rd_t"; echo "mavergreen: could not move the live $2 back to $(var_abs "$1" "$3")" >&2; return 1; }
    fi
    _rd_vnow="$_rd_now"
  fi
  if present "$_rd_save"; then
    if same_file "$_rd_save" "$_rd_cur"; then
      [ -n "$_rd_dry" ] || rm -f "$_rd_save" || { echo "mavergreen: could not remove $_rd_save, a second link to $2" >&2; return 1; }
      return 0
    fi
    if [ -f "$_rd_cur" ] && [ ! -L "$_rd_cur" ] && { [ "$_rd_now" = "$_rd_cp" ] || [ "$_rd_now" = "$_rd_vnow" ]; }; then
      [ -n "$_rd_dry" ] || mv -f "$_rd_save" "$_rd_cur" || { echo "mavergreen: could not restore $2" >&2; return 1; }
      return 0
    fi
    echo "mavergreen: $2 was changed after mavergreen adopted it, and $(var_abs "$1" "$3") does not hold the change; keeping the saved original" >&2
    return 1
  fi
  if [ "$_rd_was" = - ]; then
    present "$_rd_cur" || return 0
    if [ -f "$_rd_cur" ] && [ ! -L "$_rd_cur" ] && { [ "$_rd_now" = "$_rd_cp" ] || [ "$_rd_now" = "$_rd_vnow" ]; }; then
      [ -n "$_rd_dry" ] || rm -f "$_rd_cur" || { echo "mavergreen: could not remove $2" >&2; return 1; }
      return 0
    fi
    echo "mavergreen: $2 was absent when mavergreen recorded it, and what is there now is not what mavergreen adopted; leaving it (move it aside, then retry)" >&2
    return 1
  fi
  [ "$_rd_now" = "$_rd_was" ] && return 0
  echo "mavergreen: $2 matches neither its recorded original nor what mavergreen adopted, and no saved original is left; leaving it" >&2
  return 1
}
restore_report() {
  _rp_cur="$R$2"; _rp_orig="$MG/var/system-replace/$1$2"
  _rp_rec="$(K="$2" awk 'substr($0, 67) == ENVIRON["K"] { v = substr($0, 1, 64) } END { print v }' \
    "$MG/var/system-replace/$1/adopted.sha256" 2>/dev/null)" || _rp_rec=""
  [ "$3" != "$_rp_rec" ] || return 0
  present "$_rp_orig" || _rp_orig=/dev/null
  _rp_rc=0; _rp_d="$(diff -u "$_rp_orig" "$_rp_cur")" || _rp_rc=$?
  if [ "$_rp_rc" -gt 1 ]; then echo "mavergreen: could not compare $2 with the original being restored" >&2; return 0; fi
  [ -n "$_rp_d" ] || return 0
  printf 'mavergreen: settings in %s that the restored original does not have:\n%s\n' "$2" "$_rp_d"
}
save_area_extra() {
  _sx_found="$(cd "$1" && find . -mindepth 1 \( -type f -o -type l \))" || return 1
  printf '%s\n' "$_sx_found" | sed 's|^\./||' \
    | grep -vxE '\.replaced|applied\.plist(\.tmp)?|(adopted|restored)\.sha256(\.tmp)?|staging/.*' || true
}
clear_save_area() {
  if [ -z "$_sr_keep" ]; then rm -f "$1/.replaced" || return 1; fi
  for _cs in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    { [ -e "$_cs" ] || [ -L "$_cs" ]; } || continue
    case "$_cs" in "$1/restored.sha256"|"$1/applied.plist"|"$1/.replaced") continue ;; esac
    rm -rf "$_cs" || return 1
  done
  [ -z "$_sr_keep" ] || return 0
  rm -f "$1/applied.plist" || return 1
  [ -f "$1/restored.sha256" ] || rm -rf "$1"
}
restore_replaced() {
  _rq_cp="$(tab_get "$_ra_copies" "$2")"; _rq_t="$(staging_path "$R$2")"
  if [ -n "$_ra_newer" ]; then :
  elif { [ -f "$_rq_t" ] && [ ! -L "$_rq_t" ]; } || { [ -L "$_rq_t" ] && [ "link:$(readlink "$_rq_t")" = "$_rq_cp" ]; }; then
    rm -f "$_rq_t" || { echo "mavergreen: could not remove the leftover staging file $_rq_t" >&2; return 1; }
  fi
  restore_entry "$1" "$2" "$(tab_get "$_ra_orig" "$2")" "$_rq_cp" "$(tab_get "$_ra_refr" "$2")"
}
restore_prepare() {
  _ra_b="$MG/var/system-replace/$1"; _ra_fail=0; _ra_owns=1; _ra_newer=""; _ra_vbad=""
  _ra_vf="$R/System/Library/CoreServices/SystemVersion.plist"; _ra_pv=""
  if [ -f "$_ra_vf" ]; then _ra_pv="$("$PB" -c 'Print :ProductVersion' "$_ra_vf" 2>/dev/null)" || _ra_pv=""; fi
  case "$_ra_pv" in
    10.9|10.9.*) : ;;
    [0-9]*.[0-9]*) _ra_newer=1 ;;
    *) _ra_vbad=1 ;;
  esac
  _ra_repl="$(plist_dict "$_ra_b/applied.plist" replaces)"
  _ra_orig="$(plist_dict "$_ra_b/applied.plist" originals)"
  _ra_copies="$(plist_dict "$_ra_b/applied.plist" copies)"
  _ra_adopts="$(plist_dict "$_ra_b/applied.plist" adopts)"
  _ra_refr="$(plist_dict "$_ra_b/applied.plist" refreshing)"
  _ra_stockl="$(printf '%s\n%s\n' "$_ra_repl" "$_ra_adopts" | cut -f 1)"
  _ra_need=""
  while IFS="	" read -r _ra_abs _ra_rel; do
    [ -n "$_ra_abs" ] && [ -f "$R$_ra_abs" ] && [ ! -L "$R$_ra_abs" ] || continue
    _ra_fp="$(fingerprint "$R$_ra_abs")"
    [ "$_ra_fp" = "$(tab_get "$_ra_copies" "$_ra_abs")" ] || [ "$_ra_fp" = "$(tab_get "$_ra_refr" "$_ra_abs")" ] || _ra_need=1
  done <<EOF
$_ra_stockl
EOF
  if { [ -n "$_ra_need" ] || [ -n "$_ra_newer" ]; } && [ -z "$_stock_idx" ]; then stock_index "$_ra_stockl"; fi
}
restore_dry() {
  if [ -n "$_ra_vbad" ]; then
    echo "mavergreen: cannot read this volume's macOS version from $_ra_vf, so restore cannot tell whether it may write system paths" >&2
    return 1
  fi
  _rd_dry=1; _ra_dfail=0
  while IFS="	" read -r _ra_abs _ra_rel _ra_kind; do
    [ -n "$_ra_abs" ] || continue
    if ! adopt_shape_ok "$_ra_abs" "$_ra_rel" "$_ra_kind"; then
      echo "mavergreen: $1's applied adopts entry '$_ra_abs' -> '$_ra_rel' is unsafe; not touching it" >&2
      _ra_dfail=1; continue
    fi
    restore_adopted "$1" "$_ra_abs" "$_ra_rel" "$_ra_kind" || _ra_dfail=1
  done <<EOF
$_ra_adopts
EOF
  while IFS="	" read -r _ra_abs _ra_rel; do
    [ -n "$_ra_abs" ] || continue
    if ! replace_shape_ok "$_ra_abs" "$_ra_rel"; then
      echo "mavergreen: $1's applied entry '$_ra_abs' -> '$_ra_rel' is unsafe; not touching it" >&2
      _ra_dfail=1; continue
    fi
    restore_entry_plan "$1" "$_ra_abs" "$(tab_get "$_ra_orig" "$_ra_abs")" "$(tab_get "$_ra_copies" "$_ra_abs")" \
      "$(tab_get "$_ra_refr" "$_ra_abs")" >/dev/null || _ra_dfail=1
  done <<EOF
$_ra_repl
EOF
  _rd_dry=""
  if ! _rd_left="$(save_area_extra "$_ra_b")"; then
    echo "mavergreen: could not list $_ra_b; keeping it and everything saved in it" >&2; _ra_dfail=1
  else
    _rd_left="$(printf '%s\n' "$_rd_left" | N="$(printf '%s\n' "$_ra_stockl" | sed 's|^/||')" \
      awk 'BEGIN { n = split(ENVIRON["N"], a, "\n"); for (i = 1; i <= n; i++) k[a[i]] = 1 } NF && !($0 in k)')"
    if [ -n "$_rd_left" ]; then
      echo "mavergreen: $_ra_b holds saved files applied.plist does not name; keeping them: $(printf '%s' "$_rd_left" | tr '\n' ' ')" >&2
      _ra_dfail=1
    fi
  fi
  hook_ok "$1" post-system-restore || { echo "mavergreen: $_rh_msg" >&2; _ra_dfail=1; }
  [ "$_ra_dfail" -eq 0 ]
}
restore_applied() {
  restore_prepare "$1"
  restore_dry "$1" || { echo "mavergreen: nothing of $1's was restored; fix what is named above, then retry" >&2; return 1; }
  if [ -z "$_sr_keep" ]; then
    rm -f "$_ra_b/.replaced" || { echo "mavergreen: could not remove $_ra_b/.replaced; nothing was restored" >&2; return 1; }
  fi
  while IFS="	" read -r _ra_abs _ra_rel _ra_kind; do
    [ -n "$_ra_abs" ] || continue
    if ! adopt_shape_ok "$_ra_abs" "$_ra_rel" "$_ra_kind"; then
      echo "mavergreen: $1's applied adopts entry '$_ra_abs' -> '$_ra_rel' is unsafe; not touching it" >&2
      _ra_fail=1; continue
    fi
    restore_adopted "$1" "$_ra_abs" "$_ra_rel" "$_ra_kind" || { _ra_fail=1; continue; }
    [ -n "$_sr_keep" ] || _ra_adopts="$(tab_drop "$_ra_adopts" "$_ra_abs")"
    _ra_copies="$(tab_drop "$_ra_copies" "$_ra_abs")"
    _ra_orig="$(tab_drop "$(tab_drop "$_ra_orig" "$_ra_abs")" "$(var_abs "$1" "$_ra_rel")")"
    applied_write "$1" "$_ra_repl" "$_ra_orig" "$_ra_copies" "$_ra_adopts" "$_ra_refr" \
      || { echo "mavergreen: could not drop $_ra_abs from $_ra_b/applied.plist" >&2; _ra_fail=1; }
  done <<EOF
$_ra_adopts
EOF
  while IFS="	" read -r _ra_abs _ra_rel; do
    [ -n "$_ra_abs" ] || continue
    if ! replace_shape_ok "$_ra_abs" "$_ra_rel"; then
      echo "mavergreen: $1's applied entry '$_ra_abs' -> '$_ra_rel' is unsafe; not touching it" >&2
      _ra_fail=1; continue
    fi
    restore_replaced "$1" "$_ra_abs" || { _ra_fail=1; continue; }
    _ra_repl="$(tab_drop "$_ra_repl" "$_ra_abs")"; _ra_orig="$(tab_drop "$_ra_orig" "$_ra_abs")"
    _ra_copies="$(tab_drop "$_ra_copies" "$_ra_abs")"; _ra_refr="$(tab_drop "$_ra_refr" "$_ra_abs")"
    applied_write "$1" "$_ra_repl" "$_ra_orig" "$_ra_copies" "$_ra_adopts" "$_ra_refr" \
      || { echo "mavergreen: could not drop $_ra_abs from $_ra_b/applied.plist" >&2; _ra_fail=1; }
  done <<EOF
$_ra_repl
EOF
  [ "$_ra_fail" -eq 0 ] || return 1
  if ! _ra_left="$(save_area_extra "$_ra_b")"; then
    echo "mavergreen: could not list $_ra_b; keeping it and everything saved in it" >&2
    return 1
  fi
  if [ -n "$_ra_left" ]; then
    echo "mavergreen: $_ra_b holds saved files applied.plist does not name; keeping them: $(printf '%s' "$_ra_left" | tr '\n' ' ')" >&2
    return 1
  fi
  clear_save_area "$_ra_b" || { echo "mavergreen: could not clear $_ra_b" >&2; return 1; }
}
restore_saved() {
  if [ -f "$MG/var/system-replace/$1/applied.plist" ]; then restore_applied "$1"; else restore_legacy "$1"; fi
}
post_restore_hook() {
  run_hook "$1" post-system-restore && return 0
  echo "mavergreen: $_rh_msg; $1's originals stay restored" >&2
  return 1
}
do_system_restore() {
  need_product "$1"
  restore_saved "$1" || return 1
  post_restore_hook "$1"
}
restore_legacy() {
  _b="$MG/var/system-replace/$1"
  _entries="$(replaces "$1")"
  _want_prefix="/usr/local/mavergreen/$1/"
  _rfail=0
  _saved=""
  if [ -d "$_b" ]; then
    _saved="$(cd "$_b" && find . -mindepth 1 -path ./staging -prune -o \( -type f -o -type l \) -print | sed 's|^\./||' \
      | grep -vxE '\.replaced|applied\.plist(\.tmp)?|(adopted|restored)\.sha256(\.tmp)?' || true)"
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
  if present "$_b/staging"; then
    echo "mavergreen: $1: $_b holds an unfinished staging directory; it was left in place" >&2
    _rfail=1
  fi
  if [ "$_rfail" -eq 0 ]; then clear_save_area "$_b" || _rfail=1; fi
  [ "$_rfail" -eq 0 ]
}
replace_drift() {
  _dr_applied=""; _dr_copies=""; _dr_refr=""
  if [ -f "$MG/var/system-replace/$1/applied.plist" ]; then
    _dr_applied=1; _dr_copies="$(replace_record "$1" copies)"; _dr_refr="$(replace_record "$1" refreshing)"
  fi
  _msgs="$(replace_record "$1" replaces | while IFS="	" read -r _abs _rel; do
    [ -n "$_abs" ] || continue
    if [ -n "$_dr_applied" ] && is_copy_kind "$_rel"; then
      _dr_fp="$(fingerprint "$R$_abs")"; _dr_rf="$(tab_get "$_dr_refr" "$_abs")"
      if [ -L "$R$_abs" ] || { [ "$_dr_fp" != "$(tab_get "$_dr_copies" "$_abs")" ] && { [ -z "$_dr_rf" ] || [ "$_dr_fp" != "$_dr_rf" ]; }; }; then
        echo "mavergreen: $_abs is no longer $1's copy"
      elif ! cmp -s "$R$_abs" "$MG/$1/$_rel"; then
        echo "mavergreen: $_abs is stale: it no longer matches /usr/local/mavergreen/$1/$_rel"; fi
    elif [ -L "$R$_abs" ] && [ "$(readlink "$R$_abs")" = "/usr/local/mavergreen/$1/$_rel" ]; then :; else
      echo "mavergreen: $_abs is no longer $1's replacement"; fi
  done
  replace_record "$1" adopts | while IFS="	" read -r _abs _rel _kind; do
    [ -n "$_abs" ] && tab_has "$_dr_copies" "$_abs" && [ "$(tab_get "$_dr_copies" "$_abs")" != - ] || continue
    if [ -L "$R$_abs" ] || { [ -e "$R$_abs" ] && [ ! -f "$R$_abs" ]; }; then
      echo "mavergreen: $_abs is adopted by $1, but it is no longer a real file"
    elif [ ! -e "$R$_abs" ]; then echo "mavergreen: $_abs is adopted by $1, but it is missing"; fi
    [ "$(fingerprint "$MG/var/$1/$_rel")" = "link:$_abs" ] || echo "mavergreen: $(var_abs "$1" "$_rel") is no longer $1's link to $_abs"
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
save_plan() {
  _sv_plan=""; _sv_b="$MG/var/system-replace/$1"
  _sv_ad=""
  if [ -f "$_sv_b/applied.plist" ]; then _sv_ad="$(plist_dict "$_sv_b/applied.plist" adopts)"; fi
  if [ -f "$_sv_b/restored.sha256" ]; then
    _sv_rv="$(awk 'substr($0, 66, 4) == "var " { print substr($0, 70) }' "$_sv_b/restored.sha256")" \
      || die "could not read $_sv_b/restored.sha256; uninstall stopped, nothing removed"
    _sv_ad="$(printf '%s\n' "$_sv_ad"; adopts "$1" | RV="$_sv_rv" awk -F '\t' 'BEGIN { n = split(ENVIRON["RV"], a, "\n"); for (i = 1; i <= n; i++) k[a[i]] = 1 } $1 in k')"
    _sv_ad="$(printf '%s\n' "$_sv_ad" | awk -F '\t' 'NF && !s[$1]++')"
  fi
  [ -n "$_sv_ad" ] || return 0
  while IFS="	" read -r _sv_abs _sv_rel _sv_kind; do
    [ -n "$_sv_abs" ] && [ "$_sv_kind" = config ] && adopt_shape_ok "$_sv_abs" "$_sv_rel" "$_sv_kind" || continue
    _sv_v="$MG/var/$1/$_sv_rel"; _sv_src="$_sv_v"
    if [ "$(fingerprint "$_sv_v")" = "link:$_sv_abs" ]; then _sv_src="$R$_sv_abs"; fi
    [ -f "$_sv_src" ] && [ ! -L "$_sv_src" ] || continue
    _sv_c="$(sha256_of "$_sv_src")"
    [ -n "$_sv_c" ] || die "could not checksum $_sv_src; uninstall stopped, nothing removed"
    _sv_seed="$(seed_rec "$1" "$_sv_rel")" || die "could not read $1's seed records; uninstall stopped, nothing removed"
    [ "$_sv_c" != "$_sv_seed" ] || continue
    _sv_s="$R$_sv_abs.mavergreen-save"
    [ -d "$(dirname "$_sv_s")" ] \
      || die "$(dirname "$_sv_abs") is missing, so uninstall cannot keep the $_sv_abs settings in $_sv_abs.mavergreen-save; create it, then retry; uninstall stopped, nothing removed"
    if [ "$(fingerprint "$_sv_s")" != "$_sv_c" ]; then
      if [ -d "$_sv_s" ]; then
        die "$_sv_abs.mavergreen-save is a directory or a link to one, so uninstall cannot keep the $_sv_abs settings there; move it aside, then retry; uninstall stopped, nothing removed"
      fi
      if staging_blocked "$_sv_s" ""; then
        die "$(staging_path "$_sv_s") exists and is not a regular file; remove it, then retry; uninstall stopped, nothing removed"
      fi
    fi
    _sv_plan="$_sv_plan$_sv_c	$_sv_abs	$_sv_rel
"
  done <<EOT
$_sv_ad
EOT
}
save_write() {
  while IFS="	" read -r _sw_c _sw_abs _sw_rel; do
    [ -n "$_sw_abs" ] || continue
    _sw_v="$MG/var/$1/$_sw_rel"; _sw_s="$R$_sw_abs.mavergreen-save"; _sw_t="$(staging_path "$R$_sw_abs.mavergreen-save")"
    [ -f "$_sw_v" ] && [ ! -L "$_sw_v" ] && [ "$(sha256_of "$_sw_v")" = "$_sw_c" ] \
      || die "$(var_abs "$1" "$_sw_rel") no longer holds the $_sw_abs settings uninstall planned to keep; uninstall stopped before removing anything else -- retry"
    if [ -f "$_sw_t" ] && [ ! -L "$_sw_t" ]; then
      rm -f "$_sw_t" || die "could not remove the leftover $_sw_t; uninstall stopped before removing anything else"
    fi
    if [ "$(fingerprint "$_sw_s")" != "$_sw_c" ]; then
      [ ! -d "$_sw_s" ] \
        || die "$_sw_abs.mavergreen-save is a directory or a link to one; uninstall stopped before removing anything else"
      { cp -p "$_sw_v" "$_sw_t" && [ "$(sha256_of "$_sw_t")" = "$_sw_c" ] && mv -f "$_sw_t" "$_sw_s"; } \
        || { rm -f "$_sw_t"; die "could not write $_sw_abs.mavergreen-save and check it; uninstall stopped before removing anything else"; }
    fi
    echo "mavergreen: $_sw_abs.mavergreen-save keeps the settings $1 used in $_sw_abs"
  done <<EOT
$_sv_plan
EOT
}
do_uninstall() {
  need_product "$1"
  _ub="$MG/var/system-replace/$1"
  if [ -d "$_ub" ] && [ ! -f "$_ub/.replaced" ] && [ ! -f "$_ub/applied.plist" ]; then
    _ux="$(save_area_extra "$_ub")" || die "could not list $_ub; uninstall stopped, nothing removed"
    [ -z "$_ux" ] \
      || die "$_ub holds saved originals that no applied.plist names ($(printf '%s' "$_ux" | tr '\n' ' ')); run mavergreen system-restore $1 first; uninstall stopped, nothing removed"
  fi
  if [ -f "$_ub/applied.plist" ]; then
    restore_prepare "$1"
    restore_dry "$1" || die "$1's restore would refuse what is named above; fix it, then retry; uninstall stopped, nothing removed"
  fi
  save_plan "$1"
  run_hook "$1" pre-uninstall || die "$_rh_msg; uninstall stopped, nothing removed" "$_rh_rc"
  _failed=0
  if [ -f "$_ub/.replaced" ] || [ -f "$_ub/applied.plist" ]; then
    _sr_keep=1
    restore_saved "$1" \
      || die "system-restore failed for $1; uninstall stopped before removing anything else -- fix it, then retry"
    post_restore_hook "$1" || _failed=1
  fi
  save_write "$1"
  _g="$(group_of "$1")"; _id="$(mf "$1" identifier)"
  unlink_product "$1"
  remove_listed "$1" outside || _failed=1
  remove_listed "$1" generated || _failed=1
  for _d in "$_ub" "$MG/$1" "$MG/var/$1"; do
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
