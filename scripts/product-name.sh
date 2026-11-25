#!/bin/sh
# platform: host-agnostic
# usage: product-name.sh identifier|repo|updater-bundle-id|agent-label|updater-app|feed <short-name>
#        product-name.sh shorts <repo>
#        product-name.sh provisioner <short-name>
#        product-name.sh check
#        Reads the family's registry (scripts/product-names, or $MAVERGREEN_PRODUCT_NAMES), one line per
#        product: <short name> <pkg identifier> <repo>. Every updater identity and feed URL the family
#        uses is derived here from those three, and nowhere else.
#        provisioner prints the rest of the short name's line in scripts/product-provisioners (or
#        $MAVERGREEN_PRODUCT_PROVISIONERS): the command that sets the product up, whose first word is
#        the registered product providing it. Exit 1 when the product has none.
#        A lookup exits 1 when the name (for shorts, the repo) is not registered, and 2 when the
#        registry cannot answer: it is unreadable, the name's row names no valid repo, or the call
#        is malformed.
set -eu
# spec: tests/product-names-test.sh -- a name is lowercase ASCII; a UTF-8 locale can collate [a-z] to
#       admit uppercase in case patterns and awk ranges, so names are matched in the C locale.
LC_ALL=C; export LC_ALL
REG="${MAVERGREEN_PRODUCT_NAMES:-$(cd "$(dirname "$0")" && pwd)/product-names}"
[ -f "$REG" ] && [ -r "$REG" ] || { echo "product-name.sh: cannot read the registry $REG" >&2; exit 2; }
PROV="${MAVERGREEN_PRODUCT_PROVISIONERS:-$(cd "$(dirname "$0")" && pwd)/product-provisioners}"
prov_entries() {
  [ -f "$PROV" ] && [ -r "$PROV" ] || { echo "product-name.sh: cannot read the provisioners $PROV" >&2; exit 2; }
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$PROV"
}
entries() { sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$REG"; }
usage() {
  echo "usage: product-name.sh identifier|repo|updater-bundle-id|agent-label|updater-app|feed <short-name> | shorts <repo> | provisioner <short-name> | check" >&2
  exit 2
}
safe_name() {
  case "$1" in
    ''|-*|*[!a-z0-9-]*|var|bin|sbin|share|mavergreen|system-replace|base) return 1 ;;
  esac
}
row_field() {
  safe_name "$1" || return 1
  _v="$(entries | awk -v n="$1" -v k="$2" '$1 == n { if ($2 != "dev.mavergreen.base") print $k; exit }')"
  [ -n "$_v" ] || return 1
  printf '%s\n' "$_v"
}
repo_of() {
  row_field "$1" 2 >/dev/null || return 1
  _r="$(row_field "$1" 3)" || _r=""
  case "$_r" in
    ''|-*|*[!a-z0-9-]*) echo "product-name.sh: $1 is registered in $REG, but its row names no valid repo: '$_r'" >&2; exit 2 ;;
  esac
  printf '%s\n' "$_r"
}
case "${1:-}" in
  identifier|repo|updater-bundle-id|agent-label|updater-app|feed)
    [ $# -eq 2 ] || usage
    case "$1" in
      identifier) row_field "$2" 2 ;;
      repo) repo_of "$2" ;;
      updater-bundle-id) _id="$(row_field "$2" 2)" && printf '%s.updater\n' "$_id" ;;
      agent-label) _id="$(row_field "$2" 2)" && printf '%s-updatecheck\n' "$_id" ;;
      updater-app) row_field "$2" 2 >/dev/null && printf 'Library/Application Support/Mavergreen/%s-updater.app\n' "$2" ;;
      feed) _repo="$(repo_of "$2")" && printf 'https://github.com/Mavergreen/%s/releases/latest/download/%s.xml\n' "$_repo" "$2" ;;
    esac ;;
  provisioner)
    [ $# -eq 2 ] || usage
    safe_name "$2" || exit 1
    _p="$(prov_entries | awk -v n="$2" '$1 == n { if (NF >= 2) { $1 = ""; sub(/^ +/, ""); print } else print "-"; exit }')"
    [ -n "$_p" ] || exit 1
    [ "$_p" != - ] || { echo "product-name.sh: $2 has a provisioner row in $PROV with no command" >&2; exit 2; }
    printf '%s\n' "$_p" ;;
  shorts)
    [ $# -eq 2 ] || usage
    case "$2" in ''|-*|*[!a-z0-9-]*) exit 1 ;; esac
    _s="$(entries | awk -v r="$2" '$3 == r && $2 != "dev.mavergreen.base" && $1 ~ /^[a-z0-9][a-z0-9-]*$/ && $1 !~ /^(var|bin|sbin|share|mavergreen|system-replace|base)$/ { print $1 }')"
    [ -n "$_s" ] || exit 1
    printf '%s\n' "$_s" ;;
  check)
    RET="${MAVERGREEN_RETIRING_CROSS_NAMES:-}"
    if [ -z "$RET" ]; then
      _here="$(cd "$(dirname "$0")" && pwd)" || { echo "product-name.sh: cannot find its own directory" >&2; exit 2; }
      RET="$_here/retiring-cross-names"
    fi
    [ -f "$RET" ] && [ -r "$RET" ] || { echo "product-name.sh: cannot read the retiring list $RET" >&2; exit 2; }
    _ret="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$RET")" \
      || { echo "product-name.sh: cannot read the retiring list $RET" >&2; exit 2; }
    _ret="$(printf '%s\n' "$_ret" | tr '\n' ' ')" || exit 2
    entries | awk -v ret=" $_ret" '
      NF != 3 { print "product-names: not <name> <identifier> <repo>: " $0 > "/dev/stderr"; bad = 1; next }
      $1 !~ /^[a-z0-9][a-z0-9-]*$/ { print "product-names: bad short name: " $1 > "/dev/stderr"; bad = 1 }
      $2 !~ /^dev\.mavergreen\./ { print "product-names: identifier outside dev.mavergreen.*: " $2 > "/dev/stderr"; bad = 1 }
      $3 !~ /^[a-z0-9][a-z0-9-]*$/ { print "product-names: bad repo name: " $3 > "/dev/stderr"; bad = 1 }
      $1 ~ /^(var|bin|sbin|share|mavergreen|system-replace|base)$/ { print "product-names: short name reserved by the install layout: " $1 > "/dev/stderr"; bad = 1 }
      $1 ~ /-cross$/ && index(ret, " " $1 " ") == 0 { print "product-names: " $1 ": a product is never named *-cross; one toolchain targets every arch (see the conventions skill, \"The toolchain\")" > "/dev/stderr"; bad = 1 }
      $2 == "dev.mavergreen.base" { print "product-names: dev.mavergreen.base is the helper component, not a product: " $1 > "/dev/stderr"; bad = 1 }
      $3 ~ /-[0-9]+$/ {
        p = $3; sub(/-[0-9]+$/, "", p)
        if ($2 != "dev.mavergreen." p "." $1) { print "product-names: " $1 " is in the line repo " $3 ", so its identifier is dev.mavergreen." p "." $1 ", not " $2 > "/dev/stderr"; bad = 1 }
      }
      ($1 in n) { print "product-names: duplicate short name: " $1 > "/dev/stderr"; bad = 1 }
      ($2 in i) { print "product-names: duplicate identifier: " $2 > "/dev/stderr"; bad = 1 }
      { n[$1] = 1; i[$2] = 1 }
      END { exit bad }' || exit 1
    _pe="$(prov_entries)" || exit 2
    { entries | awk '{ print "N " $1 }'; printf '%s\n' "$_pe" | awk 'NF { print "P " $0 }'; } | awk '
      $1 == "N" { reg[$2] = 1; next }
      NF < 3 { print "product-provisioners: not <name> <command...>: " substr($0, 3) > "/dev/stderr"; bad = 1; next }
      !($2 in reg) { print "product-provisioners: not a registered product: " $2 > "/dev/stderr"; bad = 1 }
      !($3 in reg) { print "product-provisioners: " $2 ": provider is not a registered product: " $3 > "/dev/stderr"; bad = 1 }
      ($2 in p) { print "product-provisioners: duplicate provisioner for " $2 > "/dev/stderr"; bad = 1 }
      { p[$2] = 1 }
      END { exit bad }' ;;
  *) usage ;;
esac
