#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/.."
T=tests/mavergreen-names.tsv
fail() { echo "FAIL $*"; exit 1; }
TAB="$(printf '\t')"

dups="$(cut -f1 "$T" | sort | uniq -d)"
[ -z "$dups" ] || fail "names with two rows in $T: $dups. A name has one meaning."

used="$(git ls-files | grep -v -E '^(tests/|explain/|scripts/retired-names$|[.]mavergreen/deviations/retired-name/)|[.]md$' | tr '\n' '\0' | xargs -0 grep -h -o 'MAVERGREEN_[A-Z0-9_]*' 2>/dev/null | sort -u)"
for n in $used; do
  grep -q "^$n$TAB" "$T" || fail "$n is used in a tracked file but has no row in $T. Add '<name><TAB><its one meaning>'."
done

pre="CLANG22_CACHE INGREDIENT_ PKG_CACHE PREFIX PRODUCT PRODUCT_NAMES PROGRESS RELEASES ROOT TAR_CACHE VERSION"
while IFS="$TAB" read -r tok rep why; do
  [ -z "$why" ] || continue
  r="${rep%% *}"
  case "$r" in MAVERGREEN_*) ;; *) continue ;; esac
  for p in $pre; do
    [ "$r" != "MAVERGREEN_$p" ] || fail "scripts/retired-names maps $tok to $r, a name that meant something else before P3. A replacement is a new name."
  done
done < scripts/retired-names

reps="$(awk -F'\t' 'NF < 3 { print $2 }' scripts/retired-names | sort | uniq -d)"
[ -z "$reps" ] || fail "two retired tokens map to one replacement: $reps"

echo ok
