#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/ingredient-pins.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-pins-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

out="$(MAVERGREEN_ROOT="$work" sh "$S")" || fail "a repo with no .mavergreen/ exits 0"
[ -z "$out" ] || fail "a repo with no .mavergreen/ prints nothing, got '$out'"

mkdir -p "$work/.mavergreen/ingredients"
out="$(MAVERGREEN_ROOT="$work" sh "$S")" || fail "an empty ingredients/ exits 0"
[ -z "$out" ] || fail "an empty ingredients/ prints nothing, got '$out'"

mkdir "$work/.mavergreen/ingredients/zlib" "$work/.mavergreen/ingredients/Zeta" "$work/.mavergreen/ingredients/clang22"
printf '1.3.1\n' > "$work/.mavergreen/ingredients/zlib/VERSION"
out="$(MAVERGREEN_ROOT="$work" sh "$S")"
[ "$out" = "Zeta
clang22
zlib" ] || fail "each ingredient directory, one per line in C order, got '$out'"

echo "PASS ingredient-pins"
