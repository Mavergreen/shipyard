#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "shipyard: consume its facilities" -- shipyard's own version is
#       <.mavergreen/upstream/VERSION>.<commit count>, so a new commit is necessarily a new version.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/shipyard-version.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-version.XXXXXX")"; trap 'rm -rf "$work"' EXIT

mkrepo() {  # $1 = dir, $2 = line, $3 = number of commits
  mkdir -p "$1"; cd "$1"
  git init -q -b main .
  git config user.email t@example.com; git config user.name tester
  mkdir -p .mavergreen/upstream; printf '%s\n' "$2" > .mavergreen/upstream/VERSION
  mkdir -p scripts; cp "$S" "$here/../scripts/mavergreen-meta.sh" scripts/
  i=0; while [ "$i" -lt "$3" ]; do echo "$i" > f; git add -A; git commit -qm "c$i"; i=$((i + 1)); done
}

mkrepo "$work/a" 1.0 3
out="$(sh scripts/shipyard-version.sh)"
[ "$(printf '%s\n' "$out" | sed -n 's/^FULL=//p')" = "1.0.3" ] \
  || { echo "FAIL: 3 commits on line 1.0 should be 1.0.3; got: $out"; exit 1; }
[ "$(printf '%s\n' "$out" | sed -n 's/^TAG=//p')" = "v1.0.3" ] \
  || { echo "FAIL: TAG should be v1.0.3; got: $out"; exit 1; }

echo more > f; git add -A; git commit -qm c3
[ "$(sh scripts/shipyard-version.sh | sed -n 's/^FULL=//p')" = "1.0.4" ] \
  || { echo "FAIL: one more commit must be one more version -- that is the whole point"; exit 1; }

printf '2.0\n' > .mavergreen/upstream/VERSION; git add -A; git commit -qm 'line 2.0'
[ "$(sh scripts/shipyard-version.sh | sed -n 's/^FULL=//p')" = "2.0.5" ] \
  || { echo "FAIL: a deliberate line bump must not restart the patch, so versions stay monotonic across lines"; exit 1; }

mkrepo "$work/b" 1.0.5 2
if sh scripts/shipyard-version.sh >/dev/null 2>&1; then
  echo "FAIL: a full version left in upstream/VERSION is the mistake this replaces -- refuse it loudly rather than silently emitting 1.0.5.7"; exit 1
fi
sh scripts/shipyard-version.sh 2>&1 | grep -qi 'line' \
  || { echo "FAIL: the refusal should say upstream/VERSION holds the LINE"; exit 1; }

git rm -q -r .mavergreen; printf '1.0\n' > UPSTREAM_VERSION; git add UPSTREAM_VERSION; git commit -qm legacy
if sh scripts/shipyard-version.sh >/dev/null 2>&1; then
  echo "FAIL: a root UPSTREAM_VERSION is no longer read"; exit 1
fi
sh scripts/shipyard-version.sh 2>&1 | grep -q '.mavergreen/upstream/VERSION' \
  || { echo "FAIL: the refusal should name .mavergreen/upstream/VERSION"; exit 1; }

cd "$work/a"
git clone -q --depth 1 "file://$work/a" "$work/shallow"
cd "$work/shallow"
if sh scripts/shipyard-version.sh >/dev/null 2>&1; then
  echo "FAIL: a shallow clone has HEAD but not the history behind it, so rev-list --count would silently return 1 and collide with the already-published v1.0.1 -- refuse rather than mint a wrong, immutable tag"; exit 1
fi
sh scripts/shipyard-version.sh 2>&1 | grep -qi 'shallow' \
  || { echo "FAIL: the refusal should say the clone is shallow"; exit 1; }

own="$(MAVERGREEN_ROOT="$here/.." sh -c '. "$1"; mg_value upstream/VERSION' sh "$here/../scripts/mavergreen-meta.sh")"
case "$own" in
  [0-9]*.[0-9]*.*|'') echo "FAIL: shipyard's own .mavergreen/upstream/VERSION holds the line (major.minor), got '$own'"; exit 1 ;;
  [0-9]*.[0-9]*) : ;;
  *) echo "FAIL: shipyard's own .mavergreen/upstream/VERSION is not a major.minor line: '$own'"; exit 1 ;;
esac

echo "PASS: shipyard-version"
