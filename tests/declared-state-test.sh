#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "A release is a declared state, not an event" -- the "## Declared state" section
#       of INGREDIENTS.md is ONE machine-readable list, deliberately a subset of the file's prose
#       table above it; a second declaration file would be a second list of the same pins.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/declared-state.sh"
_tmp="${TMPDIR:-/tmp}"                    # macOS sets TMPDIR with a trailing slash
w="$(mktemp -d "${_tmp%/}/declared-state-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
TAB="$(printf '\t')"

ing() {   # $1 = dir, rest = lines of the "## Declared state" section
  mkdir -p "$1"; d="$1"; shift
  { printf '%s\n' '# Build ingredients' '' '| Ingredient | Pinned in |' '|---|---|' \
      '| CMake 4.4.3 | `pins.env` |' '' '## Conformance deviations' '' \
      '- scheme: shipyard versions are not <upstream>-mavericks.N' '' '## Declared state' ''
    for l in "$@"; do printf '%s\n' "$l"; done
  } > "$d/INGREDIENTS.md"
}

ing "$w/a" '- upstream: UPSTREAM_VERSION' '- cmake: pins.env:CMAKE_VERSION'
got="$(sh "$S" "$w/a")"
want="$(printf 'upstream%sUPSTREAM_VERSION\ncmake%spins.env:CMAKE_VERSION' "$TAB" "$TAB")"
[ "$got" = "$want" ] || { echo "FAIL: both entry shapes must render in declaration order, tab-separated: got '$got'"; exit 1; }

ing "$w/b" '- upstream: UPSTREAM_VERSION'
got="$(sh "$S" "$w/b")"
[ "$got" = "$(printf 'upstream%sUPSTREAM_VERSION' "$TAB")" ] \
  || { echo "FAIL: the OTHER section's entries are not ours, even though both sections use '- x: y' -- section scoping leaked a deviation in: got '$got'"; exit 1; }

ing "$w/c" '- upstream: UPSTREAM_VERSION' '' '## Something else' '' '- cmake: not-ours'
got="$(sh "$S" "$w/c")"
[ "$got" = "$(printf 'upstream%sUPSTREAM_VERSION' "$TAB")" ] \
  || { echo "FAIL: a section must end at the next heading, but it did not: got '$got'"; exit 1; }

mkdir -p "$w/d"; printf '%s\n' '# Build ingredients' '' 'prose only' > "$w/d/INGREDIENTS.md"
got="$(sh "$S" "$w/d")"; rc=$?
[ "$rc" = 0 ] || { echo "FAIL: a repo that has not migrated (no such section) is not an error, should exit 0, got $rc"; exit 1; }
[ -z "$got" ] || { echo "FAIL absent section printed '$got'"; exit 1; }

mkdir -p "$w/e"
got="$(sh "$S" "$w/e")"
[ -z "$got" ] || { echo "FAIL: no INGREDIENTS.md at all should be silent, like deviations.sh -- printed '$got'"; exit 1; }

ing "$w/f" '- upstream:'
if sh "$S" "$w/f" >"$w/f.out" 2>&1; then echo "FAIL: an entry with no value is fatal, exactly as a deviation with no reason is -- valueless entry was accepted"; exit 1; fi
grep -q upstream "$w/f.out" || { echo "FAIL valueless entry error does not name it"; exit 1; }

ing "$w/g" '- Upstream Version: UPSTREAM_VERSION'
if sh "$S" "$w/g" >"$w/g.out" 2>&1; then echo "FAIL: the name is the digest key, so a non-canonical name is fatal and cannot be freeform -- it was accepted"; exit 1; fi

ing "$w/h" '- upstream: UPSTREAM_VERSION' '- cmake: pins.env:A' '- cmake: pins.env:B'
if sh "$S" "$w/h" >"$w/h.out" 2>&1; then echo "FAIL: the same name twice is fatal, not last-one-wins -- duplicate name was accepted"; exit 1; fi
grep -q 'declared twice' "$w/h.out" \
  || { echo "FAIL: must grep the REASON, not the name -- the parser prints \"cmake<TAB>pins.env:A\" for the first valid entry before it ever reaches the duplicate, so grep -q cmake would pass even if the duplicate check were a bare exit 1 that said nothing at all: $(cat "$w/h.out")"; exit 1; }

ing "$w/i" '- cmake: pins.env:CMAKE_VERSION'
if sh "$S" "$w/i" >"$w/i.out" 2>&1; then echo "FAIL: a section with entries but no upstream is fatal, since there would be no version to compare against -- missing upstream entry was accepted"; exit 1; fi
grep -q upstream "$w/i.out" || { echo "FAIL missing-upstream error does not say so"; exit 1; }

ing "$w/j" 'What this product IS, for release purposes:' '' '- upstream: UPSTREAM_VERSION'
got="$(sh "$S" "$w/j")"
[ "$got" = "$(printf 'upstream%sUPSTREAM_VERSION' "$TAB")" ] \
  || { echo "FAIL: prose inside the section must be ignored, so the section can explain itself: got '$got'"; exit 1; }

echo "PASS: declared-state"
