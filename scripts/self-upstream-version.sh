#!/bin/sh
# platform: host-agnostic
#   usage: self-upstream-version.sh [--root DIR] [--ref REV]
#          Prints a self-upstream repo's YYYYMMDD.N for REV (default HEAD) in the repo at DIR
#          (default .), and on stderr one line saying why. Release tags are the YYYYMMDD.N tags
#          reachable from REV. With none: the UTC committer day of the newest own-code commit (or of
#          REV, if own code never changed), .1. When own code changed since the last tag: that day
#          .1 if it is later than the tag's date, else the tag's date .N+1. Otherwise the tag's date
#          .N+1. Own code is every path except UPSTREAM_VERSION, components/*/version,
#          ingredients/**, .mavergreen/deviations/**, .github/**, tests/**, top-level *.md, each file
#          declared-state.sh names, and the scope of each .mavergreen/deviations/self-upstream-exclude/
#          deviation, a git pathspec glob (`*` stays within one directory, `**/` spans any). Exit 2 on
#          a usage error, a non-repo, an unknown REV, a shallow clone, or metadata the readers refuse.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning" -- the
#       version only: whether to publish stays with release-state.sh and release-needed.sh.
# spec: tests/self-upstream-version-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # ver_cmp()
. "$SELF/deviation-reason.sh"
usage() { echo "usage: self-upstream-version.sh [--root DIR] [--ref REV]" >&2; exit 2; }

ROOT="."; REF="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="${2%/}"; shift 2 ;;
    --ref) [ $# -ge 2 ] || usage; REF="$2"; shift 2 ;;
    *) echo "self-upstream-version: unknown option $1" >&2; usage ;;
  esac
done

# platform: these variables turn the :(exclude,glob) pathspec magic off.
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "self-upstream-version: $ROOT is not a git repository" >&2
  exit 2
}
if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = true ]; then
  echo "self-upstream-version: the repo at $ROOT is a shallow clone, which hides the history and tags the version comes from" >&2
  echo "    release work needs fetch-depth: 0 and visible tags" >&2
  exit 2
fi
rev="$(git -C "$ROOT" rev-parse --verify -q "$REF^{commit}" 2>/dev/null)" || {
  echo "self-upstream-version: --ref '$REF' is not a revision of the repo at $ROOT" >&2
  echo "    (a shallow clone can hide one: release work needs fetch-depth: 0 and visible tags)" >&2
  exit 2
}

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/self-upstream-version.XXXXXX")"; trap 'rm -rf "$work"' EXIT

for p in UPSTREAM_VERSION 'components/*/version' 'ingredients/**' '.mavergreen/deviations/**' '.github/**' 'tests/**' '*.md'; do
  printf ':(exclude,glob)%s\n' "$p"
done > "$work/exclude"

if ! sh "$SELF/declared-state.sh" "$ROOT" > "$work/decl" 2>"$work/err"; then
  cat "$work/err" >&2
  echo "self-upstream-version: $ROOT/INGREDIENTS.md has a malformed \"## Declared state\" declaration" >&2
  exit 2
fi
cut -f2 "$work/decl" | sed 's/:.*//; s/^/:(exclude,literal)/' >> "$work/exclude"

if ! shipyard_deviations "$ROOT" > "$work/devs" 2>"$work/err"; then
  cat "$work/err" >&2
  echo "self-upstream-version: $ROOT/.mavergreen/deviations/ holds a deviation that deviations.sh refuses (it says why, above)" >&2
  exit 2
fi
shipyard_deviation_scopes self-upstream-exclude | while IFS= read -r glob; do
  printf ':(exclude,glob)%s\n' "$glob" >> "$work/exclude"
done

set -- .
while IFS= read -r spec; do set -- "$@" "$spec"; done < "$work/exclude"

git -C "$ROOT" tag --merged "$rev" > "$work/tags"
last=""
for t in $(grep '^[0-9]\{8\}\.[1-9][0-9]*$' "$work/tags" || true); do
  if [ -z "$last" ] || [ "$(ver_cmp "$t" "$last")" = 1 ]; then last="$t"; fi
done

own="$(TZ=UTC git -C "$ROOT" log -1 --first-parent --date=format-local:%Y%m%d --format='%cd %h' "$rev" -- "$@")"
day="${own%% *}"; sha="${own#* }"

if [ -z "$last" ]; then
  [ -n "$own" ] || day="$(TZ=UTC git -C "$ROOT" log -1 --date=format-local:%Y%m%d --format=%cd "$rev")"
  ver="$day.1"; why="no release tag yet"
else
  lastdate="${last%%.*}"; lastn="${last#*.}"
  if [ -n "$(git -C "$ROOT" log -1 --first-parent --format=%h "refs/tags/$last..$rev" -- "$@")" ]; then
    if [ "$day" -gt "$lastdate" ]; then ver="$day.1"; else ver="$lastdate.$((lastn + 1))"; fi
    why="own code changed in $sha ($day)"
  else
    ver="$lastdate.$((lastn + 1))"; why="no own-code change since $last; ingredient-only"
  fi
fi

echo "self-upstream-version: $ver: $why" >&2
printf '%s\n' "$ver"
