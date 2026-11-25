#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Versioning" -- release-version.sh is the one step every release takes its version
#       from; --previous is the newest tag of the scheme's shape merged into the ref.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-version.sh"
SU="$here/../scripts/self-upstream-version.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/release-version-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
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

at() {   # $1 = committer date, $2... = paths to change in $R, committed together
  _d="$1"; shift
  for _p in "$@"; do
    mkdir -p "$(dirname "$R/$_p")"
    n=$((n + 1)); echo "$n" >> "$R/$_p"
  done
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$_d" GIT_COMMITTER_DATE="$_d" git -C "$R" commit -qm "change $*"
}

decl() {   # $1 = a "## Versioning" entry line, committed in $R
  printf '# Ingredients\n\n## Versioning\n\n%s\n' "$1" > "$R/INGREDIENTS.md"
  git -C "$R" add INGREDIENTS.md
  git -C "$R" commit -qm "declare $1"
}

upstream() {   # $1 = upstream file, $2 = its line, committed in $R
  mkdir -p "$(dirname "$R/$1")"
  printf '%s\n' "$2" > "$R/$1"
  git -C "$R" add "$1"
  git -C "$R" commit -qm "upstream $2"
}

want() {   # $1 = expected tag, $2 = what it proves; further args go to the script
  _want="$1"; _why="$2"; shift 2
  _rc=0; got="$(sh "$S" --root "$R" "$@" 2>"$w/err")" || _rc=$?
  [ "$_rc" = 0 ] || { echo "FAIL: $_why: exit $_rc"; sed 's/^/    | /' "$w/err"; exit 1; }
  [ "$got" = "$_want" ] || { echo "FAIL: $_why: got '$got', want '$_want'"; sed 's/^/    | /' "$w/err"; exit 1; }
}

oneline() {   # the last run's stderr is exactly one release-version line
  [ "$(wc -l < "$w/err" | tr -d ' ')" = 1 ] || { echo "FAIL: stderr must be one line"; sed 's/^/    | /' "$w/err"; exit 1; }
  case "$(cat "$w/err")" in "release-version: $got: "*) : ;; *) echo "FAIL: stderr must start 'release-version: $got: ': $(cat "$w/err")"; exit 1 ;; esac
}

stderr_has() {
  grep -qF -- "$1" "$w/err" || { echo "FAIL: stderr lacks '$1'"; sed 's/^/    | /' "$w/err"; exit 1; }
}

fails() {   # $1 = exit code, $2 = text the output must contain, $3 = what it proves; further args to the script
  _code="$1"; _text="$2"; _why="$3"; shift 3
  _rc=0; sh "$S" "$@" >"$w/out" 2>&1 || _rc=$?
  [ "$_rc" = "$_code" ] || { echo "FAIL: $_why: want exit $_code, got $_rc"; sed 's/^/    | /' "$w/out"; exit 1; }
  grep -qF -- "$_text" "$w/out" || { echo "FAIL: $_why: output lacks '$_text'"; sed 's/^/    | /' "$w/out"; exit 1; }
}

empty port1
at 2026-10-12T12:00:00Z src/main.c
decl "- port"
upstream UPSTREAM_VERSION 1.2
want 1.2-mavericks.1 "port, no tags, auto" --product x --mode auto
oneline
want 1.2-mavericks.1 "port, no tags, local" --product x --mode local
[ ! -e "$R/VERSION" ] || { echo "FAIL: port must not write VERSION"; exit 1; }

empty port2
at 2026-10-12T12:00:00Z src/main.c
decl "- port"
upstream UPSTREAM_VERSION 1.2
git -C "$R" tag 1.2-mavericks.1
git -C "$R" tag 1.2-mavericks.2
want 1.2-mavericks.2 "port, auto keeps the current N" --product x --mode auto
want 1.2-mavericks.3 "port, local takes N+1" --product x --mode local
want 1.2-mavericks.2 "port --previous is the newest tag" --product x --mode local --previous

empty portfile
at 2026-10-12T12:00:00Z src/main.c
decl "- rt: port rt/UPSTREAM_VERSION"
upstream rt/UPSTREAM_VERSION 6.3
want 6.3-mavericks.1 "port reads the declared upstream file" --product rt --mode local

