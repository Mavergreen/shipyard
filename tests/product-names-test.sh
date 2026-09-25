#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/product-name.sh"
fail() { echo "FAIL: $1"; exit 1; }

sh "$S" check || fail "the committed registry must be valid"
[ "$(sh "$S" identifier shipyard)" = dev.mavergreen.mavericks-shipyard ] \
  || fail "shipyard must be registered to the pkg identifier its receipt carries"
[ "$(sh "$S" identifier node24)" = dev.mavergreen.nodejs.node24 ] \
  || fail "node24 must be registered to the pkg identifier its receipt carries"
sh "$S" identifier no-such-product >/dev/null && fail "an unregistered name must exit non-zero"

[ "$(sh "$S" repo go126)" = golang-126 ] && [ "$(sh "$S" repo go126-cross)" = golang-126 ] \
  || fail "a line's native and cross products live in one repo, named <product>-<line>"
[ "$(sh "$S" repo trackpad2)" = magic-trackpad2 ] || fail "a short name need not be its repo's name"
[ "$(sh "$S" shorts golang-126 | tr '\n' ' ')" = 'go126 go126-cross ' ] \
  || fail "shorts lists every short name one repo ships, in registry order"
sh "$S" shorts golang >/dev/null 2>&1 && fail "a repo the registry does not name ships no short name"
[ "$(sh "$S" updater-bundle-id go126)" = dev.mavergreen.golang.go126.updater ] \
  || fail "an updater's bundle id is its pkg identifier plus .updater"
[ "$(sh "$S" agent-label clang22-cross)" = dev.mavergreen.clang.clang22-cross-updatecheck ] \
  || fail "an update-check job's label is its pkg identifier plus -updatecheck"
[ "$(sh "$S" updater-app shipyard)" = 'Library/Application Support/Mavergreen/shipyard-updater.app' ] \
  || fail "an updater is <short name>-updater.app, so two lines never install the same one"
