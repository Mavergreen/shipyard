#!/bin/sh
# platform: host-agnostic
#   usage: maintainer-tests-10.9-test.sh
#          The 10.9 half of tests/maintainer-tests runs every check's fixtures there (the flag-day P1
#          ruling R5) and the tests the 10.9 guest once ran, so each runs without git (check-fixtures-run.sh
#          hides git itself) and guards its python3, which a 10.9 box has only from the python-315 release
#          .mavergreen/ingredients/python-315/VERSION pins. Linux runs the same fixture runner strictly and
#          with git hidden, so the counts compare across hosts.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
fail() { echo "FAIL: $1"; exit 1; }
list="$here/maintainer-tests"
awk '$1 == "10.9" && $2 == "tests/check-fixtures-run.sh" { found = 1 } END { exit !found }' "$list" \
  || fail "tests/maintainer-tests does not run tests/check-fixtures-run.sh on the 10.9 box"
awk '$1 == "10.9" { print $2 }' "$list" | while IFS= read -r t; do
  [ -f "$root/$t" ] || fail "tests/maintainer-tests names $t, which does not exist"
  if [ "$t" != tests/check-fixtures-run.sh ] && grep -qE '(^|[^[:alnum:]_.-])git[[:space:]]' "$root/$t"; then
    fail "$t runs git, which a 10.9 box need not have"
  fi
  if grep -q 'python3' "$root/$t" && ! grep -qE 'command -v python3|chk_python3|which python3' "$root/$t"; then
    fail "$t uses python3 without guarding for its absence"
  fi
done
sed -n 1p "$root/.mavergreen/ingredients/python-315/VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-mavericks\.[0-9]+$' \
  || fail ".mavergreen/ingredients/python-315/VERSION pins one python-315 release"
grep -q 'sh tests/check-fixtures-run.sh --strict' "$root/.github/workflows/linux-host.yml" || fail "linux-host.yml runs the fixture runner strictly"
grep -q 'sh tests/check-fixtures-run.sh --no-git' "$root/.github/workflows/linux-host.yml" || fail "linux-host.yml runs the fixture runner with git hidden"
echo "PASS: maintainer-tests-10.9"
