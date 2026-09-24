#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "shipyard: consume its facilities" -- a GitHub Action's own checkout has no
#       .git, so shipyard-version.sh's commit-count derivation cannot run inside install@v1; this
#       script resolves the version from the ref the consumer pinned instead.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/resolve-action-version.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/resolve-action-version.XXXXXX")"; trap 'rm -rf "$work"' EXIT

[ "$(sh "$S" v1.0.126)" = "1.0.126" ] || { echo "FAIL: an exact pin should resolve offline (no network) to 1.0.126 -- this is the common case for a repo escaping a bad @v1"; exit 1; }
[ "$(sh "$S" v2.13.4)" = "2.13.4" ] || { echo "FAIL: exact pin v2.13.4"; exit 1; }

remote="$work/remote"
mkdir -p "$remote"; cd "$remote"
git init -q -b main .; git config user.email t@example.com; git config user.name tester
echo a > f; git add f; git commit -qm one
git tag v1.0.5
echo b > f; git add f; git commit -qm two
git tag v1.0.126          # lightweight, as action-gh-release mints them
git tag -f -a v1 -m 'v1 -> v1.0.126' >/dev/null   # annotated, as release.yml moves it

out="$(sh "$S" v1 "file://$remote")" || { echo "FAIL: a moving tag has to be dereferenced against the remote (which immutable tag shares its commit?) -- it should resolve"; exit 1; }
[ "$out" = "1.0.126" ] || { echo "FAIL: v1 should resolve to the release sharing its commit; got '$out'"; exit 1; }

[ "$out" != "1.0.5" ] || { echo "FAIL: resolved to the wrong release -- the older release must NOT be picked just because it is also a v*.*.* tag"; exit 1; }

if sh "$S" "$(git rev-parse HEAD)" "file://$remote" >/dev/null 2>&1; then
  echo "FAIL: a SHA pin names no release and must FAIL rather than invent a version, so the caller can fall back to the line and say so"; exit 1
fi
if sh "$S" nonexistent-ref "file://$remote" >/dev/null 2>&1; then
  echo "FAIL: a tag we never released names no release and must not resolve"; exit 1
fi

echo "PASS: resolve-action-version"
