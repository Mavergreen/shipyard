#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Release notes" -- version-check (no notes yet) and the publish gate (the generated
#       notes) give one verdict, so a release refused at publish was already refused before any build.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
SCR="$here/../scripts"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/release-checks-agree-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
GIT_CEILING_DIRECTORIES="$w"; export GIT_CEILING_DIRECTORIES
GITHUB_SERVER_URL=https://github.com; GITHUB_REPOSITORY=Mavergreen/fixture
export GITHUB_SERVER_URL GITHUB_REPOSITORY
unset GITHUB_ACTIONS

commit() {   # $1 = message; commits $R's working tree
  git -C "$R" add -A
  git -C "$R" commit -qm "$1"
}

put() {   # $1 = path in $R, $2 = its text
  mkdir -p "$(dirname "$R/$1")"
  printf '%s\n' "$2" > "$R/$1"
}

workflow() {   # $1 = checkout's ref
  put .github/workflows/ci.yml "on: push
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@$1
      - run: make"
}

counter_repo() {   # $1 = case; R is a counter repo released at v1.0.920
  R="$w/$1"
  git init -q "$R"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name tester
  git -C "$R" config commit.gpgsign false
  printf '# Ingredients\n\n## Versioning\n\n- counter\n\n## Conformance deviations\n\n- pin:scripts/*.pin: Renovate bumps them\n' > "$R/INGREDIENTS.md"
  put UPSTREAM_VERSION 1.0
  put src/main.c 1
  put components/clang22/version 22.1.8-mavericks.12
  put scripts/recaulk.pin RECAULK_VERSION=20261124.7
  workflow v6
  commit base
  git -C "$R" tag v1.0.920
}

port_repo() {   # $1 = case; R is a port repo released at 1.2-mavericks.1
  counter_repo "$1"
  printf '# Ingredients\n\n## Versioning\n\n- port\n' > "$R/INGREDIENTS.md"
  put UPSTREAM_VERSION 1.2
  put build/upstream-release-notes-url.sh 'printf "https://example.com/notes/%s\n" "$1"'
  commit port
  git -C "$R" tag 1.2-mavericks.1
}

verdicts() {   # $1 = product noun, further = --mode; prints "early=<rc> late=<rc>" for HEAD in $R
  _noun="$1"; shift
  _v="$(cd "$R" && sh "$SCR/release-version.sh" --product x "$@" 2>/dev/null)"
  _e=0; (cd "$R" && sh "$SCR/check-release-version.sh" --product x --version "$_v" --sha HEAD --publishing yes "$@") >"$w/early" 2>&1 || _e=$?
  _l=0
  (cd "$R" && MAVERICKS_ROOT="$R" sh "$SCR/release-notes.sh" --tag "$_v" --version "${_v#v}" --product "$_noun" --out "$w/NOTES.md") >"$w/notes.log" 2>&1 || _l=$?
  if [ "$_l" = 0 ]; then
    (cd "$R" && sh "$SCR/check-release-version.sh" --product x --version "$_v" --sha HEAD --publishing yes --notes-file "$w/NOTES.md" "$@") >"$w/late" 2>&1 || _l=$?
  else
    cp "$w/notes.log" "$w/late"
  fi
  echo "early=$_e late=$_l"
}

agree() {   # $1 = the verdict both must give (pass or refuse), $2 = what it proves, further = verdicts' args
  _want="$1"; _why="$2"; shift 2
  _got="$(verdicts "$@")"
  case "$_want:$_got" in
    pass:"early=0 late=0") return 0 ;;
    refuse:"early=1 late=1") return 0 ;;
  esac
  echo "FAIL: $_why: want both to $_want, got $_got"
  sed 's/^/    early | /' "$w/early"; sed 's/^/    late  | /' "$w/late"
  [ ! -f "$w/NOTES.md" ] || sed 's/^/    notes | /' "$w/NOTES.md"
  exit 1
}

counter_repo action
workflow v7
commit "bump checkout"
agree pass "an action's ref bump" Fixture

counter_repo components
put components/clang22/version 22.1.8-mavericks.16
commit "bump clang22"
agree pass "a components/*/version bump, with no repackage caller" Fixture

counter_repo pin
put scripts/recaulk.pin RECAULK_VERSION=20261125.1
commit "bump recaulk"
agree pass "a declared .pin bump" Fixture

port_repo upstream
put UPSTREAM_VERSION 1.3
commit "upstream 1.3"
agree pass "a port's UPSTREAM_VERSION bump" Fixture --mode auto

counter_repo line
put UPSTREAM_VERSION 1.1
commit "line 1.1"
agree refuse "a counter's line move, with no notes" Fixture

counter_repo own
put src/main.c 2
commit "own code"
agree refuse "own code, with no notes" Fixture

echo "PASS: release-checks-agree"
