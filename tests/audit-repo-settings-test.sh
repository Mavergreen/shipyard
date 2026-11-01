#!/bin/sh
# platform: host-agnostic
# spec: scripts/audit-repo-settings.sh -- gh is a stub answering from files under $GH_STUB, so no network is touched
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/audit-repo-settings.sh"
SC="$here/../scripts/shipyard-check"
w="$(mktemp -d "${TMPDIR:-/tmp}/audit-repo-settings-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }
first_id() { sed -n 1p "$1" | cut -d: -f1; }

mkdir -p "$w/bin" "$w/gh"
cp "$here/lib/gh-stub.sh" "$w/bin/gh"
chmod +x "$w/bin/gh"
GH_STUB="$w/gh"; export GH_STUB
reset() {
  rm -rf "$w/gh"; mkdir -p "$w/gh"
  printf "Token scopes: 'admin:org', 'repo'\n" > "$w/gh/scopes"
  printf 'false\n' > "$w/gh/shipyard-admin"
  printf 'good\nnoauto\nnoprot\nplain\n' > "$w/gh/repos"
  for r in good noauto noprot; do : > "$w/gh/product-$r"; done
  printf 'true\n' > "$w/gh/am-good"; printf 'true\n' > "$w/gh/am-noauto"; printf 'true\n' > "$w/gh/am-noprot"; printf 'true\n' > "$w/gh/am-plain"
  printf 'false\n' > "$w/gh/am-noauto"
  printf 'build\n' > "$w/gh/ctx-good"; printf 'build\n' > "$w/gh/ctx-noauto"
  for r in good noauto noprot; do
    mkdir -p "$w/gh/raw-$r/.github/workflows"
    printf 'name: release\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' > "$w/gh/raw-$r/.github/workflows/release.yml"
  done
}
vmjob() {  # $1 = repo: its release.yml gains a job that runs the 10.9 guest, named on-target
  printf '  vm:\n    name: on-target\n    runs-on: ubuntu-latest\n    steps:\n      - uses: Mavergreen/mavericks-vm@v1\n' >> "$w/gh/raw-$1/.github/workflows/release.yml"
}
for id in repo-public repo-auto-merge repo-required-context repo-requires-on-target; do
  printf '%s\trepo-state\tscripts/audit-repo-settings.sh\tx\tP1\n' "$id"
done > "$w/reg"
SHIPYARD_CHECK_REGISTRY="$w/reg"; export SHIPYARD_CHECK_REGISTRY
run() { rc=0; PATH="$w/bin:$PATH" sh "$@" > "$w/out" 2> "$w/err" || rc=$?; }

reset
run "$S"
[ "$rc" -eq 1 ] || fail "a repo with auto-merge off and a repo with no protection should exit 1, got $rc"
grep -q '^repo-auto-merge: .*Mavergreen/noauto' "$w/err" || fail "the auto-merge failure should open with its id and name the repo: $(cat "$w/err")"
grep -q '^repo-required-context: .*Mavergreen/noprot' "$w/err" || fail "the required-context failure should open with its id and name the repo: $(cat "$w/err")"
grep -q 'Mavergreen/good' "$w/err" && fail "a healthy repo must not be named: $(cat "$w/err")"
grep -q 'Mavergreen/plain' "$w/err" && fail "a repo with no release.yml is not a product repo: $(cat "$w/err")"
[ "$(first_id "$w/err")" = repo-auto-merge ] || fail "the first line of stderr should be an id: $(cat "$w/err")"

reset; printf 'true\n' > "$w/gh/am-noauto"; : > "$w/gh/ctx-noprot"; printf 'build\n' > "$w/gh/ctx-noprot"
run "$S"
[ "$rc" -eq 0 ] || fail "a healthy org should exit 0, got $rc: $(cat "$w/err")"
grep -q '^audit-repo-settings: ok' "$w/out" || fail "a healthy org should print the ok line: $(cat "$w/out")"

reset; printf 'false\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"
run "$S"
[ "$rc" -eq 1 ] || fail "only auto-merge off should exit 1, got $rc"
grep -q '^repo-auto-merge: ' "$w/err" || fail "auto-merge off is repo-auto-merge: $(cat "$w/err")"
grep -q '^repo-required-context: ' "$w/err" && fail "it must not also be a required-context failure: $(cat "$w/err")"

reset; printf 'true\n' > "$w/gh/am-noauto"; : > "$w/gh/ctx-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"
run "$S"
[ "$rc" -eq 1 ] || fail "a protected repo with an empty required list should exit 1, got $rc"
grep -q '^repo-required-context: .*Mavergreen/noauto' "$w/err" || fail "an empty required-check list is repo-required-context: $(cat "$w/err")"

reset; : > "$w/gh/noauth"
run "$SC" --repo-state
[ "$rc" -eq 2 ] || fail "--repo-state with no gh login should exit 2, got $rc"
grep -q 'needs an admin token: `gh auth status` must show `admin:org` or repo admin' "$w/err" || fail "it should say it needs an admin token: $(cat "$w/err")"

reset; printf "Token scopes: 'repo'\n" > "$w/gh/scopes"
run "$SC" --repo-state
[ "$rc" -eq 2 ] || fail "--repo-state with a token that is neither admin:org nor repo admin should exit 2, got $rc"

reset; printf "Token scopes: 'repo'\n" > "$w/gh/scopes"; printf 'true\n' > "$w/gh/shipyard-admin"
run "$SC" --repo-state
[ "$rc" -eq 1 ] || fail "repo admin should be enough to run, and this org has failures: got $rc: $(cat "$w/err")"
grep -qx 'shipyard-check: 4 checks, 2 failed' "$w/out" || fail "the dispatcher should count both ids failed: $(cat "$w/out")"

reset; printf 'true\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"
run "$SC" --repo-state
[ "$rc" -eq 0 ] || fail "a healthy org under --repo-state should exit 0, got $rc: $(cat "$w/err")"
grep -qx 'shipyard-check: 4 checks, 0 failed' "$w/out" || fail "the dispatcher should count four checks: $(cat "$w/out")"

reset; printf 'true\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"; printf 'private\n' > "$w/gh/vis-plain"
run "$S"
[ "$rc" -eq 1 ] || fail "a private repo should exit 1, got $rc"
grep -q '^repo-public: .*Mavergreen/plain is public' "$w/err" || fail "a private repo is repo-public, even with no release.yml: $(cat "$w/err")"

reset; printf 'true\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"; vmjob good
run "$S"
[ "$rc" -eq 1 ] || fail "a 10.9 job main does not require should exit 1, got $rc"
grep -q '^repo-requires-on-target: .*Mavergreen/good' "$w/err" || fail "an unrequired 10.9 job is repo-requires-on-target: $(cat "$w/err")"
grep -q 'main does not require on-target' "$w/err" || fail "it names the job by its check name: $(cat "$w/err")"

reset; printf 'true\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"; vmjob good; printf 'build,on-target\n' > "$w/gh/ctx-good"
run "$S"
[ "$rc" -eq 0 ] || fail "a required 10.9 job should pass, got $rc: $(cat "$w/err")"

reset; printf 'true\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"; rm -r "$w/gh/raw-good"
run "$S"
[ "$rc" -eq 1 ] || fail "a release.yml that cannot be read should exit 1, got $rc"
grep -q '^repo-requires-on-target: .*Mavergreen/good' "$w/err" || fail "an unreadable release.yml is repo-requires-on-target: $(cat "$w/err")"

echo "PASS audit-repo-settings"
