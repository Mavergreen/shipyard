#!/bin/sh
# platform: host-agnostic
#   usage: fetch-host-libcxx-test.sh
# spec: scripts/fetch_host_libcxx.sh header -- a clang22 of another LLVM version than the llvm-project pin is refused,
#       both versions named; a cached prefix is printed with no network; on x86_64 Linux the prefix is built.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fetch-host-libcxx-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; [ ! -f "$T/err" ] || sed 's/^/    | /' "$T/err"; fails=$((fails + 1)); }
S="$ROOT/scripts/fetch_host_libcxx.sh"
pin=22.1.8; digest=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

mkdir -p "$T/pin"
printf '22.1.9-mavericks.1\n' >"$T/pin/version"
printf '%s %s\n' "$pin" "$digest" >"$T/pin/llvm-project"
rc=0; sh "$S" "$T/pin" "$T/clang" >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" = 1 ] && grep -q '22\.1\.9' "$T/err" && grep -q '22\.1\.8' "$T/err"; then
  pass 'a clang22 of another LLVM version is refused, naming both versions'
else fail "mismatch: exit $rc"; fi

printf '22.1.8-mavericks.1\n' >"$T/pin/version"
mkdir -p "$T/cache/22.1.8-mavericks.1/lib" "$T/cache/22.1.8-mavericks.1/include/c++/v1"
: >"$T/cache/22.1.8-mavericks.1/lib/libc++.a"; : >"$T/cache/22.1.8-mavericks.1/include/c++/v1/__config_site"
rc=0; out=$(MAVERGREEN_HOST_LIBCXX_CACHE="$T/cache" SHIPYARD_FETCH_TRIES=1 MAVERGREEN_RELEASES="file://$T/none" \
  sh "$S" "$T/pin" "$T/clang" 2>"$T/err") || rc=$?
if [ "$rc" = 0 ] && [ "$out" = "$T/cache/22.1.8-mavericks.1" ]; then
  pass 'a cached prefix is printed without a fetch'
else fail "cache: exit $rc, printed '$out'"; fi

if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
  cp "$ROOT/components/clang22/version" "$ROOT/components/clang22/linux-sha256" "$T/pin/"
  printf '%s %s\n' "$pin" "$digest" >"$T/pin/llvm-project"
  CL=$(sh "$ROOT/scripts/fetch_clang22.sh" "$T/pin" 2>"$T/err") || { fail 'fetch clang22'; CL=; }
  if [ -n "$CL" ]; then
    rc=0; out=$(MAVERGREEN_HOST_LIBCXX_CACHE="$T/full" sh "$S" "$T/pin" "$CL" 2>"$T/err") || rc=$?
    if [ "$rc" = 0 ] && [ -f "$out/lib/libc++.a" ] && [ -f "$out/lib/libc++abi.a" ] && [ -f "$out/include/c++/v1/__config_site" ]; then
      pass "the full build prints a prefix holding libc++.a and libc++abi.a: $out"
    else fail "full build: exit $rc, printed '$out'"; fi
  fi
else echo "NOTE: the full build runs on x86_64 Linux only"; fi
[ "$fails" -eq 0 ]
