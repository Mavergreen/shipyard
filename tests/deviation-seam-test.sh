#!/bin/sh
# platform: host-agnostic
#   usage: deviation-seam-test.sh
#          Every script asks one pair of functions, shipyard_deviations and shipyard_deviated, about
#          deviations. No script parses INGREDIENTS.md for one, and only deviation-reason.sh (and
#          check-deviations.sh, for its grammar refusals) runs deviations.sh.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/devseam-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

hits="$(grep -rnE '(^|[^a-z])(sed|grep|awk) .*(Conformance deviations|No upstream release notes)' "$root/scripts" \
  | grep -v "^$root/scripts/deviations.sh:" \
  | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"
[ -z "$hits" ] || fail "a script parses INGREDIENTS.md for a deviation itself:
$hits"

runs="$(grep -rnE '(^|[;&|(]|[[:space:]])sh +[^|;&]*deviations\.sh' "$root/scripts" \
  | grep -v "^$root/scripts/deviations.sh:" \
  | grep -v "^$root/scripts/deviation-reason.sh:" \
  | grep -v "^$root/scripts/check-deviations.sh:" \
  | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"
[ -z "$runs" ] || fail "deviations.sh is run outside the seam:
$runs"

facts="$(grep -rnE '(^|["'"'"'])deviation ' "$root/scripts" \
  | grep -v "^$root/scripts/deviation-reason.sh:" \
  | grep -v "^$root/scripts/deviations.sh:" \
  | grep -v "^$root/scripts/check-deviations.sh:" \
  | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true)"
[ -z "$facts" ] || fail "a script reads the deviation fact encoding itself:
$facts"

SELF="$root/scripts"
. "$SELF/deviation-reason.sh"

. "$here/lib/deviation_tree.sh"
mkdir "$w/a" "$w/b"
deviation "$w/a" upstream-notes none '*' 'upstream keeps none'
deviation "$w/a" comments later '*' 'swept later'
deviation "$w/a" rosetta tools 'tools/*.sh' 'runs translated'
deviation "$w/a" unpinned dockerfile 'Dockerfile' 'wants the newest'
deviation "$w/a" rosetta spaced 'my tools/*.sh' 'a space is a space'
deviation "$w/b" rosetta everywhere '*' 'everywhere'

is() {  # $1 = want ("" for none), then shipyard_deviated's arguments
  _want="$1"; shift
  _got="$(shipyard_deviated "$@" || true)"
  [ "$_got" = "$_want" ] || fail "shipyard_deviated $* -- wanted '$_want', got '$_got'"
}

cd "$w/a"
shipyard_deviations > "$w/facts"
grep -qx 'deviation comments swept later' "$w/facts" || fail "comments is an unscoped fact: $(cat "$w/facts")"
grep -qx 'deviation upstream-notes upstream keeps none' "$w/facts" || fail "upstream-notes is an unscoped fact"
grep -qx 'deviation rosetta:tools/\*.sh runs translated' "$w/facts" || fail "a scoped fact keeps its glob"
is "swept later" comments
is "upstream keeps none" upstream-notes
is "runs translated" rosetta tools/x.sh
is "" rosetta other/x.sh
[ "$(shipyard_deviation_scopes rosetta)" = "my tools/*.sh
tools/*.sh" ] || fail "scopes lists each scoped glob, a space and all: $(shipyard_deviation_scopes rosetta)"
is "a space is a space" rosetta 'my tools/x.sh'
is "" rosetta 'myXtools/x.sh'
[ "$(shipyard_deviation_scopes comments)" = "*" ] || fail "scopes lists * for an unscoped deviation"
[ -z "$(shipyard_deviation_scopes nothing)" ] || fail "scopes lists nothing for an undeclared check"
is "" rosetta
is "wants the newest" unpinned Dockerfile

printf 'changed\n' > .mavergreen/deviations/comments/later/reason
is "swept later" comments

shipyard_deviations "$w/b" > /dev/null
is "everywhere" rosetta anything
is "" comments
shipyard_deviations "$w/a/INGREDIENTS.md" > /dev/null
is "upstream keeps none" upstream-notes
is "changed" comments
is "" rosetta anything

printf 'deviation host:linux no bash 3.2 here\n' > "$w/stdin-facts"
shipyard_deviations - < "$w/stdin-facts" > /dev/null
is "no bash 3.2 here" host linux
is "" comments

: > "$w/b/.mavergreen/deviations/rosetta/everywhere/revisit"
if shipyard_deviations "$w/b" > /dev/null 2> "$w/err"; then fail "a malformed declaration must fail"; fi
grep -q 'no revisit' "$w/err" || fail "the refusal reaches stderr: $(cat "$w/err")"

echo "PASS deviation-seam-test"
