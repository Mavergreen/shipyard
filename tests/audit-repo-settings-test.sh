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
cat > "$w/bin/gh" <<'STUB'
#!/bin/sh
d="$GH_STUB"
case "$1 $2" in
  "auth status") [ -f "$d/noauth" ] && exit 1; cat "$d/scopes"; exit 0 ;;
  "repo list") cat "$d/repos"; exit 0 ;;
esac
case "$2" in
  repos/*/shipyard) cat "$d/shipyard-admin"; exit 0 ;;
  repos/*/contents/*) r="${2#repos/*/}"; r="${r%%/contents*}"; [ -f "$d/product-$r" ] && exit 0; exit 1 ;;
  repos/*/branches/main/protection) r="${2#repos/*/}"; r="${r%%/branches*}"; [ -f "$d/ctx-$r" ] || exit 1; cat "$d/ctx-$r"; exit 0 ;;
  repos/*) r="${2#repos/*/}"; cat "$d/am-$r"; exit 0 ;;
esac
exit 1
STUB
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
}
printf 'repo-auto-merge\trepo-state\tscripts/audit-repo-settings.sh\tx\tP1\nrepo-required-context\trepo-state\tscripts/audit-repo-settings.sh\tx\tP1\n' > "$w/reg"
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
grep -qx 'shipyard-check: 2 checks, 2 failed' "$w/out" || fail "the dispatcher should count both ids failed: $(cat "$w/out")"

reset; printf 'true\n' > "$w/gh/am-noauto"; printf 'build\n' > "$w/gh/ctx-noprot"
run "$SC" --repo-state
[ "$rc" -eq 0 ] || fail "a healthy org under --repo-state should exit 0, got $rc: $(cat "$w/err")"
grep -qx 'shipyard-check: 2 checks, 0 failed' "$w/out" || fail "the dispatcher should count two checks: $(cat "$w/out")"

echo "PASS audit-repo-settings"
