#!/bin/sh
# platform: host-agnostic -- stevedore expands the pkg and reads plists; gzip and cpio read each Payload
#   usage: pkg_read.sh expand PKG DIR
#          pkg_read.sh payload PKG COMPONENT_ID DIR [PATTERN...]
#          pkg_read.sh list PKG COMPONENT_ID
#          pkg_read.sh plist PKG KEY...
#          pkg_read.sh facts PKG
#          Reads a family .pkg, a product archive or a flat component, the same way on Linux, a modern
#          Mac and 10.9, with no pkgutil, lsbom or PlistBuddy. Every PKG may instead be a directory that
#          `expand` (or pkgutil --expand) made, so a caller expands once and reads many times.
#          A component is picked by the identifier in its PackageInfo, never by position.
#          expand: stevedore expand PKG into DIR, which must not exist.
#          payload: unpack COMPONENT_ID's Payload into DIR (made when missing); PATTERNs are cpio
#          patterns that limit it to the members they match.
#          list: one line per Payload member, sorted bytewise (LC_ALL=C):
#            PATH<TAB>MODE<TAB>UID<TAB>GID
#          PATH as the Payload names it (./usr/...), MODE the octal st_mode with no leading zero
#          (40755, 100644, 120755), UID and GID numeric, as the cpio header carries them: the format of
#          `lsbom -p fmug`. A symlink's PATH stops at its " -> ".
#          plist: the product manifest, the one opt/mavergreen/SHORT/mavergreen.plist any component
#          installs (install-location applied), or usr/local/mavergreen/SHORT/mavergreen.plist in a
#          pinned pre-flag-day release; prints each KEY's scalar value, one per line,
#          in order. A missing key fails.
#          facts: sorted lines of `SUBJECT FACT VALUE...`:
#            distribution host-architectures ARCHS
#            distribution os-version-min VERSION      (and os-version-max, when declared)
#            distribution pkg-ref ID VERSION
#            component ID version VERSION
#            component ID install-location PATH
#            component ID script NAME                 (one per file in the component's Scripts)
#          A flat component has no distribution lines.
#          Exit 1 on an unreadable pkg, a missing or repeated component, a failed gzip or cpio (named
#          as such), a missing manifest or key; 2 on a usage error or a missing gzip or cpio.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() {
  echo "usage: pkg_read.sh expand PKG DIR | payload PKG COMPONENT_ID DIR [PATTERN...] | list PKG COMPONENT_ID | plist PKG KEY... | facts PKG" >&2
  exit 2
}
die() { echo "pkg_read: $*" >&2; exit 1; }
[ $# -ge 2 ] || usage
cmd=$1; PKG=$2; shift 2
case "$cmd" in
  expand) [ $# -eq 1 ] || usage ;;
  payload) [ $# -ge 2 ] || usage ;;
  list) [ $# -eq 1 ] || usage ;;
  plist) [ $# -ge 1 ] || usage ;;
  facts) [ $# -eq 0 ] || usage ;;
  *) usage ;;
esac
case "$cmd" in
  payload|list|plist)
    for tool in gzip cpio; do
      command -v "$tool" > /dev/null 2>&1 || { echo "pkg_read: needs $tool to read a Payload; install the $tool package" >&2; exit 2; }
    done ;;
