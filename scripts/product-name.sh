#!/bin/sh
# usage: product-name.sh identifier <short-name>
#        product-name.sh check
#        Reads the family's short-name registry (scripts/product-names, or $MAVERGREEN_PRODUCT_NAMES).
set -eu
REG="${MAVERGREEN_PRODUCT_NAMES:-$(cd "$(dirname "$0")" && pwd)/product-names}"
entries() { sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$REG"; }
case "${1:-}" in
  identifier)
    id="$(entries | awk -v n="${2:?usage: product-name.sh identifier <short-name>}" '$1 == n { print $2; exit }')"
    [ -n "$id" ] || exit 1
    printf '%s\n' "$id" ;;
  check)
    entries | awk '
      NF != 2 { print "product-names: not <name> <identifier>: " $0 > "/dev/stderr"; bad = 1; next }
      $1 !~ /^[a-z0-9][a-z0-9-]*$/ { print "product-names: bad short name: " $1 > "/dev/stderr"; bad = 1 }
      $2 !~ /^dev\.mavergreen\./ { print "product-names: identifier outside dev.mavergreen.*: " $2 > "/dev/stderr"; bad = 1 }
      $1 ~ /^(var|bin|sbin|share|mavergreen|system-replace|base)$/ { print "product-names: short name reserved by the install layout: " $1 > "/dev/stderr"; bad = 1 }
      $2 == "dev.mavergreen.base" { print "product-names: dev.mavergreen.base is the helper component, not a product: " $1 > "/dev/stderr"; bad = 1 }
      ($1 in n) { print "product-names: duplicate short name: " $1 > "/dev/stderr"; bad = 1 }
      ($2 in i) { print "product-names: duplicate identifier: " $2 > "/dev/stderr"; bad = 1 }
      { n[$1] = 1; i[$2] = 1 }
      END { exit bad }' ;;
  *) echo "usage: product-name.sh identifier <short-name> | check" >&2; exit 2 ;;
esac
