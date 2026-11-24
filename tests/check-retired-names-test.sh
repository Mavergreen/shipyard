#!/bin/sh
# platform: host-agnostic
#   usage: check-retired-names-test.sh
#          Runs scripts/check-retired-names.sh over inline trees: a retired form of the arm64 check id
#          fails and names its replacement, and arm64 as an arch string passes.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/check-retired-names.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-retired-names-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
unset SHIPYARD_CHECK_RUNLOG SHIPYARD_CHECK_FAILLOG SHIPYARD_CHECK_NOTRUNLOG SHIPYARD_CHECK_SELECTED
fail() { echo "FAIL $1"; exit 1; }

run() {  # $1 = name, $2 = the text of scripts/x.sh, the one tracked file; output in $w/out
  mkdir -p "$w/$1/scripts"; printf '%s\n' "$2" > "$w/$1/scripts/x.sh"; printf 'scripts/x.sh\n' > "$w/$1/FILES"
  (cd "$w/$1" && SHIPYARD_CHECK_FILES="$w/$1/FILES" sh "$S") > "$w/out" 2>&1
}

run dir 'cat .mavergreen/deviations/arm64/x/scope' && fail "a deviation directory under the old id should fail: $(cat "$w/out")"
grep -q '^retired-name: scripts/x.sh uses deviations/arm64, a retired family name' "$w/out" \
  || fail "the failure names the file and the retired form: $(cat "$w/out")"
grep -q '^  fix: write deviations/arch-host$' "$w/out" || fail "the fix names deviations/arch-host: $(cat "$w/out")"

tok=MAVERGREEN_MIN_OS
run minos "MIN=\$$tok" && fail "$tok is retired: $(cat "$w/out")"
grep -q "^retired-name: scripts/x.sh uses $tok, a retired family name" "$w/out" || fail "the failure names $tok: $(cat "$w/out")"
grep -q '^  fix: write .mavergreen/products/<short>/floor (mavergreen_floor)$' "$w/out" || fail "the fix names the floor file: $(cat "$w/out")"

tok=release-needed.sh
run declared "sh \"\$SHIPYARD_SCRIPTS/$tok\"" && fail "$tok is retired: $(cat "$w/out")"
grep -q "^retired-name: scripts/x.sh uses $tok, a retired family name" "$w/out" || fail "the failure names $tok: $(cat "$w/out")"
grep -q '^  fix: write release-decision.sh' "$w/out" || fail "the fix names release-decision.sh: $(cat "$w/out")"

for text in 'clang -arch arm64 -c x.c' "sysctl -n hw.optional.arm64" 'tar xf go1.26.5.darwin_arm64.tar.gz'; do
  run arch "$text" || fail "arm64 as an arch string is no retired name, in '$text': $(cat "$w/out")"
done
echo "PASS check-retired-names"
