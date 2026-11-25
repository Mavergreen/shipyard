#!/bin/sh
# platform: host-agnostic
#   usage: check-release-version.sh --product SHORT --version V --sha SHA --publishing yes|no
#                                   [--mode auto|local] [--root DIR] [--notes-file FILE]
#          Exit 0 passes, 1 refuses, 2 is a usage or checkout error. In order:
#            1. --publishing is yes or no, --mode auto or local, and the checkout at DIR is SHA.
#            2. V is the version release-version.sh derives (D), else it says why D differs.
#            3. --publishing no passes here: notes are only required of a publishing run.
#            4. NR/next is gone (NR is release-notes/, or release-notes/SHORT/ when that exists).
#            5. semver: NR/D/kind exists.
#            6. NR/D/changes/ commits a file named [a-z0-9-]+, or only pins moved since --previous
#               (no own code, a pin, and FILE, when given, has "### Build ingredients" or
#               "- New upstream: ").
#            7. Prints "check-release-version: ok — D" and why it passed.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Versioning"
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release notes"
# spec: tests/check-release-version-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: check-release-version.sh --product SHORT --version V --sha SHA --publishing yes|no [--mode auto|local] [--root DIR] [--notes-file FILE]" >&2
  exit 2
}
refuse() { echo "check-release-version: $1" >&2; exit 1; }

ROOT="."; MODE="auto"; PRODUCT=""; V=""; SHA=""; PUBLISHING=""; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --product) [ $# -ge 2 ] || usage; PRODUCT="$2"; shift 2 ;;
    --version) [ $# -ge 2 ] || usage; V="$2"; shift 2 ;;
    --sha) [ $# -ge 2 ] || usage; SHA="$2"; shift 2 ;;
    --publishing) [ $# -ge 2 ] || usage; PUBLISHING="$2"; shift 2 ;;
    --mode) [ $# -ge 2 ] || usage; MODE="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || usage; ROOT="${2%/}"; shift 2 ;;
    --notes-file) [ $# -ge 2 ] || usage; NOTES="$2"; shift 2 ;;
    *) echo "check-release-version: unknown option $1" >&2; usage ;;
  esac
done
[ -n "$PRODUCT" ] && [ -n "$V" ] && [ -n "$SHA" ] || usage
case "$PUBLISHING" in yes|no) : ;; *) echo "check-release-version: --publishing must be yes or no, got '$PUBLISHING'" >&2; usage ;; esac
case "$MODE" in auto|local) : ;; *) echo "check-release-version: --mode must be auto or local, got '$MODE'" >&2; usage ;; esac
if [ -n "$NOTES" ] && [ ! -f "$NOTES" ]; then
  echo "check-release-version: --notes-file $NOTES does not exist" >&2
  exit 2
fi

# platform: these variables turn the :(exclude,glob) pathspec magic off.
unset GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
head="$(git -C "$ROOT" rev-parse --verify -q HEAD 2>/dev/null)" || {
  echo "check-release-version: $ROOT is not a git checkout with a commit" >&2
  exit 2
}
sha="$(git -C "$ROOT" rev-parse --verify -q "$SHA^{commit}" 2>/dev/null)" || sha=""
[ "$head" = "$sha" ] || {
  echo "check-release-version: the checkout at $ROOT is $head, not $SHA — check out the commit being released" >&2
  exit 2
}

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/check-release-version.XXXXXX")"; trap 'rm -rf "$work"' EXIT

rv() { sh "$SELF/release-version.sh" --product "$PRODUCT" --root "$ROOT" --mode "$MODE" "$@"; }

_rc=0; rv > "$work/d" 2>"$work/why" || _rc=$?
if [ "$_rc" != 0 ]; then
  sed 's/^/check-release-version: /' "$work/why" >&2
  exit 1
fi
D="$(cat "$work/d")"
why="$(tail -n 1 "$work/why")"; why="${why#"release-version: $D: "}"
_rc=0; rv --previous > "$work/b" 2>"$work/err" || _rc=$?
[ "$_rc" = 0 ] || { sed 's/^/check-release-version: /' "$work/err" >&2; exit 1; }
B="$(cat "$work/b")"

sh "$SELF/versioning.sh" --root "$ROOT" --product "$PRODUCT" > "$work/decl" || exit 1
scheme="$(cut -f1 "$work/decl")"
upfile="$(cut -f2 "$work/decl")"

