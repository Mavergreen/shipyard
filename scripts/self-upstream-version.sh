#!/bin/sh
# platform: host-agnostic
#   usage: self-upstream-version.sh [--root DIR] [--ref REV] [--prefix P]
#          Prints a self-upstream repo's YYYYMMDD.N for REV (default HEAD) in the repo at DIR
#          (default .), and on stderr one line saying why. Release tags are the YYYYMMDD.N tags
#          reachable from REV. With none: the UTC committer day of the newest own-code commit (or of
#          REV, if own code never changed), .1. When own code changed since the last tag: that day
#          .1 if it is later than the tag's date, else the tag's date .N+1. Otherwise the tag's date
#          .N+1. Own code is every path except UPSTREAM_VERSION, components/*/version,
#          ingredients/**, .github/**, tests/**, release-notes/**, top-level *.md, each file
#          declared-state.sh names, and each INGREDIENTS.md "## Conformance deviations" entry
#          "- self-upstream-exclude:<glob>: <reason>", a git pathspec glob (`*` stays within one
#          directory, `**/` spans any). With --prefix P, release tags are P<YYYYMMDD>.<N>, matched
#          literally, and the version printed is P<YYYYMMDD>.<N>. Exit 2 on a usage error, a
#          non-repo, an unknown REV, a shallow clone, or an INGREDIENTS.md the parsers refuse.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning" -- the
#       version only: whether to publish stays with release-state.sh and release-needed.sh.
# spec: tests/self-upstream-version-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # ver_cmp()

usage() { echo "usage: self-upstream-version.sh [--root DIR] [--ref REV] [--prefix P]" >&2; exit 2; }

ROOT="."; REF="HEAD"; PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="${2%/}"; shift 2 ;;
    --ref) [ $# -ge 2 ] || usage; REF="$2"; shift 2 ;;
    --prefix) [ $# -ge 2 ] || usage; PREFIX="$2"; shift 2 ;;
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

sh "$SELF/own-code-pathspecs.sh" --root "$ROOT" > "$work/exclude" || exit 2

set -- .
while IFS= read -r spec; do set -- "$@" "$spec"; done < "$work/exclude"

git -C "$ROOT" tag --merged "$rev" > "$work/tags"
last=""
for t in $(PREFIX="$PREFIX" awk '
  BEGIN { p = ENVIRON["PREFIX"] }
  { rest = $0 }
  p != "" { if (index($0, p) != 1) next; rest = substr($0, length(p) + 1) }
  rest ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]\.[1-9][0-9]*$/ { print rest }
' "$work/tags"); do
  if [ -z "$last" ] || [ "$(ver_cmp "$t" "$last")" = 1 ]; then last="$t"; fi
done

own="$(TZ=UTC git -C "$ROOT" log -1 --first-parent --date=format-local:%Y%m%d --format='%cd %h' "$rev" -- "$@")"
day="${own%% *}"; sha="${own#* }"

if [ -z "$last" ]; then
  [ -n "$own" ] || day="$(TZ=UTC git -C "$ROOT" log -1 --date=format-local:%Y%m%d --format=%cd "$rev")"
  ver="$PREFIX$day.1"; why="no release tag yet"
else
  lastdate="${last%%.*}"; lastn="${last#*.}"
  if [ -n "$(git -C "$ROOT" log -1 --first-parent --format=%h "refs/tags/$PREFIX$last..$rev" -- "$@")" ]; then
    if [ "$day" -gt "$lastdate" ]; then ver="$PREFIX$day.1"; else ver="$PREFIX$lastdate.$((lastn + 1))"; fi
    why="own code changed in $sha ($day)"
  else
    ver="$PREFIX$lastdate.$((lastn + 1))"; why="no own-code change since $PREFIX$last; ingredient-only"
  fi
fi

echo "self-upstream-version: $ver: $why" >&2
printf '%s\n' "$ver"
