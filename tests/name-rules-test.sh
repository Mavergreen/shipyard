#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
LC_ALL=en_US.UTF-8; export LC_ALL
. "$here/../scripts/lib/name-rules.sh"
fail() { echo "FAIL: $1"; exit 1; }
rc() { _r=0; mavergreen_name_ok "$1" || _r=$?; echo "$_r"; }
for n in shipyard go126 clang22-cross 1password a; do
  [ "$(rc "$n")" = 0 ] || fail "'$n' is a short name the rules allow"
done
for n in '' -x Go126 B Porthole cmakE a_b 'a b' a.b é; do
  [ "$(rc "$n")" = 1 ] || fail "'$n' is outside lowercase ASCII letters, digits and hyphens, so it must be refused (1), even in $LC_ALL"
done
for n in var bin sbin share mavergreen system-replace base; do
  [ "$(rc "$n")" = 2 ] || fail "'$n' is reserved by the install layout, so it must be refused as reserved (2)"
done
alts() { sed -n "s/^.*\\(''|.*\\)) return 1 ;;.*\$/\\1/p" "$1" | head -n 1 | tr '|' '\n'; }
rules="$(alts "$here/../scripts/lib/name-rules.sh")"
helper="$(alts "$here/../scripts/mavergreen.sh")"
[ -n "$rules" ] && [ -n "$helper" ] || fail "cannot read the refused patterns of lib/name-rules.sh and mavergreen.sh's valid()"
class() { printf '%s\n' "$1" | grep '^\*\[!.*\]\*$' || :; }
[ -n "$(class "$rules")" ] && [ "$(class "$helper")" = "$(class "$rules")" ] \
  || fail "mavergreen.sh's valid() refuses names outside $(class "$rules"), as lib/name-rules.sh does; it has $(class "$helper")"
words="$(printf '%s\n' "$helper" | grep -v -e "^''\$" -e '^-\*$' -e '^\*\[!' | tr '\n' ' ')"
[ "$words" = "$mavergreen_reserved_names " ] \
  || fail "mavergreen.sh's valid() reserves exactly \$mavergreen_reserved_names ($mavergreen_reserved_names), word for word; it reserves $words"
echo "PASS: name-rules"