pathspecs() {   # $1 = own or pins; writes $work/$1, the own-code pathspecs or the pin pathspecs
  if [ "$1" = own ]; then
    echo . > "$work/own"
    sh "$SELF/own-code-pathspecs.sh" --root "$ROOT" >> "$work/own" || refuse "own-code-pathspecs.sh refused $ROOT (it says why, above)"
    [ -z "$upfile" ] || printf ':(exclude,literal)%s\n' "$upfile" >> "$work/own"
  else
    sh "$SELF/own-code-pathspecs.sh" --root "$ROOT" --pins > "$work/pins" || refuse "own-code-pathspecs.sh --pins refused $ROOT (it says why, above)"
    [ -z "$upfile" ] || printf ':(literal)%s\n' "$upfile" >> "$work/pins"
  fi
}

changed() {   # $1 = own or pins; prints the paths changed between B and SHA that $1's pathspecs match
  _list="$work/$1"; set --
  while IFS= read -r _s; do set -- "$@" "$_s"; done < "$_list"
  git -C "$ROOT" diff --no-renames --name-only "refs/tags/$B" "$sha" -- "$@"
}

dirs() {   # stdin = paths; prints their first components, "/" after a directory, sorted, five at most
  awk '{ i = index($0, "/"); print (i ? substr($0, 1, i) : $0) }' | LC_ALL=C sort -u | awk '
    NR <= 5 { out = out (NR > 1 ? ", " : "") $0 }
    NR == 6 { out = out ", …" }
    END { print out }'
}

if [ "$V" != "$D" ]; then
  reason="$why"
  case "$scheme" in
    self-upstream-date|date-semver)
      if [ -n "$B" ]; then
        pathspecs own
        changed own > "$work/owned"
        set --
        while IFS= read -r _s; do set -- "$@" "$_s"; done < "$work/own"
        day="$(TZ=UTC git -C "$ROOT" log -1 --first-parent --date=format-local:%Y-%m-%d --format=%cd "refs/tags/$B..$sha" -- "$@")"
        if [ -s "$work/owned" ] && [ -n "$day" ]; then
          reason="own code changed on $day ($(dirs < "$work/owned"))"
        fi
      fi ;;
  esac
  refuse "version $V but $reason: this release is $D — release.yml must take its version from release-version.sh"
fi

if [ "$PUBLISHING" = no ]; then
  echo "check-release-version: ok — $V (not publishing, so notes are not required)"
  exit 0
fi

nr="$ROOT/release-notes"; [ ! -d "$nr/$PRODUCT" ] || nr="$nr/$PRODUCT"
NR="${nr#"$ROOT"/}"

[ ! -e "$nr/next" ] || refuse "$NR/next is still there — rename it to $NR/$D"

if [ "$scheme" = semver ] && [ ! -f "$nr/$D/kind" ]; then
  refuse "semver release $D has no kind — write major, minor or patch to $NR/$D/kind"
fi

TAB="$(printf '\t')"
git -C "$ROOT" ls-tree "$sha" -- "$NR/$D/changes/" > "$work/tree"
if awk -F"$TAB" '
  { split($1, m, " ") }
  (m[1] == "100644" || m[1] == "100755") && m[2] == "blob" {
    n = split($2, p, "/"); if (p[n] ~ /^[a-z0-9-]+$/) found = 1
  }
  END { exit !found }' "$work/tree"; then
  echo "check-release-version: ok — $D (committed notes in $NR/$D/changes/)"
  exit 0
fi

missing="no release notes for $D — add $NR/$D/changes/<slug>"
[ -n "$B" ] || refuse "$missing (a first release)"
pathspecs own
changed own > "$work/owned"
[ ! -s "$work/owned" ] || refuse "$missing (own code changed since $B: $(dirs < "$work/owned"))"
pathspecs pins
changed pins > "$work/pinned"
[ -s "$work/pinned" ] || refuse "$missing (no pin moved since $B)"
if [ -n "$NOTES" ]; then
  if ! grep -qE '^### Build ingredients[[:space:]]*$' "$NOTES" && ! grep -q '^- New upstream: ' "$NOTES"; then
    refuse "$missing (the generated notes do not say what moved)"
  fi
  echo "check-release-version: ok — $D (only pins moved since $B, and the generated notes say what moved)"
  exit 0
fi
echo "check-release-version: ok — $D (only pins moved since $B)"
