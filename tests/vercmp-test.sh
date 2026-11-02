#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/lib/vercmp.sh"
vc() { r="$(mavergreen_vercmp "$1" "$2")" && s=0 || s=$?; echo "$s:$r"; }
[ "$(vc 22.1.8-mavericks.5 22.1.8-mavericks.4)" = 0:1 ]   || { echo "FAIL vercmp: .5 > .4"; exit 1; }
[ "$(vc 22.1.8-mavericks.10 22.1.8-mavericks.9)" = 0:1 ]  || { echo "FAIL vercmp: .10 > .9"; exit 1; }
[ "$(vc 22.1.8-mavericks.5 22.1.8-mavericks.12)" = 0:-1 ] || { echo "FAIL vercmp: .5 < .12"; exit 1; }
[ "$(vc 4.4.5-mavericks.2 4.4.5-mavericks.2)" = 0:0 ]     || { echo "FAIL vercmp: equal"; exit 1; }
[ "$(vc 20261019.1 20261018.12)" = 0:1 ]                  || { echo "FAIL vercmp: dates"; exit 1; }
[ "$(vc 9.9p2 9.9p1)" = 0:1 ]                             || { echo "FAIL vercmp: pN"; exit 1; }
[ "$(vc 22.1.8-mavergreen.1 22.1.8-mavericks.1)" = 0:0 ]  || { echo "FAIL vercmp: mavergreen == mavericks"; exit 1; }
[ "$(vc 1.0 1.0.0)" = 0:0 ]                               || { echo "FAIL vercmp: trailing zero"; exit 1; }
[ "$(vc 1.2 1.10.1)" = 0:-1 ]                             || { echo "FAIL vercmp: 1.2 < 1.10.1, numerically and with fewer components"; exit 1; }
[ "$(vc 2 1.9.9)" = 0:1 ]                                 || { echo "FAIL vercmp: 2 > 1.9.9"; exit 1; }
[ "$(vc 1.0.0.1 1.0)" = 0:1 ]                             || { echo "FAIL vercmp: 1.0.0.1 > 1.0"; exit 1; }
[ "$(vc 22.1.9 22.1.8-mavericks.12)" = 0:1 ]              || { echo "FAIL vercmp: 22.1.9 > 22.1.8-mavericks.12"; exit 1; }
[ "$(vc 1.0-rc1 1.0)" = 2: ]                              || { echo "FAIL vercmp: -rc1 must be status 2"; exit 1; }
[ "$(vc 22.1.8-rc1 22.1.8-mavericks.12)" = 2: ]           || { echo "FAIL vercmp: -rc1 against a mavericks pin must be status 2"; exit 1; }
[ "$(vc abc 1)" = 2: ]                                    || { echo "FAIL vercmp: abc must be status 2"; exit 1; }
[ "$(vc v1.0 1.0)" = 2: ]                                 || { echo "FAIL vercmp: a v prefix must be status 2"; exit 1; }
[ "$(vc '' 1)" = 2: ]                                     || { echo "FAIL vercmp: an empty version must be status 2"; exit 1; }
[ "$(vc 1 '')" = 2: ]                                     || { echo "FAIL vercmp: an empty pin must be status 2"; exit 1; }
[ "$(vc 1..2 1.2)" = 2: ]                                 || { echo "FAIL vercmp: an empty component must be status 2"; exit 1; }
echo "PASS: vercmp"
