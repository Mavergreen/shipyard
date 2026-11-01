#!/bin/sh
# platform: host-agnostic
#   usage: check-lib-git-test.sh
#          What the checks ask git, through check-lib.sh: the tracked-file list (an unreadable
#          SHIPYARD_CHECK_FILES fails tracked-files; a non-ASCII path is listed as itself), and
#          chk_ignored, which answers only when git can and otherwise reports its check as not run
#          (never a pass, never a false failure). Every case runs, and each failure prints its own line.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
lib="$here/scripts/check-lib.sh"
sc="$here/scripts/shipyard-check"
fx="$here/tests/fixtures/checks"
. "$here/tests/lib/fixture_tree.sh"
t="$(mktemp -d "${TMPDIR:-/tmp}/check-lib-git-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
unset SHIPYARD_CHECK_RUNLOG SHIPYARD_CHECK_FAILLOG SHIPYARD_CHECK_NOTRUNLOG SHIPYARD_CHECK_SELECTED \
  SHIPYARD_CHECK_DIST SHIPYARD_CHECK_FILES GITHUB_REPOSITORY
SHIPYARD_CHECK_DIR="$here/scripts"; export SHIPYARD_CHECK_DIR
GIT_CEILING_DIRECTORIES="$t"; export GIT_CEILING_DIRECTORIES
bad=0
fail() { echo "FAIL $1"; bad=1; }

rc=0; (cd "$t" && SHIPYARD_CHECK_FILES="$t/no-such-list" sh -c '. "$1"; chk_tracked_files' sh "$lib") > "$t/out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q '^tracked-files: ' "$t/out" || fail "M1: an unreadable SHIPYARD_CHECK_FILES fails tracked-files: $(cat "$t/out")"

if command -v git >/dev/null 2>&1; then
  mkdir "$t/utf"
  (cd "$t/utf" && git init -q && git config core.precomposeunicode false \
     && : > "$(printf 'stra\303\237e.sh')" && git add -A) >/dev/null 2>&1
  got="$(cd "$t/utf" && sh -c '. "$1"; chk_tracked_files' sh "$lib")"
  [ "$got" = "$(printf 'stra\303\237e.sh')" ] || fail "M2: a non-ASCII tracked path is listed as itself, got: $got"
fi

mkdir "$t/curl"; printf '#!/bin/sh\ncurl -o x https://example.com/x\n' > "$t/curl/get.sh"
rc=0; (cd "$t/curl" && SHIPYARD_CHECK_FILES="$t/no-such-list" sh "$sc" --only bare-curl) > "$t/out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q '^tracked-files: ' "$t/out" || fail "--only bare-curl reports the unreadable tracked-file list it checked nothing against, got $rc: $(cat "$t/out")"
rc=0; (SHIPYARD_CHECK_SELECTED="bare-curl" SHIPYARD_PYTHON3="$t/no-such-python" sh -c '. "$1"; . "$2"; chk_python3' sh "$lib" "$here/scripts/lib/py.sh") > "$t/out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] && grep -q '^python3: ' "$t/out" || fail "a missing python3 is reported when it isn't selected: $(cat "$t/out")"

mkdir "$t/nogit"; printf '#!/bin/sh\necho "git: hidden" >&2\nexit 127\n' > "$t/nogit/git"; chmod +x "$t/nogit/git"
for id in version-sh-tracked build-dirs-ignored user-presets-ignored; do
  for kind in pass fail; do
    c="$t/$id-$kind"; fixture_tree "$fx" "$fx/$id/$kind" "$c"
    rc=0; (cd "$c" && PATH="$t/nogit:$PATH" SHIPYARD_CHECK_FILES="$c/FILES" sh "$sc" --only "$id") > "$t/out" 2>&1 || rc=$?
    [ "$rc" = 0 ] || fail "I3: $id/$kind without git is not a false failure, got $rc: $(cat "$t/out")"
    grep -q "^$id: not run: git cannot say" "$t/out" || fail "I3: $id/$kind without git says it did not run: $(cat "$t/out")"
    [ "$(tail -n 1 "$t/out")" = "shipyard-check: 0 checks, 0 failed, 1 not run" ] || fail "I3: $id/$kind without git is not counted as a pass: $(tail -n 1 "$t/out")"
  done
done

c="$t/tree"; mkdir "$c"
rc=0; (cd "$c" && PATH="$t/nogit:$PATH" sh "$sc" --only tree-clean) > "$t/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -q '^tree-clean: not run: git is missing' "$t/out" || fail "I3: tree-clean under shipyard-check without git is not run: $(cat "$t/out")"

[ "$bad" -eq 0 ] || exit 1
echo "PASS check-lib-git"