esac
[ -e "$PKG" ] || die "no pkg $PKG"
_tmp="${TMPDIR:-/tmp}"
T="$(mktemp -d "${_tmp%/}/pkg_read.XXXXXX")" || die "cannot make a temporary directory"
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stevedore() {
  [ -n "${_sd:-}" ] || _sd="$(sh "$SELF/fetch_stevedore.sh")" || die "no stevedore to read $PKG with"
  "$_sd" "$@"
}
expanded() {
  if [ -d "$PKG" ]; then X=$PKG; return 0; fi
  X="$T/x"
  stevedore expand "$PKG" "$X" > /dev/null || die "could not expand $PKG"
}
XML='
function unent(v) {
  gsub(/&lt;/, "<", v); gsub(/&gt;/, ">", v); gsub(/&quot;/, "\"", v); gsub(/&apos;/, "\047", v); gsub(/&amp;/, "\\&", v)
  return v
}
function attr(e, n,   p) {
  p = "[ \t]" n "=\"[^\"]*\""
  if (!match(e, p)) return ""
  return unent(substr(e, RSTART + length(n) + 3, RLENGTH - length(n) - 4))
}
function next_el(tag,   p) {
  p = "<" tag "[ \t/>][^>]*>"
  if (!match(rest, p)) return 0
  el = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
  return 1
}
{ s = s " " $0 }
'
pkginfo() {
  awk "$XML"'function f(v) { return v == "" ? "-" : v }
    END { rest = s; if (next_el("pkg-info")) printf "%s\t%s\t%s", f(attr(el, "identifier")), f(attr(el, "version")), f(attr(el, "install-location")) }' "$1"
}
components() {
  for _pi in "$X/PackageInfo" "$X"/*/PackageInfo; do
    [ -f "$_pi" ] || continue
    _l="$(pkginfo "$_pi")" || return 1
    [ -n "$_l" ] || continue
    printf '%s\t%s\n' "$_l" "${_pi%/PackageInfo}"
  done
}
component() {
  components > "$T/comps" || die "could not read the PackageInfo files of $PKG"
  _n="$(awk -F '\t' -v id="$1" '$1 == id' "$T/comps" | grep -c . || :)"
  [ "$_n" = 1 ] || die "expected one component $1 in $PKG, found $_n"
  C="$(awk -F '\t' -v id="$1" '$1 == id { print $4 }' "$T/comps")"
  LOC="$(awk -F '\t' -v id="$1" '$1 == id { print $3 }' "$T/comps")"
  [ -f "$C/Payload" ] || die "component $1 in $PKG has no Payload"
}
cpio_from() {
  _id=$1; shift
  rm -f "$T/gzip.rc" "$T/cpio.rc"
  { if gzip -dc "$C/Payload"; then echo 0 > "$T/gzip.rc"; else echo $? > "$T/gzip.rc"; fi; } \
    | { if cpio "$@" 2>/dev/null; then echo 0 > "$T/cpio.rc"; else echo $? > "$T/cpio.rc"; fi; }
  [ "$(cat "$T/cpio.rc" 2>/dev/null || :)" = 0 ] || die "could not unpack the Payload of $_id in $PKG"
  [ "$(cat "$T/gzip.rc" 2>/dev/null || :)" = 0 ] || die "could not decompress the Payload of $_id in $PKG"
}
list_component() {
  cpio_from "$1" -itvn --quiet > "$T/tv"
  awk '
    BEGIN { split("- d l p c b s", t, " "); split("8 4 10 1 2 6 12", tv, " "); for (i in t) ty[t[i]] = tv[i] }
    {
      p = $1; name = $0
      sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ /, "", name)
      c = substr(p, 1, 1)
      if (c == "l") sub(/ -> .*$/, "", name)
      m = ty[c] * 4096
      for (i = 0; i < 3; i++) {
        r = substr(p, 2 + 3 * i, 1); w = substr(p, 3 + 3 * i, 1); x = substr(p, 4 + 3 * i, 1)
        b = 0
        if (r == "r") b += 4
        if (w == "w") b += 2
        if (x == "x" || x == "s" || x == "t") b += 1
        m += b * (i == 0 ? 64 : (i == 1 ? 8 : 1))
        if (x == "s" || x == "S") m += (i == 0 ? 2048 : 1024)
        if (x == "t" || x == "T") m += 512
      }
      printf "%s\t%o\t%s\t%s\n", name, m, $3, $4
    }' "$T/tv" | sort
}

case "$cmd" in
  expand)
    [ ! -e "$1" ] && [ ! -L "$1" ] || die "$1 already exists"
    [ -f "$PKG" ] || die "$PKG is not a pkg file"
    stevedore expand "$PKG" "$1" > /dev/null || die "could not expand $PKG"
    ;;
  payload)
    id=$1; dir=$2; shift 2
    expanded; component "$id"
    case "$C" in /*) : ;; *) C="$(pwd)/$C" ;; esac
    mkdir -p "$dir" || die "cannot make $dir"
    ( cd "$dir" && cpio_from "$id" -id --quiet "$@" )
    ;;
  list)
    expanded; component "$1"
    list_component "$1"
    ;;
  plist)
    expanded
    components > "$T/comps" || die "could not read the PackageInfo files of $PKG"
    : > "$T/hits"
    while IFS='	' read -r id ver loc dir; do
      C=$dir
      [ -f "$C/Payload" ] || continue
      list_component "$id" | awk -F '\t' -v id="$id" -v loc="$loc" '{
        p = $1; sub(/^\.\//, "", p); sub(/^\.$/, "", p)
        f = loc "/" p; gsub(/\/+/, "/", f)
        if (f ~ /^\/(opt|usr\/local)\/mavergreen\/[^\/]+\/mavergreen\.plist$/) printf "%s\t%s\n", id, $1
      }' >> "$T/hits"
    done < "$T/comps"
    n="$(grep -c . "$T/hits" || :)"
    [ "$n" = 1 ] || die "expected one opt/mavergreen/SHORT/mavergreen.plist in $PKG, found $n"
    id="$(cut -f1 "$T/hits")"; member="$(cut -f2- "$T/hits")"
    C="$(awk -F '\t' -v id="$id" '$1 == id { print $4 }' "$T/comps")"
    case "$C" in /*) : ;; *) C="$(pwd)/$C" ;; esac
    mkdir "$T/m"
    ( cd "$T/m" && cpio_from "$id" -id --quiet "$member" )
    [ -f "$T/m/$member" ] || die "could not unpack $member from $id in $PKG"
    for k in "$@"; do
      v="$(stevedore plist get "$T/m/$member" "$k" 2>/dev/null)" || die "the manifest $member in $PKG has no scalar $k"
      printf '%s\n' "$v"
    done
    ;;
  facts)
    expanded
    {
      if [ -f "$X/Distribution" ]; then
        awk "$XML"'END {
          rest = s; while (next_el("options")) { v = attr(el, "hostArchitectures"); if (v != "") print "distribution host-architectures " v }
          rest = s; while (next_el("os-version")) {
            v = attr(el, "min"); if (v != "") print "distribution os-version-min " v
            v = attr(el, "max"); if (v != "") print "distribution os-version-max " v
          }
          rest = s; while (next_el("pkg-ref")) { v = attr(el, "version"); if (v != "") print "distribution pkg-ref " attr(el, "id") " " v }
        }' "$X/Distribution"
      fi
      components > "$T/comps" || die "could not read the PackageInfo files of $PKG"
      [ -s "$T/comps" ] || die "$PKG has no PackageInfo"
      while IFS='	' read -r id ver loc dir; do
        printf 'component %s version %s\ncomponent %s install-location %s\n' "$id" "$ver" "$id" "$loc"
        [ -d "$dir/Scripts" ] || continue
        for f in "$dir"/Scripts/* "$dir"/Scripts/.[!.]*; do
          [ -e "$f" ] || [ -L "$f" ] || continue
          printf 'component %s script %s\n' "$id" "${f##*/}"
        done
      done < "$T/comps"
    } > "$T/facts"
    sort -u "$T/facts"
    ;;
esac
