#!/bin/sh
# platform: host-agnostic
# usage: product-name.sh identifier|repo|updater-bundle-id|agent-label|updater-app|feed <short-name>
#        product-name.sh shorts <repo>
#        product-name.sh check
#        Reads the family's registry (scripts/product-names, or $MAVERGREEN_PRODUCT_NAMES), one line per
#        product: <short name> <pkg identifier> <repo>. Every updater identity and feed URL the family
#        uses is derived here from those three, and nowhere else.
set -eu
REG="${MAVERGREEN_PRODUCT_NAMES:-$(cd "$(dirname "$0")" && pwd)/product-names}"
[ -f "$REG" ] && [ -r "$REG" ] || { echo "product-name.sh: cannot read the registry $REG" >&2; exit 2; }
entries() { sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$REG"; }
usage() {
  echo "usage: product-name.sh identifier|repo|updater-bundle-id|agent-label|updater-app|feed <short-name> | shorts <repo> | check" >&2
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
  _r="$(row_field "$1" 3)" || return 1
  case "$_r" in -*|*[!a-z0-9-]*) return 1 ;; esac
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
  shorts)
    [ $# -eq 2 ] || usage
    case "$2" in ''|-*|*[!a-z0-9-]*) exit 1 ;; esac
    _s="$(entries | awk -v r="$2" '$3 == r && $2 != "dev.mavergreen.base" && $1 ~ /^[a-z0-9][a-z0-9-]*$/ && $1 !~ /^(var|bin|sbin|share|mavergreen|system-replace|base)$/ { print $1 }')"
    [ -n "$_s" ] || exit 1
    printf '%s\n' "$_s" ;;
  check)
    entries | awk '
      NF != 3 { print "product-names: not <name> <identifier> <repo>: " $0 > "/dev/stderr"; bad = 1; next }
      $1 !~ /^[a-z0-9][a-z0-9-]*$/ { print "product-names: bad short name: " $1 > "/dev/stderr"; bad = 1 }
      $2 !~ /^dev\.mavergreen\./ { print "product-names: identifier outside dev.mavergreen.*: " $2 > "/dev/stderr"; bad = 1 }
      $3 !~ /^[a-z0-9][a-z0-9-]*$/ { print "product-names: bad repo name: " $3 > "/dev/stderr"; bad = 1 }
      $1 ~ /^(var|bin|sbin|share|mavergreen|system-replace|base)$/ { print "product-names: short name reserved by the install layout: " $1 > "/dev/stderr"; bad = 1 }
      $2 == "dev.mavergreen.base" { print "product-names: dev.mavergreen.base is the helper component, not a product: " $1 > "/dev/stderr"; bad = 1 }
      $3 ~ /-[0-9]+$/ {
        p = $3; sub(/-[0-9]+$/, "", p)
        if ($2 != "dev.mavergreen." p "." $1) { print "product-names: " $1 " is in the line repo " $3 ", so its identifier is dev.mavergreen." p "." $1 ", not " $2 > "/dev/stderr"; bad = 1 }
      }
      ($1 in n) { print "product-names: duplicate short name: " $1 > "/dev/stderr"; bad = 1 }
      ($2 in i) { print "product-names: duplicate identifier: " $2 > "/dev/stderr"; bad = 1 }
      { n[$1] = 1; i[$2] = 1 }
      END { exit bad }' ;;
  *) usage ;;
esac
