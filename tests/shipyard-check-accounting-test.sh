#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-check-accounting-test.sh
#          The real gate and dispatcher, never stubs: a repo with no release.yml still runs every
#          repo-wide rule, and reports the release rules as not run; --dist refuses a directory with
#          no artifact; --only reports and counts only what it selects; a deviation key is never a
#          check. Every case runs, and each failure prints its own FAIL line.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
sc="$here/scripts/shipyard-check"
fx="$here/tests/fixtures/checks"
. "$here/tests/lib/fixture_tree.sh"
t="$(mktemp -d "${TMPDIR:-/tmp}/shipyard-check-accounting-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
unset SHIPYARD_CHECK_RUNLOG SHIPYARD_CHECK_FAILLOG SHIPYARD_CHECK_NOTRUNLOG SHIPYARD_CHECK_SELECTED \
  SHIPYARD_CHECK_DIST SHIPYARD_CHECK_REPO SHIPYARD_CHECK_VERSION SHIPYARD_CHECK_FILES GITHUB_REPOSITORY
GIT_CEILING_DIRECTORIES="$t"; export GIT_CEILING_DIRECTORIES
bad=0
fail() { echo "FAIL $1"; bad=1; }

r="$t/norel"; mkdir -p "$r/.github/workflows" "$r/build"
printf '{"extends":["github>Mavergreen/shipyard"]}\n' > "$r/.github/renovate.json"
printf 'name: ci\non:\n  pull_request:\n    branches: [main]\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: sudo apt-get install -y jq\n' > "$r/.github/workflows/ci.yml"
printf '.superpowers/\n.idea/\n' > "$r/.gitignore"
printf '#!/bin/sh\ncurl -fsSL -o "$2" "$1"\n' > "$r/build/fetch.sh"
printf '#!/bin/sh\nbrew install jq\n' > "$r/build/deps.sh"
printf '#!/bin/sh\necho "run: sudo make install"\n' > "$r/build/hint.sh"
printf '.github/renovate.json\n.github/workflows/ci.yml\n.gitignore\nbuild/fetch.sh\nbuild/deps.sh\nbuild/hint.sh\n' > "$t/norel.files"
rc=0; (cd "$r" && SHIPYARD_CHECK_FILES="$t/norel.files" sh "$sc") > "$t/out" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "C1: a repo with no release.yml that breaks repo-wide rules exits 1, got $rc"
for id in bare-curl brew apt docs-no-sudo; do
  grep -q "^$id: " "$t/out" && grep -q "^  more: shipyard-check --explain $id\$" "$t/out" \
    || fail "C1: with no release.yml, $id still runs and fails"
done
for id in release-concurrency concurrency-group publish-order permissions-contents-read; do
  grep -q "^$id: not run: no .github/workflows/release.yml" "$t/out" || fail "C1: $id, which reads release.yml, says it did not run"
done
[ "$(sed -n 's/^  more: shipyard-check --explain //p' "$t/out" | sort -u | tr '\n' ' ')" = "apt bare-curl brew docs-no-sudo " ] \
  || fail "C1: exactly the four repo-wide rules fail: $(sed -n 's/^  more: shipyard-check --explain //p' "$t/out" | tr '\n' ' ')"
grep -q '^shipyard-check: [0-9]* checks, 4 failed, [0-9]* not run$' "$t/out" || fail "C1: the count names the four failures and the rules not run: $(tail -n 1 "$t/out")"
for id in comments host-tools ingredient-pins; do
  grep -q "^$id: not run: " "$t/out" || fail "M3: $id, with nothing to check, says it did not run"
done

c="$t/clean"; fixture_tree "$fx" "$fx/release-concurrency/pass-no-release" "$c"
rc=0; (cd "$c" && SHIPYARD_CHECK_FILES="$c/FILES" sh "$sc" --only release-concurrency bare-curl brew vendored) > "$t/out" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "C1: a clean repo with no release.yml passes, got $rc: $(cat "$t/out")"
[ "$(tail -n 1 "$t/out")" = "shipyard-check: 3 checks, 0 failed, 1 not run" ] || fail "C1: the release rule is counted as not run: $(tail -n 1 "$t/out")"

for d in "$t/no-such-dist" "$t/empty-dist"; do
  rm -rf "$t/empty-dist"; mkdir "$t/empty-dist"
  rc=0; SHIPYARD_CHECK_VERSION=1.0.0-mavericks.1 sh "$sc" --dist "$d" > "$t/out" 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "C2: --dist $(basename "$d") exits 2, got $rc: $(tail -n 1 "$t/out")"
  grep -qF -- "$d" "$t/out" || fail "C2: the refusal names $(basename "$d")"
done

rc=0; SHIPYARD_CHECK_VERSION=1.0.0-mavericks.1 sh "$sc" --dist "$fx/compat-archs/pass/dist" --only pkg-in-place gui-relaunch-safe > "$t/out" 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(tail -n 1 "$t/out")" = "shipyard-check: 0 checks, 0 failed, 2 not run" ] \
  || fail "M3: a dist with no .pkg reports the pkg checks not run, got $rc: $(tail -n 1 "$t/out")"
if sh -c '. "$1"; mach_tool OTOOL && mach_tool LIPO' sh "$here/scripts/lib/macho-tools.sh" >/dev/null 2>&1; then
  rc=0; (cd "$t" && SHIPYARD_CHECK_VERSION=1.0.0-mavericks.1 SHIPYARD_CHECK_REPO="$t" sh "$sc" --dist "$fx/bundle-id/pass/dist" --only enclosure notes floor) > "$t/out" 2>&1 || rc=$?
  [ "$rc" = 0 ] && [ "$(tail -n 1 "$t/out")" = "shipyard-check: 1 checks, 0 failed, 2 not run" ] \
    || fail "M3: a dist with no appcast reports the appcast checks not run, got $rc: $(tail -n 1 "$t/out")"
fi

v="$t/vi"; fixture_tree "$fx" "$fx/version-ignored/fail" "$v"
rc=0; (cd "$v" && SHIPYARD_CHECK_FILES="$v/FILES" sh "$sc" --only release-concurrency) > "$t/out" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "I2: --only release-concurrency passes a repo whose only fault is version-ignored, got $rc"
grep -q '^version-ignored' "$t/out" && fail "I2: --only release-concurrency prints no version-ignored failure"
[ "$(tail -n 1 "$t/out")" = "shipyard-check: 1 checks, 0 failed" ] || fail "I2: --only counts what it selects: $(tail -n 1 "$t/out")"

for id in host linux; do
  rc=0; sh "$sc" --only "$id" > "$t/out" 2>&1 || rc=$?
  [ "$rc" = 2 ] && grep -q 'deviation key' "$t/out" || fail "I6: --only $id refuses a deviation key, got $rc"
done
sh "$sc" --list | awk -F'\t' '$1 == "linux" || $1 == "host" { print $2 }' | grep -qvx key && fail "I6: linux and host are registered as keys"

[ "$bad" -eq 0 ] || exit 1
echo "PASS shipyard-check-accounting"
