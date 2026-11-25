#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "Versioning" -- INGREDIENTS.md's "## Versioning" section declares each product's scheme.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/versioning.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/versioning-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
TAB="$(printf '\t')"

ing() {
  mkdir -p "$1"; d="$1"; shift
  { printf '%s\n' '# Build ingredients' '' '## Conformance deviations' '' '- scheme: x' '' '## Versioning' ''
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '%s\n' '' '## Declared state' '' '- upstream: UPSTREAM_VERSION'
  } > "$d/INGREDIENTS.md"
}
fails() {   # $1 = dir, $2 = pattern, rest = extra args
  d="$1"; pat="$2"; shift 2
  if sh "$S" --root "$d" "$@" >"$d.out" 2>&1; then echo "FAIL: $d should exit 1"; exit 1; fi
  grep -q -- "$pat" "$d.out" || { echo "FAIL: $d output lacks '$pat': $(cat "$d.out")"; exit 1; }
}
eq() { [ "$1" = "$2" ] || { echo "FAIL: $3: got '$1'"; exit 1; }; }

ing "$w/a" '- port'
eq "$(sh "$S" --root "$w/a")" "*${TAB}port${TAB}" "single form"
eq "$(sh "$S" --root "$w/a" --product anything)" "port${TAB}" "single form per product"

ing "$w/b" '- swift-runtime: port components/swift-runtime/UPSTREAM_VERSION' '- swift-toolchain: port'
eq "$(sh "$S" --root "$w/b")" "$(printf 'swift-runtime\tport\tcomponents/swift-runtime/UPSTREAM_VERSION\nswift-toolchain\tport\t')" "two entries in order"
eq "$(sh "$S" --root "$w/b" --product swift-toolchain)" "port${TAB}" "per-product entry"
eq "$(sh "$S" --root "$w/b" --product swift-runtime)" "port${TAB}components/swift-runtime/UPSTREAM_VERSION" "upstream file exposed"
fails "$w/b" 'declares no versioning scheme for nope' --product nope

n=0
for s in port self-upstream-date semver date-semver counter; do
  n=$((n + 1)); ing "$w/s$n" "- $s"
  eq "$(sh "$S" --root "$w/s$n" --product x)" "$s${TAB}" "scheme $s"
done
ing "$w/cal" '- calver'
fails "$w/cal" calver
for s in port self-upstream-date semver date-semver counter; do grep -q -- "$s" "$w/cal.out" || { echo "FAIL: calver error omits $s"; exit 1; }; done
ing "$w/cf" '- counter VERSION'
eq "$(sh "$S" --root "$w/cf" --product x)" "counter${TAB}VERSION" "counter takes a file"

ing "$w/dup" '- a: semver' '- a: port'
fails "$w/dup" 'declared twice'
ing "$w/mix" '- port' '- a: semver'
fails "$w/mix" single
ing "$w/two" '- port' '- semver'
fails "$w/two" .
ing "$w/ex" '- semver extra'
fails "$w/ex" 'only port and counter'
ing "$w/bad" '- Bad_Short: port'
fails "$w/bad" Bad_Short

ing "$w/pr" 'Some prose here.' '- a: semver' 'More prose.' '' '## Later' '' '- x: semver'
eq "$(sh "$S" --root "$w/pr")" "a${TAB}semver${TAB}" "prose ignored, section ends at next heading"

mkdir -p "$w/none"
eq "$(sh "$S" --root "$w/none")" "" "no INGREDIENTS.md"
printf '%s\n' '# Build ingredients' 'prose' > "$w/none/INGREDIENTS.md"
eq "$(sh "$S" --root "$w/none")" "" "no section"
fails "$w/none" 'declares no versioning scheme for x' --product x
if sh "$S" --bogus >/dev/null 2>&1; then echo "FAIL: usage error"; exit 1; else [ $? -eq 2 ] || { echo "FAIL: usage exit not 2"; exit 1; }; fi

echo "PASS: versioning"
