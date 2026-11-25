#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: needs a python3 with PyYAML"; exit 77; }

gate() {  # $1 = dir
  (cd "$1" && sh "$S" 2>&1)
}
fails() {  # $1 = label, $2 = dir, $3 = phrase
  out="$(gate "$2")" && { echo "FAIL: $1 must fail"; exit 1; }
  printf '%s\n' "$out" | grep -q -- "$3" || { echo "FAIL: $1 should fail with '$3': $out"; exit 1; }
}
passes() {  # $1 = label, $2 = dir
  out="$(gate "$2")" || { echo "FAIL: $1 must pass: $out"; exit 1; }
}
lacks() {  # $1 = label, $2 = dir, $3 = phrase the output must not carry
  out="$(gate "$2")" || :
  printf '%s\n' "$out" | grep -q -- "$3" && { echo "FAIL: $1 must not report '$3': $out"; exit 1; }
  :
}
add() { (cd "$1" && git add -A) >/dev/null 2>&1; }
rel() { printf '%s/.github/workflows/release.yml' "$1"; }
edit() {  # $1 = dir, $2 = sed script applied to release.yml
  sed "$2" "$(rel "$1")" > "$1/rel.tmp" && mv "$1/rel.tmp" "$(rel "$1")"
}
case_dir() { d="$work/$1"; mkrepo "$d"; }

passes "baseline" "$work/ok"

# spec: SKILL.md "Family conventions" check 40 -- INGREDIENTS.md declares a versioning scheme.
case_dir nover
printf '# Build ingredients\n\n## Conformance deviations\n\n- packager:build/package.sh: fixtures build pkgs with the system packager\n' > "$d/INGREDIENTS.md"; add "$d"
fails "check 40: no ## Versioning" "$d" 'declares no versioning scheme'

case_dir calver
printf '# Build ingredients\n\n## Versioning\n\n- calver\n\n## Conformance deviations\n\n- packager:build/package.sh: fixtures build pkgs with the system packager\n' > "$d/INGREDIENTS.md"; add "$d"
fails "check 40: an unknown scheme" "$d" 'versioning entry .*calver'
fails "check 40: the fix names the grammar" "$d" 'fix the entry it names'

# spec: SKILL.md "Family conventions" check 40b -- release.yml takes its version from release-version.sh.
case_dir vsh
printf '      - run: sh build/version.sh auto\n' >> "$(rel "$d")"; add "$d"
fails "check 40b: build/version.sh" "$d" 'takes its version from version.sh'

case_dir suv
printf '      - run: sh "$SHIPYARD_SCRIPTS/self-upstream-version.sh"\n' >> "$(rel "$d")"; add "$d"
fails "check 40b: self-upstream-version.sh" "$d" 'takes its version from self-upstream-version.sh'

case_dir comment
printf '      # sh "$SHIPYARD_SCRIPTS/resolve-version.sh" is retired\n' >> "$(rel "$d")"; add "$d"
passes "check 40b: a comment naming resolve-version.sh" "$d"

case_dir norv
edit "$d" '/V="$(sh "$SHIPYARD_SCRIPTS\/release-version.sh"/d'; add "$d"
fails "check 40b: no release-version.sh call" "$d" 'never calls release-version.sh'

# spec: SKILL.md "Family conventions" check 40c -- a Linux version-check job runs
#       check-release-version.sh --publishing, and every macOS job and the publish job need it.
case_dir novc
edit "$d" 's/^  version-check:/  vcheck:/'; add "$d"
fails "check 40c: no version-check job" "$d" 'no job named version-check'

case_dir vcmac
edit "$d" '/^  version-check:/,/^  [a-z]/s/ubuntu-latest/macos-26/'; add "$d"
fails "check 40c: version-check on macOS" "$d" 'version-check version-check: .*ubuntu-'

case_dir vcnopub
edit "$d" 's/ --publishing yes//'; add "$d"
fails "check 40c: version-check without --publishing" "$d" 'version-check version-check: .*--publishing'

LINT='  lint:
    runs-on: ubuntu-latest
    steps:
      - run: true'
case_dir maclint
printf '%s\n  mac:\n    runs-on: macos-26\n    needs: [lint]\n    steps:\n      - run: true\n' "$LINT" >> "$(rel "$d")"; add "$d"
fails "check 40c: a macOS job that reaches only lint" "$d" 'version-check mac:'

case_dir macchain
printf '%s\n    needs: [version-check]\n  mac:\n    runs-on: macos-26\n    needs: [lint]\n    steps:\n      - run: true\n' "$LINT" >> "$(rel "$d")"; add "$d"
lacks "check 40c: a macOS job reaching version-check through lint" "$d" 'version-check'

case_dir pubno
edit "$d" 's/needs: \[vm-test, version-check\]/needs: [vm-test]/'; add "$d"
fails "check 40c: publish does not need version-check" "$d" 'version-check publish:'

# spec: SKILL.md "Family conventions" check 40d -- no workflow triggers on a pushed tag.
case_dir tagci
printf "name: ci\non:\n  push:\n    tags: ['*']\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n" > "$d/.github/workflows/ci.yml"; add "$d"
fails "check 40d: ci.yml triggers on a pushed tag" "$d" 'ci.yml triggers on a pushed tag'

echo "PASS: check-family-conventions-9 (checks 40-40d)"
