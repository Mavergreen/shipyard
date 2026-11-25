#!/bin/sh
# platform: host-agnostic
# spec: scripts/action-ref-moves.sh -- only a step's or a job's uses: whose ref changed is a move.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
A="$here/../scripts/action-ref-moves.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/action-ref-moves-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
GIT_CEILING_DIRECTORIES="$w"; export GIT_CEILING_DIRECTORIES
TAB="$(printf '\t')"

repo() {   # $1 = case, $2 = the workflow's first text; R is a repo with it committed and tagged base
  R="$w/$1"
  git init -q "$R"
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name tester
  git -C "$R" config commit.gpgsign false
  mkdir -p "$R/.github/workflows"
  printf '%s' "$2" > "$R/.github/workflows/ci.yml"
  git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" tag base
}

move() {   # $1 = the workflow's next text, committed in $R
  printf '%s' "$1" > "$R/.github/workflows/ci.yml"
  git -C "$R" add -A; git -C "$R" commit -qm next
}

run() {   # $1 = exit code wanted, $2 = stdout wanted exactly, $3 = what it proves
  _rc=0; sh "$A" --root "$R" base HEAD >"$w/out" 2>"$w/err" || _rc=$?
  [ "$_rc" = "$1" ] || { echo "FAIL: $3: want exit $1, got $_rc"; cat "$w/out" "$w/err"; exit 1; }
  [ "$(cat "$w/out")" = "$2" ] || { echo "FAIL: $3: want '$2'"; sed 's/^/    | /' "$w/out"; exit 1; }
}

STEP='jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@%s
      - name: cache
        uses: actions/cache@%s
        with:
          uses: foo/bar@%s
  scan:
    uses: Mavergreen/shipyard/.github/workflows/scan.yml@%s
'
wf() { printf "$STEP" "$@"; }
crlf() { awk '{ printf "%s\r\n", $0 }'; }

repo moved "$(wf '0123abc # v4.1.1' v4 v1 v1)"
move "$(wf '4567def # v4.2.0' v5 v1 v2)"
run 0 "Mavergreen/shipyard${TAB}v1${TAB}v2
actions/cache${TAB}v4${TAB}v5
actions/checkout${TAB}v4.1.1${TAB}v4.2.0" "a step's, a named step's and a job's uses: are moves"

repo commentonly "$(wf '0123abc # v4.1.1' v4 v1 v1)"
move "$(wf '0123abc # v4.1.2' v4 v1 v1)"
run 1 "" "a comment-only edit with the same ref is not a move"
grep -q 'other than an action' "$w/err" || { echo "FAIL: commentonly names the change"; cat "$w/err"; exit 1; }

repo withinput "$(wf '0123abc # v4.1.1' v4 v1 v1)"
move "$(wf '0123abc # v4.1.1' v4 v2 v1)"
run 1 "" "a with: input named uses: is not an action's ref"

repo crlf "$(wf '0123abc # v4.1.1' v4 v1 v1 | crlf)"
move "$(wf '4567def # v4.2.0' v4 v1 v1 | crlf)"
run 0 "actions/checkout${TAB}v4.1.1${TAB}v4.2.0" "a CRLF workflow's ref and version carry no carriage return"

repo crlfref "$(wf 0123abc v4 v1 v1 | crlf)"
move "$(wf 4567def v4 v1 v1 | crlf)"
run 0 "actions/checkout${TAB}0123abc${TAB}4567def" "a CRLF workflow's bare ref carries no carriage return"

echo "PASS: action-ref-moves"
