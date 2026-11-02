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
echo "PASS: name-rules"
