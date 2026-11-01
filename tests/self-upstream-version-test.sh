#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Versioning", date-based YYYYMMDD.N -- the date is the UTC day the repo's own code
#       last changed, never below the last release tag's; an ingredient-only release keeps the date.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/deviation_tree.sh"
S="$here/../scripts/self-upstream-version.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/self-upstream-version-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
n=0
GIT_CEILING_DIRECTORIES="$w"; export GIT_CEILING_DIRECTORIES
TZ=PST8PDT; export TZ

empty() {   # $1 = name; R becomes a new repo with no commits
  R="$w/$1"
  git init -q "$R"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name tester
  git -C "$R" config commit.gpgsign false
}

fresh() {   # $1 = name; R becomes a new repo with one own-code commit on 2026-10-12
  empty "$1"
  at 2026-10-12T12:00:00Z src/main.c
}

at() {   # $1 = committer date, $2... = paths to change in $R, committed together
  _d="$1"; shift
  for _p in "$@"; do
    mkdir -p "$(dirname "$R/$_p")"
    n=$((n + 1)); echo "$n" >> "$R/$_p"
  done
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$_d" GIT_COMMITTER_DATE="$_d" git -C "$R" commit -qm "change $*"
}

want() {   # $1 = expected version, $2 = what it proves; further args go to the script
  _want="$1"; _why="$2"; shift 2
  _rc=0; got="$(sh "$S" --root "$R" "$@" 2>"$w/err")" || _rc=$?
  [ "$_rc" = 0 ] || { echo "FAIL: $_why: exit $_rc"; sed 's/^/    | /' "$w/err"; exit 1; }
  [ "$got" = "$_want" ] || { echo "FAIL: $_why: got '$got', want '$_want'"; sed 's/^/    | /' "$w/err"; exit 1; }
}

said() {   # $1 = the exact stderr line the last run must have printed
  [ "$(cat "$w/err")" = "$1" ] || { echo "FAIL: the reason line must be '$1': got '$(cat "$w/err")'"; exit 1; }
}

refuses() {   # $1 = stderr text it must contain, $2 = what it proves; further args go to the script
  _text="$1"; _why="$2"; shift 2
  _rc=0; sh "$S" "$@" >"$w/out" 2>"$w/err" || _rc=$?
  [ "$_rc" = 2 ] || { echo "FAIL: $_why: want exit 2, got $_rc"; sed 's/^/    | /' "$w/out" "$w/err"; exit 1; }
  [ ! -s "$w/out" ] || { echo "FAIL: $_why: a refusal must print no version: got '$(cat "$w/out")'"; exit 1; }
  grep -qF -- "$_text" "$w/err" || { echo "FAIL: $_why: stderr lacks '$_text'"; sed 's/^/    | /' "$w/err"; exit 1; }
}

fresh first
want 20261012.1 "no release tag yet: the own-code day, .1"
said "self-upstream-version: 20261012.1: no release tag yet"

fresh ingredient
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z components/golang/version
want 20261012.4 "an ingredient-only change keeps the date and takes .N+1"
said "self-upstream-version: 20261012.4: no own-code change since 20261012.3; ingredient-only"

fresh owncode
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z src/x.c
sha="$(git -C "$R" rev-parse --short HEAD)"
want 20261019.1 "an own-code change on a later day takes that day and .1"
said "self-upstream-version: 20261019.1: own code changed in $sha (20261019)"

fresh sameday
at 2026-10-19T09:00:00Z src/x.c
git -C "$R" tag 20261019.1
at 2026-10-19T15:00:00Z src/x.c
want 20261019.2 "an own-code change on the last tag's own day takes .N+1"

fresh rebased
at 2026-10-19T09:00:00Z src/x.c
git -C "$R" tag 20261019.2
at 2026-10-01T09:00:00Z src/x.c
want 20261019.3 "a commit dated before the last tag must never move the date backwards"

fresh utc
git -C "$R" tag 20261012.3
at 2026-10-19T22:30:00-05:00 src/x.c
want 20261020.1 "the day is the UTC day, neither the committer's offset nor the caller's TZ"

for p in tests/a.sh .github/workflows/x.yml README.md .mavergreen/upstream/VERSION ingredients/foo/product; do
  fresh "default-$(printf '%s' "$p" | tr '/.' '__')"
  git -C "$R" tag 20261012.3
  at 2026-10-19T12:00:00Z "$p"
  want 20261012.4 "$p is excluded by default, so changing it is ingredient-only"
done

fresh legacy-upstream
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z UPSTREAM_VERSION
want 20261019.1 "a root UPSTREAM_VERSION is no longer the upstream, so it is own code"

fresh nested-md
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z docs/x.md
want 20261019.1 "only TOP-LEVEL *.md is excluded: docs/x.md is own code"

fresh declared
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream: UPSTREAM_VERSION' \
  '- shipyard-scripts: components/shipyard/scripts.sha256' '- cmake: pins.env:CMAKE_VERSION' \
  > "$R/INGREDIENTS.md"
at 2026-10-12T13:00:00Z INGREDIENTS.md
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z components/shipyard/scripts.sha256
want 20261012.4 "a declared-state path is an ingredient, not own code"
git -C "$R" tag 20261012.4
at 2026-10-20T12:00:00Z pins.env
want 20261012.5 "a declared path:KEY counts its whole file as ingredient" --ref HEAD
git -C "$R" tag 20261012.5
at 2026-10-21T12:00:00Z src/y.c
want 20261021.1 "own code beside declared state still counts"

