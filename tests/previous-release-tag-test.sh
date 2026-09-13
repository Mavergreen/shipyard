#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/previous-release-tag.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/previous-release-tag.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
echo hi > f; git add f; git commit -qm base

out="$(sh "$S")"
[ -z "$out" ] || { echo "FAIL no-tags: got '$out'"; exit 1; }

git tag 1.98.8-mavericks.1
git tag 1.98.8-mavericks.2
git tag 1.102.0-mavericks.1
git tag v1                 # not a release tag; must be ignored

out="$(sh "$S")"
[ "$out" = 1.102.0-mavericks.1 ] || { echo "FAIL: version ordering must be numeric per component, not lexical -- 1.102.0 must sort after 1.98.8: got '$out'"; exit 1; }

out="$(sh "$S" 1.102.0-mavericks.1)"
[ "$out" = 1.98.8-mavericks.2 ] || { echo "FAIL: excluding the tag being published must yield its predecessor: got '$out'"; exit 1; }

git tag 1.102.0-mavericks.9; git tag 1.102.0-mavericks.10
out="$(sh "$S")"
[ "$out" = 1.102.0-mavericks.10 ] || { echo "FAIL: N ordering must be numeric, .10 beats .9: got '$out'"; exit 1; }

git tag 1.26.5-mavericks.1; git tag 1.26.7-mavericks.1; git tag 1.27.0-mavericks.1
out="$(sh "$S" '' '1.26.*')"
[ "$out" = 1.26.7-mavericks.1 ] || { echo "FAIL: a repo with parallel upstream lines needs the baseline from its OWN line -- 1.26.7's notes must diff against 1.26.5, not a 1.27.0 that shipped in between: got '$out'"; exit 1; }
out="$(sh "$S" 1.26.7-mavericks.1 '1.26.*')"
[ "$out" = 1.26.5-mavericks.1 ] || { echo "FAIL line filter + exclude: got '$out'"; exit 1; }
out="$(sh "$S")"
[ "$out" = 1.102.0-mavericks.10 ] \
  || { echo "FAIL: no filter must still mean \"newest overall\" across every line -- 1.102.0 outranks 1.27.0 under version-sorted order, which is exactly why a repo with parallel lines must pass the filter rather than trust the default: got '$out'"; exit 1; }

git tag 9.9p2-mavericks.4; git tag 9.9p2-mavericks.5
out="$(sh "$S" 9.9p2-mavericks.5 '9.9p2')"
[ "$out" = 9.9p2-mavericks.4 ] \
  || { echo "FAIL: an openssh-shaped upstream carries a letter (9.9p2), so the comparison key must map pN before ordering, or every release silently omits its ingredient section: got '$out'"; exit 1; }

git tag v1.0.5; git tag v1.0.191; git tag v1.0.192
out="$(sh "$S" --tag-glob 'v*.*.*' v1.0.192)"
[ "$out" = v1.0.191 ] \
  || { echo "FAIL: self-upstream tag shapes (shipyard/magic-trackpad2's vX.Y.Z) match no *-mavericks.* glob, so without --tag-glob every release would report \"no baseline\" and drop its compare link: got '$out'"; exit 1; }

git tag v2
out="$(sh "$S" --tag-glob 'v*.*.*' v2)"
[ "$out" != v1 ] \
  || { echo "FAIL: the moving major tag v1 is a real tag in shipyard and must never be chosen as a baseline (a compare link against it says \"everything since whenever v1 last moved,\" which is not a release) -- 'v*.*.*' not 'v[0-9]*' is what keeps it out, since requiring three dot-separated components means a bare \"v1\" or \"v2\" alias never even reaches the comparator; the glob itself must do the work -- even excluding v2 (the only other tag that could let v1 \"win by default\"), the result must still not be v1: got '$out'"; exit 1; }

git tag 20260802.4; git tag 20260802.5
git tag feed-porthole            # not a release tag; must be ignored (never matches [0-9]*)
git tag backup/pre-rewrite       # not a release tag; must be ignored (never matches [0-9]*)
git tag 20260802-rc1             # DOES match [0-9]*, but fails numeric(): must be skipped, not chosen
out="$(sh "$S" --tag-glob '[0-9]*' 20260802.5)"
[ "$out" = 20260802.4 ] || { echo "FAIL date-shaped newest: got '$out'"; exit 1; }

out="$(sh "$S" --tag-glob 'v*.*.*' v1.0.192 1.26 2>&1)" && rc=0 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: --tag-glob and a positional upstream-glob fight over the same slot -- silently picking one would give a caller a baseline from a tag set it did not ask about, so this must be a mutual-exclusion error: got exit $rc (output: $out)"; exit 1; }

out="$(sh "$S" --globb 'v*.*.*' v1.0.192 2>&1)" && rc=0 || rc=$?
[ "$rc" = 2 ] \
  || { echo "FAIL: an unrecognised FLAG must not silently fall through to the positional slot -- a typo like --globb would otherwise cost a real release its compare link at exit 0, the exact failure shape this generator exists to stop: got exit $rc (output: $out)"; exit 1; }

git tag 9.9p3-mavericks.1; git tag 9.9p3-mavericks.2
out="$(sh "$S" 9.9p3-mavericks.2)"
[ "$out" = 9.9p3-mavericks.1 ] \
  || { echo "FAIL: every existing positional call must still mean what it meant (fresh tags here, not reused from above, so this cannot pass by accident): got '$out'"; exit 1; }

(
  work2="$(mktemp -d "${TMPDIR:-/tmp}/previous-release-tag-vcollide.XXXXXX")"
  trap 'rm -rf "$work2"' EXIT
  cd "$work2"
  git init -q -b main .
  git config user.email t@example.com; git config user.name tester
  echo hi > f; git add f; git commit -qm base
  git tag v1.5.2-mavericks.1
  git tag 1.5.2-mavericks.1
  out="$(sh "$S")"
  [ "$out" = 1.5.2-mavericks.1 ] \
    || { echo "FAIL v-collision: outside --tag-glob, a leading 'v' must NOT be stripped -- mavericks-legacysupport ships a stray v1.5.2-mavericks.1 beside the real 1.5.2-mavericks.1, and stripping it would let the two collide/compare as the same release, or surface the stray one as the baseline instead of the real tag: got '$out'"; exit 1; }
)

echo "PASS: previous-release-tag"