empty portderived
at 2026-10-12T12:00:00Z src/main.c
decl "- port"
mkdir -p "$R/build"
printf '#!/bin/sh\necho 9.9 > "$MAVERICKS_ROOT/UPSTREAM_VERSION"\n' > "$R/build/derive-upstream-version.sh"
git -C "$R" add build
git -C "$R" commit -qm "derive"
want 9.9-mavericks.1 "port runs the tracked derive script when the upstream file is untracked" --product x --mode local
oneline
[ ! -e "$R/VERSION" ] || { echo "FAIL: port must not write VERSION"; exit 1; }

mkdir -p "$w/stub"
cp "$here/../scripts/"*.sh "$w/stub/"
cp -R "$here/../scripts/lib" "$w/stub/lib"
printf '#!/bin/sh\nexit 0\n' > "$w/stub/version.sh"
_rc=0; sh "$w/stub/release-version.sh" --root "$w/port1" --product x >"$w/out" 2>&1 || _rc=$?
[ "$_rc" = 1 ] || { echo "FAIL: an empty FULL= must exit 1, got $_rc"; exit 1; }
grep -qF "x: version.sh printed no FULL=" "$w/out" || { echo "FAIL: empty FULL= message"; cat "$w/out"; exit 1; }

empty selfdate
at 2026-10-12T12:00:00Z src/main.c
decl "- self-upstream-date"
git -C "$R" tag 20261012.3
at 2026-10-19T12:00:00Z src/x.c
expect="$(sh "$SU" --root "$R" 2>/dev/null)"
want "$expect" "self-upstream-date is self-upstream-version.sh's answer" --product x
oneline
want 20261012.3 "self-upstream-date --previous" --product x --previous

empty datesemver
at 2026-10-12T12:00:00Z src/main.c
decl "- date-semver"
git -C "$R" tag v0.0.20261012.1
at 2026-10-19T12:00:00Z components/golang/version
want v0.0.20261012.2 "date-semver, ingredient-only" --product x
oneline
want v0.0.20261012.1 "date-semver --previous" --product x --previous

empty counter
at 2026-10-12T12:00:00Z src/main.c
decl "- counter"
upstream UPSTREAM_VERSION 1.0
git -C "$R" tag v1.0.916
git -C "$R" tag v1.0.920
git -C "$R" tag v1
want v1.0.921 "counter is one past the largest N" --product x
oneline
stderr_has v1.0.920
want v1.0.920 "counter --previous" --product x --previous
upstream UPSTREAM_VERSION 1.1
want v1.1.1 "counter restarts when the line changes" --product x
want v1.0.920 "counter --previous crosses lines" --product x --previous
upstream UPSTREAM_VERSION 1.0.3
fails 1 UPSTREAM_VERSION "counter refuses a three-part line" --root "$R" --product x

empty counternotmerged
at 2026-10-12T12:00:00Z src/main.c
decl "- counter"
upstream UPSTREAM_VERSION 1.0
git -C "$R" tag v1.0.920
git -C "$R" checkout -q -b side
at 2026-10-13T12:00:00Z src/side.c
git -C "$R" tag v1.0.950
git -C "$R" checkout -q -
want v1.0.921 "counter ignores tags not merged into the ref" --product x

for f in port1 counter selfdate; do
  rm -rf "$w/shallow-$f"
  git clone -q --depth 1 "file://$w/$f" "$w/shallow-$f"
  fails 2 "fetch-depth: 0" "a shallow $f clone is refused" --root "$w/shallow-$f" --product x
done

R="$w/counter"
fails 2 "must be HEAD" "--ref not HEAD for a tree-reading scheme" --root "$R" --product x --ref HEAD~1
fails 2 "not a revision" "unknown ref" --root "$R" --product x --ref nonesuch
fails 2 "usage:" "no --product" --root "$R"
fails 2 "not a git repository" "not a repo" --root "$w" --product x

empty nodecl
at 2026-10-12T12:00:00Z src/main.c
fails 1 "declares no versioning scheme" "no declaration" --root "$R" --product x

echo "release-version-test: ok"
