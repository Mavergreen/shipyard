#!/bin/sh
# platform: host-agnostic
#   usage: shipyard-launcher-test.sh
#          Drives scripts/shipyard-launcher.sh, installed as <root>/shipyard/bin/shipyard-{cmake,ctest,
#          cpack}, against stub tools in <root>/cmake/bin. Exit 0 clean, 1 on failure.
# spec: 2026-10-09 C4
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; src="$(cd "$here/.." && pwd)"
L="$src/scripts/shipyard-launcher.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/shipyard-launcher.XXXXXX")"; trap 'rm -rf "$w"' EXIT
# platform: the launcher resolves its own links physically, and macOS's TMPDIR is under /var, itself a
#           link to /private/var, so every expected path is the physical one.
w="$(cd -P "$w" && pwd)"
root="$w/mg"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

mkdir -p "$root/shipyard/bin" "$root/cmake/bin" "$root/bin"
for t in cmake ctest cpack; do
  cp "$L" "$root/shipyard/bin/shipyard-$t"; chmod +x "$root/shipyard/bin/shipyard-$t"
  cat > "$root/cmake/bin/$t" <<EOF
#!/bin/sh
echo "tool=$t"
for a in "\$@"; do echo "arg=[\$a]"; done
echo "CMAKE_PREFIX_PATH=\${CMAKE_PREFIX_PATH-<unset>}"
EOF
  chmod +x "$root/cmake/bin/$t"
  ln -s "shipyard-$t" "$root/shipyard/bin/$t"
  ln -s "../shipyard/bin/shipyard-$t" "$root/bin/shipyard-$t"
done
sy="$root/shipyard"

expect() {  # $1 = what  $2 = expected stdout; the rest is the command
  _what="$1"; _want="$2"; shift 2
  _rc=0; _got="$("$@" 2>&1)" || _rc=$?
  [ "$_rc" -eq 0 ] || { fail "$_what: exit $_rc: $_got"; return 0; }
  [ "$_got" = "$_want" ] || fail "$_what: got
$_got
want
$_want"
}
nl='
'
args_out="arg=[a b]${nl}arg=[]${nl}arg=[c]"

expect "shipyard-cmake runs cmake with its args intact and appends shipyard to an unset CMAKE_PREFIX_PATH" \
  "tool=cmake${nl}${args_out}${nl}CMAKE_PREFIX_PATH=$sy" \
  env -u CMAKE_PREFIX_PATH "$sy/bin/shipyard-cmake" "a b" "" c
expect "an empty CMAKE_PREFIX_PATH gets no leading colon" \
  "tool=cmake${nl}CMAKE_PREFIX_PATH=$sy" \
  env CMAKE_PREFIX_PATH= "$sy/bin/shipyard-cmake"
expect "a caller's CMAKE_PREFIX_PATH stays first" \
  "tool=cmake${nl}CMAKE_PREFIX_PATH=/dev/p:$sy" \
  env CMAKE_PREFIX_PATH=/dev/p "$sy/bin/shipyard-cmake"
for t in ctest cpack; do
  expect "shipyard-$t runs $t with its args intact and leaves CMAKE_PREFIX_PATH alone" \
    "tool=$t${nl}${args_out}${nl}CMAKE_PREFIX_PATH=/dev/p" \
    env CMAKE_PREFIX_PATH=/dev/p "$sy/bin/shipyard-$t" "a b" "" c
done

expect "through the farm link it still finds <root>/cmake" \
  "tool=cmake${nl}CMAKE_PREFIX_PATH=$sy" \
  env -u CMAKE_PREFIX_PATH "$root/bin/shipyard-cmake"
mkdir -p "$w/rust/bin"
ln -s "$root/bin/shipyard-cmake" "$w/rust/bin/shipyard-cmake"
ln -s shipyard-cmake "$w/rust/bin/cmake"
expect "through a second link in another directory (rust's <dir>/cmake -> shipyard-cmake) it still finds <root>/cmake" \
  "tool=cmake${nl}CMAKE_PREFIX_PATH=$sy" \
  env -u CMAKE_PREFIX_PATH "$w/rust/bin/cmake"
expect "found on PATH it still finds <root>/cmake" \
  "tool=ctest${nl}CMAKE_PREFIX_PATH=<unset>" \
  env -u CMAKE_PREFIX_PATH PATH="$root/bin:/usr/bin:/bin" shipyard-ctest
expect "run by a relative path it still finds <root>/cmake" \
  "tool=cmake${nl}CMAKE_PREFIX_PATH=$sy" \
  sh -c 'cd "$1" && exec env -u CMAKE_PREFIX_PATH ./shipyard-cmake' sh "$root/bin"
# platform: a relative $0 with no leading ./ resolves to bin/../shipyard/bin, which an exported CDPATH
#           would send to the decoy's copy of that path, printing it.
mkdir -p "$w/decoy/bin" "$w/decoy/shipyard/bin"
expect "run by a relative path with CDPATH exported it still finds <root>/cmake" \
  "tool=cmake${nl}CMAKE_PREFIX_PATH=$sy" \
  sh -c 'cd "$1" && CDPATH="$2" && export CDPATH && exec env -u CMAKE_PREFIX_PATH bin/shipyard-cmake' sh "$root" "$w/decoy"
for t in cmake ctest cpack; do
  want="tool=$t${nl}CMAKE_PREFIX_PATH=<unset>"
  [ "$t" != cmake ] || want="tool=cmake${nl}CMAKE_PREFIX_PATH=$sy"
  expect "the compatibility link shipyard/bin/$t behaves as shipyard-$t" "$want" \
    env -u CMAKE_PREFIX_PATH "$sy/bin/$t"
done

rc=0; out="$(sh "$L" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "run under any name but the three, the launcher must exit 2; got $rc: $out"

mv "$root/cmake" "$w/cmake-aside"
for t in cmake ctest cpack; do
  rc=0; out="$("$root/bin/shipyard-$t" --version 2>"$w/err")" || rc=$?
  want="shipyard-$t: shipyard needs the Mavergreen cmake product, which isn't installed: https://github.com/Mavergreen/cmake/releases/latest -- install it, then run this again."
  [ "$rc" -eq 1 ] || fail "with no cmake product, shipyard-$t must exit 1; got $rc"
  [ -z "$out" ] || fail "with no cmake product, shipyard-$t must print nothing on stdout; got: $out"
  [ "$(cat "$w/err")" = "$want" ] || fail "with no cmake product, shipyard-$t must say exactly
$want
got
$(cat "$w/err")"
done

[ "$fails" -eq 0 ] || { echo "FAIL: $fails case(s) in shipyard-launcher"; exit 1; }
echo "PASS: shipyard-launcher"
