#!/bin/sh
# platform: macOS-only -- runs the compat guard with the readers its seam finds on this Mac, with no LIPO, NM, OTOOL or STRINGS set; run by hand on the 10.9 box (tests/maintainer-tests)
#   usage: compat-guard-native-test.sh
#          compat_guard.bats names clang22's readers for every case, so this is the one run of
#          assert_binary_compatible.sh on the readers it finds itself (lib/macho-tools.sh). Exit 77 when
#          it finds none.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
G="$here/../scripts/assert_binary_compatible.sh"
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/..")"
S9="$(sh "$here/../scripts/fetch_sdk.sh")"
w="$(mktemp -d "${TMPDIR:-/tmp}/compat-native.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cc() { "$CL/bin/clang" --no-default-config -w -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target x86_64-apple-macos10.9 -isysroot "$S9" -Wl,-platform_version,macos,10.9,10.9 "$@"; }
printf 'int main(void){return 0;}\n' > "$w/clean.c"
printf 'extern int mav_test_post109(void);\nint main(void){return mav_test_post109();}\n' > "$w/leak.c"
cc "$w/clean.c" -o "$w/clean"
cc -Wl,-undefined,dynamic_lookup "$w/leak.c" -o "$w/leak"
run() { env -u LIPO -u NM -u OTOOL -u STRINGS "$@"; }
run sh -c '. "$1/lib/macho-tools.sh"; for v in LIPO NM OTOOL STRINGS; do mach_tool "$v" || exit 1; done' sh "$here/../scripts" >/dev/null 2>&1 \
  || { echo "SKIP: the seam finds no LLVM Mach-O readers on this Mac"; exit 77; }
out="$(run sh "$G" "$w/clean" 2>&1)" || { echo "FAIL: a clean binary must pass on the readers the seam finds:"; printf '%s\n' "$out" | sed 's/^/    | /'; exit 1; }
rc=0; out="$(run env MAVERICKS_POST_10_9_SYMBOLS=_mav_test_post109 sh "$G" "$w/leak" 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q _mav_test_post109 \
  || { echo "FAIL: a post-10.9 import must fail on the readers the seam finds, naming it (exit $rc):"; printf '%s\n' "$out" | sed 's/^/    | /'; exit 1; }
echo "PASS: compat-guard-native"
