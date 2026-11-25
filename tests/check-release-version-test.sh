#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Versioning" and "Release notes" -- a release's version is the one its declared
#       scheme derives, and a publishing run has committed notes for it unless only pins moved.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/check-release-version.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/check-release-version-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
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

chk() {   # $1 = exit code, $2 = text the output must contain (or ""), $3 = what it proves; further args, run in $R
  _code="$1"; _text="$2"; _why="$3"; shift 3
  _rc=0; (cd "$R" && sh "$C" "$@") >"$w/out" 2>&1 || _rc=$?
  [ "$_rc" = "$_code" ] || { echo "FAIL: $_why: want exit $_code, got $_rc"; sed 's/^/    | /' "$w/out"; exit 1; }
  [ -z "$_text" ] || grep -qF -- "$_text" "$w/out" || { echo "FAIL: $_why: output lacks '$_text'"; sed 's/^/    | /' "$w/out"; exit 1; }
}

counter_repo() {
  empty "$1"
  at 2026-10-12T12:00:00Z src/main.c
  decl "- counter"
  upstream UPSTREAM_VERSION 1.0
  git -C "$R" tag v1.0.920
}

counter_repo match
chk 0 "not publishing" "match" --product x --version v1.0.921 --sha HEAD --publishing no
chk 0 "check-release-version: ok — v1.0.921" "match prints ok" --product x --version v1.0.921 --sha HEAD --publishing no
chk 1 "this release is v1.0.921" "vspelling" --product x --version 1.0.921 --sha HEAD --publishing no
chk 1 "check-release-version: " "a refusal starts with the script's name" --product x --version 1.0.921 --sha HEAD --publishing no
chk 2 "" "headnotsha" --product x --version v1.0.921 --sha HEAD~1 --publishing no
grep -qF "check out the commit being released" "$w/out" || { echo "FAIL: headnotsha message"; cat "$w/out"; exit 1; }
chk 2 "yes" "publishingword" --product x --version v1.0.921 --sha HEAD --publishing true
grep -qw "no" "$w/out" || { echo "FAIL: publishingword must name no"; cat "$w/out"; exit 1; }
chk 2 "auto" "modeword" --product x --version v1.0.921 --sha HEAD --publishing no --mode later
chk 2 "" "no --version" --product x --sha HEAD --publishing no

selfdate_repo() {
  empty "$1"
  at 2026-10-25T12:00:00Z payload/x menubar/y
  decl "- self-upstream-date"
  git -C "$R" tag 20261025.19
}

selfdate_repo mismatch
at 2026-11-24T12:00:00Z payload/x
at 2026-11-24T13:00:00Z menubar/y
chk 1 "version 20261025.20 but own code changed on 2026-11-24 (menubar/, payload/): this release is 20261124.1 — release.yml must take its version from release-version.sh" \
  "mismatch" --product x --version 20261025.20 --sha HEAD --publishing no

selfdate_repo manydirs
at 2026-11-24T12:00:00Z a/1 b/1 c/1 d/1 e/1 f/1 top.c
chk 1 "own code changed on 2026-11-24 (a/, b/, c/, d/, e/, …): this release" "dirs cut to five" \
  --product x --version 20261025.20 --sha HEAD --publishing no

R="$w/mismatch"
chk 1 "no release notes for 20261124.1 — add release-notes/20261124.1/changes/<slug> (own code changed since 20261025.19: menubar/, payload/)" \
  "notes" --product x --version 20261124.1 --sha HEAD --publishing yes
at 2026-11-24T14:00:00Z release-notes/20261124.1/changes/stop-stays
chk 0 "check-release-version: ok — 20261124.1" "committed notes pass" --product x --version 20261124.1 --sha HEAD --publishing yes

port_repo() {   # $1 = case, $2 = the "## Versioning" entry, $3 = upstream file
  empty "$1"
  at 2026-10-12T12:00:00Z src/main.c payload/a components/zlib/version
  decl "$2"
  upstream "$3" 1.2
  git -C "$R" tag 1.2-mavericks.1
}

port_repo pinsonly "- port" UPSTREAM_VERSION
at 2026-10-13T12:00:00Z components/zlib/version
chk 0 "check-release-version: ok — 1.2-mavericks.2" "pinsonly" --product x --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes
printf '## What changed\n\nthings\n' > "$w/bare-notes"
chk 1 "do not say what moved" "pinsonly, generated notes without markers" \
  --product x --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes --notes-file "$w/bare-notes"
printf '## What changed\n\n### Build ingredients\n\n- zlib\n' > "$w/ingr-notes"
chk 0 "" "pinsonly, generated notes with Build ingredients" \
  --product x --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes --notes-file "$w/ingr-notes"
printf -- '- New upstream: 1.3\n' > "$w/up-notes"
chk 0 "" "pinsonly, generated notes with New upstream" \
  --product x --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes --notes-file "$w/up-notes"

port_repo upstreamfile "- rt: port rt/UPSTREAM_VERSION" rt/UPSTREAM_VERSION
upstream rt/UPSTREAM_VERSION 1.3
chk 0 "check-release-version: ok — 1.3-mavericks.1" "the declared upstream file is a pin, not own code" \
  --product rt --version 1.3-mavericks.1 --sha HEAD --publishing yes

port_repo workflowonly "- port" UPSTREAM_VERSION
at 2026-10-13T12:00:00Z .github/workflows/ci.yml
chk 1 "no pin moved" "workflowonly" --product x --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes

port_repo rename "- port" UPSTREAM_VERSION
mkdir -p "$R/ingredients"; git -C "$R" mv payload/a ingredients/a
git -C "$R" commit -qm "move a"
chk 1 "own code changed" "rename" --product x --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes

port_repo nested "- w: port" UPSTREAM_VERSION
at 2026-10-12T13:00:00Z release-notes/w/1.2-mavericks.1/changes/first
at 2026-10-13T12:00:00Z src/main.c release-notes/1.2-mavericks.2/changes/x
chk 1 "release-notes/w/1.2-mavericks.2/changes/<slug>" "nested" --product w --version 1.2-mavericks.2 --sha HEAD --mode local --publishing yes

semver_repo() {   # $1 = case
  empty "$1"
  at 2026-10-12T12:00:00Z src/main.c
  decl "- semver"
  git -C "$R" tag v1.2.5
}

semver_repo next
at 2026-10-13T12:00:00Z src/main.c release-notes/v1.3.0/changes/feature
mkdir -p "$R/release-notes/next"
printf 'minor\n' > "$R/release-notes/next/kind"
git -C "$R" add release-notes
git -C "$R" commit -qm "kind"
chk 1 "release-notes/next is still there — rename it to release-notes/v1.3.0" "next" --product x --version v1.3.0 --sha HEAD --publishing yes

semver_repo semverkind
at 2026-10-13T12:00:00Z src/main.c release-notes/v1.2.6/changes/fix
chk 1 "semver release v1.2.6 has no kind — write major, minor or patch to release-notes/v1.2.6/kind" "semverkind" \
  --product x --version v1.2.6 --sha HEAD --publishing yes
chk 0 "" "semverkind, not publishing" --product x --version v1.2.6 --sha HEAD --publishing no

empty first
at 2026-10-12T12:00:00Z src/main.c
decl "- port"
upstream UPSTREAM_VERSION 1.2
chk 1 "no release notes for 1.2-mavericks.1 — add release-notes/1.2-mavericks.1/changes/<slug> (a first release)" "first" \
  --product x --version 1.2-mavericks.1 --sha HEAD --mode local --publishing yes

echo "check-release-version-test: ok"