fresh deviation
deviation "$R" self-upstream-exclude vm-acceptance 'build/vm-acceptance.sh' 'runs only in CI'
deviation "$R" self-upstream-exclude go-tests '**/*_test.go' 'tests never ship'
at 2026-10-12T13:00:00Z INGREDIENTS.md
git -C "$R" tag 20261012.3
at 2026-10-19T11:00:00Z .mavergreen/deviations/self-upstream-exclude/go-tests/reason
want 20261012.4 "a deviation is metadata, not own code"
at 2026-10-19T12:00:00Z build/vm-acceptance.sh
want 20261012.4 "a self-upstream-exclude path is ingredient-only"
at 2026-10-19T13:00:00Z pkg/deep/x_test.go x_test.go
want 20261012.4 "a self-upstream-exclude glob matches at any depth with **/"
at 2026-10-19T14:00:00Z build/other.sh
want 20261019.1 "an exclusion covers only what it names: build/other.sh is own code"

fresh no-reason
deviation "$R" self-upstream-exclude x 'build/x.sh' ''
refuses "deviations.sh" "an exclusion with no reason is refused, like every deviation" --root "$R"

fresh unscoped
deviation "$R" self-upstream-exclude x '*' 'everything'
refuses "self-upstream-exclude" "an unscoped exclusion would make no change own code, so it is refused" --root "$R"

fresh malformed
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream:' > "$R/INGREDIENTS.md"
refuses "Declared state" "a malformed declared state is refused, never read as no exclusions" --root "$R"

fresh ref
git -C "$R" tag 20261012.3
at 2026-10-15T12:00:00Z components/golang/version
old="$(git -C "$R" rev-parse HEAD)"
at 2026-10-19T12:00:00Z src/x.c
git -C "$R" tag 20261019.1
at 2026-10-20T12:00:00Z src/x.c
want 20261020.1 "HEAD sees the newer tag and the newer own code"
want 20261012.4 "--ref uses only that commit's history and tags" --ref "$old"

fresh numeric
git -C "$R" tag 20261012.9
at 2026-10-12T13:00:00Z components/golang/version
git -C "$R" tag 20261012.10
at 2026-10-19T12:00:00Z components/golang/version
want 20261012.11 "the last tag is the numerically greatest: .10 beats .9"

fresh foreign-tags
git -C "$R" tag v1.0
git -C "$R" tag 20261012-mavericks.1
at 2026-10-19T12:00:00Z components/golang/version
want 20261012.1 "a tag not shaped YYYYMMDD.N is not a release tag"
said "self-upstream-version: 20261012.1: no release tag yet"

empty never-own
at 2026-10-12T12:00:00Z README.md
at 2026-10-17T12:00:00Z tests/a.sh
want 20261017.1 "with no tag and no own-code commit ever, the date is REV's own UTC day"

fresh default-root
at 2026-10-19T12:00:00Z src/x.c
_rc=0; got="$(cd "$R" && sh "$S" 2>/dev/null)" || _rc=$?
[ "$_rc" = 0 ] && [ "$got" = 20261019.1 ] || { echo "FAIL: --root defaults to the current directory: exit $_rc, got '$got'"; exit 1; }

fresh shallow-src
at 2026-10-19T12:00:00Z src/x.c
git clone -q --depth 1 "file://$R" "$w/shallow"
refuses "release work needs fetch-depth: 0 and visible tags" "a shallow clone hides history and tags" --root "$w/shallow"

refuses "no-such-rev" "an unknown --ref is a usage error" --root "$R" --ref no-such-rev
mkdir -p "$w/not-a-repo"
refuses "not a git repository" "a directory outside any repo is refused" --root "$w/not-a-repo"
refuses "unknown option" "an unknown option is a usage error" --root "$R" --frobnicate

fresh merged
git -C "$R" tag 20261012.2
git -C "$R" checkout -qb side
at 2026-10-15T12:00:00Z src/side.c
git -C "$R" checkout -q -
at 2026-10-16T12:00:00Z components/golang/version
GIT_AUTHOR_DATE=2026-10-19T12:00:00Z GIT_COMMITTER_DATE=2026-10-19T12:00:00Z git -C "$R" merge -q --no-ff -m merge side
want 20261019.1 "own code merged on the 19th takes the merge's day, not the branch commit's"

fresh zero
git -C "$R" tag 20261012.3
git -C "$R" tag 20261012.08
at 2026-10-19T12:00:00Z components/golang/version
want 20261012.4 "a tag whose N has a leading zero is not a release tag"

fresh literal
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z tests/a.sh
_rc=0; got="$(GIT_LITERAL_PATHSPECS=1 sh "$S" --root "$R" 2>"$w/err")" || _rc=$?
[ "$_rc" = 0 ] && [ "$got" = 20261012.4 ] || { echo "FAIL: GIT_LITERAL_PATHSPECS must not disable the exclusions: exit $_rc, got '$got'"; exit 1; }

fresh starstar
deviation "$R" self-upstream-exclude x '**' 'everything'
refuses "self-upstream-exclude" "an exclusion of only * and / is refused" --root "$R"

echo "PASS: self-upstream-version"
