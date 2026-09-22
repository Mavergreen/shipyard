#!/bin/sh
#   usage: resolve-action-version.sh <ref> [repo-url]
#          What shipyard version is a consumer's `uses: Mavergreen/shipyard/...@<ref>` actually
#          getting? An EXACT pin (v1.0.126) already IS the version, no network. A MOVING tag (v1) is
#          dereferenced against the remote for the immutable v*.*.* tag pointing at the same commit.
#          Anything else -- a raw SHA, a branch, an unreleased tag -- names no release and FAILS
#          rather than invent a number; the caller falls back to the line and says why.
# platform: a GitHub Action's own checkout is a TARBALL with no .git, so shipyard-version.sh's
#           commit-count derivation cannot run there.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "shipyard: consume
#       its facilities, never hand-roll them" -- resolving from the pinned ref is what ends the
#       anonymous install: every consumer's installed shipyard used to report "1.0" regardless of
#       @<ref>. A committed stamp is not an option either: check 7 fails a tracked VERSION.
set -eu
ref="${1:?resolve-action-version: ref required}"
url="${2:-https://github.com/Mavergreen/shipyard}"

case "$ref" in
  v[0-9]*.[0-9]*.[0-9]*)
    printf '%s\n' "${ref#v}"
    exit 0
    ;;
esac

# platform: `^{}` yields the commit for an annotated tag; a lightweight tag has no such line, so
#           fall back to the ref's own object.
refs="$(git ls-remote --tags "$url" 2>/dev/null)" || {
  echo "resolve-action-version: cannot read tags from $url" >&2; exit 1; }

sha="$(printf '%s\n' "$refs" | awk -v r="refs/tags/$ref^{}" '$2==r {print $1}')"
[ -n "$sha" ] || sha="$(printf '%s\n' "$refs" | awk -v r="refs/tags/$ref" '$2==r {print $1}')"
[ -n "$sha" ] || { echo "resolve-action-version: $ref is not a tag in $url" >&2; exit 1; }

ver="$(printf '%s\n' "$refs" | awk -v s="$sha" '
  $1==s && $2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+(\^\{\})?$/ {
    t=$2; sub(/^refs\/tags\/v/, "", t); sub(/\^\{\}$/, "", t); print t; exit
  }')"
[ -n "$ver" ] || { echo "resolve-action-version: no vX.Y.Z release points at $sha (ref $ref)" >&2; exit 1; }
printf '%s\n' "$ver"
