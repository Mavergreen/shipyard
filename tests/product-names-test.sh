#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/product-name.sh"
fail() { echo "FAIL: $1"; exit 1; }

sh "$S" check || fail "the committed registry must be valid"
[ "$(sh "$S" identifier shipyard)" = dev.mavergreen.mavericks-shipyard ] \
  || fail "shipyard must be registered to the pkg identifier its receipt carries"
sh "$S" identifier no-such-product >/dev/null && fail "an unregistered name must exit non-zero"

w="$(mktemp -d "${TMPDIR:-/tmp}/product-names.XXXXXX")"; trap 'rm -rf "$w"' EXIT
printf 'a dev.mavergreen.a\na dev.mavergreen.b\n' > "$w/dup-name"
MAVERGREEN_PRODUCT_NAMES="$w/dup-name" sh "$S" check 2>/dev/null \
  && fail "two identifiers under one short name must be refused -- the name is what people type"
printf 'a dev.mavergreen.a\nb dev.mavergreen.a\n' > "$w/dup-id"
MAVERGREEN_PRODUCT_NAMES="$w/dup-id" sh "$S" check 2>/dev/null \
  && fail "one identifier under two names must be refused -- a receipt has one tree"
printf 'Go126 dev.mavergreen.golang.go126\n' > "$w/bad"
MAVERGREEN_PRODUCT_NAMES="$w/bad" sh "$S" check 2>/dev/null \
  && fail "a name outside [a-z0-9-] must be refused -- it becomes a path in a preinstall's rm -rf"
printf '# comment\n\nok dev.mavergreen.ok\n' > "$w/good"
MAVERGREEN_PRODUCT_NAMES="$w/good" sh "$S" check || fail "comments and blank lines are allowed"
echo "PASS: product-names"