[ "$(sh "$S" feed go126-cross)" = https://github.com/Mavergreen/golang-126/releases/latest/download/go126-cross.xml ] \
  || fail "a feed is <short name>.xml on its repo's latest release"
[ "$(sh "$S" feed trackpad2)" = https://github.com/Mavergreen/magic-trackpad2/releases/latest/download/trackpad2.xml ] \
  || fail "a feed is named for the short name, and served from the registered repo"
for q in repo updater-bundle-id agent-label updater-app feed; do
  sh "$S" "$q" no-such-product >/dev/null 2>&1 && fail "$q of an unregistered name must exit non-zero"
done

w="$(mktemp -d "${TMPDIR:-/tmp}/product-names.XXXXXX")"; trap 'rm -rf "$w"' EXIT
printf 'a dev.mavergreen.a r\na dev.mavergreen.b r\n' > "$w/dup-name"
MAVERGREEN_PRODUCT_NAMES="$w/dup-name" sh "$S" check 2>/dev/null \
  && fail "two identifiers under one short name must be refused -- the name is what people type"
printf 'a dev.mavergreen.a r\nb dev.mavergreen.a r\n' > "$w/dup-id"
MAVERGREEN_PRODUCT_NAMES="$w/dup-id" sh "$S" check 2>/dev/null \
  && fail "one identifier under two names must be refused -- a receipt has one tree"
printf 'Go126 dev.mavergreen.golang.go126 golang-126\n' > "$w/bad"
MAVERGREEN_PRODUCT_NAMES="$w/bad" sh "$S" check 2>/dev/null \
  && fail "a name outside [a-z0-9-] must be refused -- it becomes a path in a preinstall's rm -rf"
for r in var bin sbin share mavergreen system-replace base; do
  printf '%s dev.mavergreen.%s-x r\n' "$r" "$r" > "$w/reserved"
  MAVERGREEN_PRODUCT_NAMES="$w/reserved" sh "$S" check 2>/dev/null \
    && fail "short name '$r' must be refused -- the install layout reserves it (the link farm, var/, the helper and its base component)"
done
printf 'x dev.mavergreen.base r\n' > "$w/base-id"
MAVERGREEN_PRODUCT_NAMES="$w/base-id" sh "$S" check 2>/dev/null \
  && fail "identifier dev.mavergreen.base must be refused -- it is the helper component every archive carries"
printf 'a dev.mavergreen.a\n' > "$w/two-col"
MAVERGREEN_PRODUCT_NAMES="$w/two-col" sh "$S" check 2>/dev/null \
  && fail "a row with no repo must be refused -- every feed URL is derived from it"
printf 'a dev.mavergreen.a Bad_Repo\n' > "$w/bad-repo"
MAVERGREEN_PRODUCT_NAMES="$w/bad-repo" sh "$S" check 2>/dev/null \
  && fail "a repo outside [a-z0-9-] must be refused -- it becomes part of every feed URL"
printf 'go127 dev.mavergreen.go127 golang-127\n' > "$w/lined-id"
MAVERGREEN_PRODUCT_NAMES="$w/lined-id" sh "$S" check 2>/dev/null \
  && fail "a product in a line repo is identified dev.mavergreen.<product>.<short name>"
printf '# comment\n\ngo127 dev.mavergreen.golang.go127 golang-127\nx dev.mavergreen.x one\ny dev.mavergreen.y one\n' > "$w/good"
MAVERGREEN_PRODUCT_NAMES="$w/good" sh "$S" check \
  || fail "comments, blank lines, a lined identifier and many short names in one repo are all allowed"
printf 'var dev.mavergreen.var-x v\n-x dev.mavergreen.dash d\nBad dev.mavergreen.bad b\n' > "$w/unsafe"
for n in var -x Bad; do
  for q in identifier repo feed updater-app; do
    MAVERGREEN_PRODUCT_NAMES="$w/unsafe" sh "$S" "$q" "$n" >/dev/null 2>&1 \
      && fail "$q must refuse '$n' even when a hand-edited registry lists it"
  done
done

printf 'x dev.mavergreen.base r\nb dev.mavergreen.b Bad_Repo\n' > "$w/unsafe-row"
for q in identifier repo updater-bundle-id agent-label updater-app feed; do
  MAVERGREEN_PRODUCT_NAMES="$w/unsafe-row" sh "$S" "$q" x >/dev/null 2>&1 \
    && fail "$q must refuse a row carrying dev.mavergreen.base -- that is the helper component, not a product"
done
MAVERGREEN_PRODUCT_NAMES="$w/unsafe-row" sh "$S" shorts r >/dev/null 2>&1 \
  && fail "shorts must not name a row carrying dev.mavergreen.base"
for q in repo feed; do
  MAVERGREEN_PRODUCT_NAMES="$w/unsafe-row" sh "$S" "$q" b >/dev/null 2>&1 \
    && fail "$q must refuse a repo outside [a-z0-9-] even when a hand-edited registry lists it"
done
for q in repo feed; do
  rc=0; err="$(MAVERGREEN_PRODUCT_NAMES="$w/unsafe-row" sh "$S" "$q" b 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] && [ -n "$err" ] \
    || fail "$q of a registered name whose row is malformed must exit 2 and say why -- exit 1 means not registered: rc $rc [$err]"
  rc=0; err="$(MAVERGREEN_PRODUCT_NAMES="$w/two-col" sh "$S" "$q" a 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] && [ -n "$err" ] \
    || fail "$q of a registered name whose row has no repo must exit 2 and say why: rc $rc [$err]"
done

missing_registry() {
  err="$(MAVERGREEN_PRODUCT_NAMES="$w/absent" sh "$S" "$@" 2>&1 >/dev/null)" \
    && fail "$1 must fail when the registry is missing, not read it as empty"
  [ -n "$err" ] || fail "$1 must say why when the registry is missing"
}
missing_registry check
missing_registry identifier shipyard
missing_registry shorts shipyard
echo "PASS: product-names"
